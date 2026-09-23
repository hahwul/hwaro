# Built-in asset pipeline for CSS/JS bundling, minification, and fingerprinting
#
# Processes static CSS/JS files into optimized bundles with content-hash
# based filenames for cache busting.

require "digest/sha256"
require "file_utils"
require "../utils/css_minifier"
require "../utils/js_minifier"
require "../utils/logger"
require "../utils/output_guard"
require "../utils/path_utils"
require "../models/config"
require "./sass_compiler"

module Hwaro
  module Assets
    class Pipeline
      # Manifest mapping original names to fingerprinted output paths
      # e.g. "main.css" => "/assets/main.a1b2c3d4.css"
      getter manifest : Hash(String, String)

      # Output files this run actually wrote, as filesystem paths under the
      # build output directory. The caller (AssetHooks) claims them so a
      # `--cache` build — which never wipes the output directory — can drop
      # the previous fingerprinted bundle instead of accumulating one file
      # per edit in `public/assets/` forever.
      getter written_paths : Array(String)

      # `sass_enabled` mirrors `[sass].enabled`: `.scss` bundle entries
      # compile through the built-in compiler only when the feature is on;
      # otherwise they concatenate verbatim (pre-Sass behavior, and the
      # escape hatch for sources outside the supported subset).
      def initialize(@config : Models::AssetsConfig, @base_url : String, @sass_enabled : Bool = false)
        @manifest = {} of String => String
        @written_paths = [] of String
      end

      def process(output_dir : String)
        return unless @config.enabled

        assets_output = File.join(output_dir, @config.output_dir)
        # `[assets] output_dir` is joined onto the build output directory and,
        # unchanged, becomes the manifest URL every page links. A traversing
        # value ("../../oops") published the fingerprinted bundles above the
        # site root — public/ ended up with no CSS at all and every page linked
        # a 404. The source side is already validated in process_bundle; this is
        # the missing check on the destination side.
        unless Utils::OutputGuard.within_output_dir?(assets_output, output_dir)
          Logger.warn "Asset pipeline: output_dir '#{@config.output_dir}' escapes the output directory; skipping asset processing."
          return
        end
        # The directory is created by `process_bundle` when a bundle actually
        # has bytes to write. Creating it up front left an empty `assets/`
        # in the output of every build that produced no bundle (all sources
        # missing, or `bundles` empty) — a stray directory a cold build ships
        # and a `--cache` build, which prunes emptied directories, does not.
        @config.bundles.each do |bundle|
          process_bundle(bundle, assets_output)
        end
      end

      private def process_bundle(bundle : Models::AssetBundleConfig, assets_output : String)
        separator = bundle_separator(bundle.name)
        css_bundle = File.extname(bundle.name).downcase == ".css"
        # Output-root-relative directory the bundle is published in
        # ("assets", or "assets/vendor" for a "vendor/x.css" bundle name).
        bundle_dir = Path.posix(@config.output_dir, File.dirname(bundle.name)).normalize.to_s
        # Read and concatenate source files
        contents = String.build do |io|
          wrote_any = false
          bundle.files.each do |file|
            # Validate source path stays within source_dir
            source = File.join(@config.source_dir, file)
            source_real = File.expand_path(source)
            source_dir_real = File.expand_path(@config.source_dir)
            unless source_real == source_dir_real || source_real.starts_with?(source_dir_real + "/")
              Logger.warn "Asset pipeline: source file outside source directory: #{file}"
              next
            end
            unless File.exists?(source)
              Logger.warn "Asset pipeline: source file not found: #{source}"
              next
            end
            # Symlink targets outside the configured source_dir must not be
            # read into a published bundle. Bound against source_dir (not
            # Dir.current) so mktmpdir-based tests and custom source roots
            # still work while still rejecting /etc-style escapes.
            unless Utils::PathUtils.resolves_within?(source, source_dir_real)
              Logger.warn "Asset pipeline: source outside source directory (symlink?): #{file}"
              next
            end
            # Keyed off what was actually written, not the loop index: a
            # skipped first entry (missing file, escaping symlink) used to
            # leave the bundle starting with a stray separator.
            io << separator if wrote_any
            content = File.read(source)
            # `.scss` bundle entries compile before concatenation when the
            # built-in Sass feature is on; verbatim otherwise.
            if @sass_enabled && file.ends_with?(".scss")
              content = SassCompiler.compile_source(content, source)
            end
            content = rebase_css_urls(content, file, bundle_dir) if css_bundle && publishes_source_dir?
            io << content
            wrote_any = true
          end
        end

        if contents.empty?
          Logger.warn "Asset pipeline: bundle '#{bundle.name}' produced empty output"
          return
        end

        # A `.scss`-named bundle would publish with a non-CSS extension and
        # skip the extension-keyed minifier — almost certainly a mistake.
        if bundle.name.ends_with?(".scss")
          Logger.warn "Asset pipeline: bundle '#{bundle.name}' keeps the .scss extension in output — name the bundle '#{bundle.name.sub(/\.scss\z/, ".css")}' to serve it as CSS."
        end

        # Minify if enabled
        if @config.minify
          contents = minify(contents, bundle.name)
        end

        # Determine output filename (with or without fingerprint)
        output_name = if @config.fingerprint
                        fingerprint(bundle.name, contents)
                      else
                        bundle.name
                      end

        # Write the bundle
        output_path = File.join(assets_output, output_name)
        # A bundle `name` may legitimately carry a subdirectory ("vendor/x.css"),
        # so it is joined rather than basenamed — which means it can also carry
        # "..". Bound it to the asset output directory before writing.
        unless Utils::OutputGuard.within_output_dir?(output_path, assets_output)
          Logger.warn "Asset pipeline: bundle '#{bundle.name}' resolves outside the asset output directory; skipping."
          return
        end
        Hwaro::Utils::FileSafe.mkdir_p(File.dirname(output_path))
        File.write(output_path, contents)
        @written_paths << output_path

        # Record in manifest
        manifest_path = "/" + File.join(@config.output_dir, output_name)
        @manifest[bundle.name] = manifest_path

        Logger.debug "  Asset: #{bundle.name} → #{manifest_path} (#{contents.bytesize} bytes)"
      end

      # `static/` is copied to the output root verbatim, so a file beside a
      # stylesheet in `source_dir = "static"` is published beside that
      # stylesheet's own copy. Any other source_dir is not published, and
      # its relative URLs have no published target to rebase onto.
      private def publishes_source_dir? : Bool
        File.expand_path(@config.source_dir) == File.expand_path("static")
      end

      CSS_URL_RE = /url\(\s*(["']?)([^"')]+?)\1\s*\)/i

      # A stylesheet's relative `url(...)` resolves against the stylesheet's
      # own location, but the bundle is published elsewhere
      # (`/assets/main.<hash>.css`): `url(img/x.png)` written in
      # `static/css/a.css` pointed at `/assets/img/x.png`, a 404, and vendor
      # CSS lost its fonts the same way. Rewrite such a URL to the same file
      # seen from the bundle's directory — but only when that file exists
      # beside the source, so a URL the author already wrote relative to the
      # bundle output keeps working. Relative results keep subpath
      # (`base_path`) deploys working.
      private def rebase_css_urls(css : String, file : String, bundle_dir : String) : String
        source_dir = File.dirname(file)
        return css if source_dir == bundle_dir
        css.gsub(CSS_URL_RE) do |whole|
          quote = $1
          url = $2.strip
          next whole if url.empty? || url.starts_with?('/') || url.starts_with?('#') ||
                        url.includes?("://") || url.starts_with?("//") || url.matches?(/\A[a-z][a-z0-9+.-]*:/i)
          path_part = url.split(/[?#]/, 2).first
          suffix = url[path_part.size..]
          target = Path.posix(source_dir, path_part).normalize
          next whole if target.to_s.starts_with?("..")
          next whole unless File.file?(File.join(@config.source_dir, target.to_s))
          rebased = target.relative_to(Path.posix(bundle_dir)).to_s
          "url(#{quote}#{rebased}#{suffix}#{quote})"
        end
      end

      # Separator placed between concatenated bundle sources.
      #
      # JavaScript needs an explicit statement terminator: a newline alone does
      # NOT trigger automatic semicolon insertion when the next file opens with
      # `(`, `[`, a backtick, `+`, `-` or `/`. Two individually valid files —
      # `const a = 1` and `(function(){…})()` — then concatenate into
      # `1(function(){…})()`, a runtime `TypeError` with nothing in the build
      # log. The `;` sits on its own line so a source ending in an unterminated
      # `// line comment` cannot swallow it (the minifier drops the blank
      # framing lines, keeping the `;`). CSS keeps the bare newline: a stray
      # top-level `;` is a parse error browsers only recover from.
      private def bundle_separator(name : String) : String
        case File.extname(name).downcase
        when ".js", ".mjs" then "\n;\n"
        else                    "\n"
        end
      end

      private def minify(content : String, filename : String) : String
        ext = File.extname(filename).downcase
        case ext
        when ".css"
          Utils::CssMinifier.minify(content)
        when ".js"
          Utils::JsMinifier.minify(content)
        else
          content
        end
      end

      private def fingerprint(name : String, content : String) : String
        hash = Digest::SHA256.hexdigest(content)[0, 8]
        ext = File.extname(name)
        base = File.basename(name, ext)
        dir = File.dirname(name)
        fingerprinted = "#{base}.#{hash}#{ext}"
        if dir == "."
          fingerprinted
        else
          File.join(dir, fingerprinted)
        end
      end
    end
  end
end
