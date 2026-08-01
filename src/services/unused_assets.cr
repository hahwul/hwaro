# Unused Assets Service
#
# Scans static files and co-located content assets, then checks
# whether each asset is referenced by any content or template file.
# Reports unreferenced files that may be candidates for removal.

require "json"
require "uri"
require "../models/config"
require "../utils/logger"

module Hwaro
  module Services
    struct UnusedAssetsResult
      include JSON::Serializable

      property unused_files : Array(String)
      property total_assets : Int32
      property referenced_count : Int32
      property unused_count : Int32

      def initialize(
        @unused_files : Array(String) = [] of String,
        @total_assets : Int32 = 0,
        @referenced_count : Int32 = 0,
        @unused_count : Int32 = 0,
      )
      end
    end

    class UnusedAssets
      ASSET_EXTENSIONS = Set{
        ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".avif", ".ico",
        ".bmp", ".tiff", ".tif",
        ".css", ".js",
        ".woff", ".woff2", ".ttf", ".eot", ".otf",
        ".mp4", ".webm", ".ogg", ".mp3", ".wav",
        ".pdf", ".zip",
      }

      CONTENT_EXTENSIONS = Set{".md", ".markdown"}

      # Template files that may reference an asset. `.html` alone was not
      # enough: `Builder::TEMPLATE_EXTENSION_REGEX` also accepts `.j2`,
      # `.jinja`, `.jinja2` and `.ecr`, and feed/manifest templates are
      # authored as `rss.xml.jinja` / `site.webmanifest`. Anything missing
      # here is invisible to the reference scan, so its assets are reported
      # unused — and `--delete` removes files the build still needs.
      TEMPLATE_SCAN_EXTENSIONS = %w[html j2 jinja jinja2 ecr css js xml json webmanifest svg txt]

      # Static sources that reference other static files: Sass (`@font-face`
      # / `url()` in a `.scss` that compiles to `.css`), PWA manifests
      # (`site.webmanifest` icons), and `<image href>` inside an SVG.
      STATIC_SCAN_EXTENSIONS = %w[css scss sass js json webmanifest xml svg txt]

      @content_dir : String
      @static_dir : String
      @templates_dir : String
      @project_root : String

      def initialize(
        @content_dir : String = "content",
        @static_dir : String = "static",
        @templates_dir : String = "templates",
      )
        if File.exists?("config.toml")
          @project_root = "."
        else
          @project_root = find_project_root(@content_dir)
        end

        if @templates_dir == "templates"
          @templates_dir = File.join(@project_root, "templates")
        end
      end

      private def find_project_root(content_dir : String) : String
        if File.basename(content_dir) == "content"
          parent = File.dirname(content_dir)
          return parent.empty? || parent == "." ? "." : parent
        end

        if Dir.exists?(File.join(content_dir, "content")) || Dir.exists?(File.join(content_dir, "../content"))
          return content_dir
        end

        content_dir
      end

      def run : UnusedAssetsResult
        assets = collect_assets
        return UnusedAssetsResult.new if assets.empty?

        scanned_text = collect_scan_text
        referenced = build_referenced_basenames(scanned_text)

        unused = [] of String
        assets.each do |asset_path|
          basename = File.basename(asset_path)
          next if referenced.includes?(basename)
          # Safety net against the `delete_unused` data-loss path: the
          # reference regex only captures filenames built from [\w\-.], so a
          # referenced asset whose name contains a space or parenthesis (e.g.
          # `team photo.png`, `logo(1).png`) is NOT in `referenced` and would
          # be flagged — and deleted — despite being in active use. Before
          # declaring an asset unused, confirm its basename does not appear in
          # the scanned source delimited by non-[\w\-.] boundaries — the same
          # token model the reference regex uses. A boundary-anchored match (not
          # a raw substring) still rescues the space/paren names while keeping a
          # genuinely-unused `header.png` flagged when only `page-header.png` is
          # referenced (their shared suffix is preceded by `-`, inside the token).
          next if scanned_text.matches?(/(?<![\w\-.])#{Regex.escape(basename)}(?![\w\-.])/)
          next if scanned_text.matches?(/(?<![\w\-.])#{Regex.escape(URI.encode_path(basename))}(?![\w\-.])/)
          unused << asset_path
        end

        UnusedAssetsResult.new(
          unused_files: unused.sort,
          total_assets: assets.size,
          referenced_count: assets.size - unused.size,
          unused_count: unused.size,
        )
      end

      def delete_unused(files : Array(String))
        files.each do |file|
          if File.exists?(file)
            File.delete(file)
            Logger.action(:remove, file, Logger::Role::Warn)
          end
        end
      end

      private def collect_assets : Array(String)
        assets = [] of String

        # Static directory assets
        if Dir.exists?(@static_dir)
          Dir.glob(File.join(@static_dir, "**", "*")) do |path|
            next if File.directory?(path)
            ext = File.extname(path).downcase
            assets << path if ASSET_EXTENSIONS.includes?(ext)
          end
        end

        # Co-located assets in content directory
        if Dir.exists?(@content_dir)
          Dir.glob(File.join(@content_dir, "**", "*")) do |path|
            next if File.directory?(path)
            ext = File.extname(path).downcase
            next if CONTENT_EXTENSIONS.includes?(ext)
            assets << path if ASSET_EXTENSIONS.includes?(ext)
          end
        end

        assets
      end

      # Concatenate every content/template file we scan for references into a
      # single blob, so both the regex pass and the literal-substring safety
      # net in `run` work off the same source text.
      private def collect_scan_text : String
        scan_files = [] of String

        if Dir.exists?(@content_dir)
          Dir.glob(File.join(@content_dir, "**", "*.md")) { |f| scan_files << f }
          Dir.glob(File.join(@content_dir, "**", "*.markdown")) { |f| scan_files << f }
        end

        if Dir.exists?(@templates_dir)
          Dir.glob(File.join(@templates_dir, "**", "*.{#{TEMPLATE_SCAN_EXTENSIONS.join(",")}}")) { |f| scan_files << f }
        end

        # Stylesheets/scripts shipped under static/ commonly reference other
        # assets via url()/@font-face/import (e.g. the scaffold's
        # static/css/style.css pulls in static/fonts/*.woff2). Without scanning
        # them, those fonts are misreported as unused — and `--delete` would
        # remove in-use files (data loss).
        if Dir.exists?(@static_dir)
          Dir.glob(File.join(@static_dir, "**", "*.{#{STATIC_SCAN_EXTENSIONS.join(",")}}")) { |f| scan_files << f }
        end

        String.build do |sb|
          scan_files.each do |file|
            text = readable_scan_source(file) || next
            sb << text << '\n'
          end

          config_path = File.join(@project_root, "config.toml")
          if File.exists?(config_path)
            begin
              sb << File.read(config_path) << '\n'
            rescue IO::Error
            end
          end
        end
      end

      # Read one reference source, or nil when it cannot be scanned.
      #
      # A file containing invalid UTF-8 makes every later PCRE2 operation on
      # the concatenated corpus raise `ArgumentError`, which aborted the whole
      # command with a bare "Error: Regex match error" and zero results. That
      # got materially more likely once the scan widened to `.json`/`.xml`/
      # `.svg`/`.txt`, which are often machine-generated. Skip the file with a
      # warning instead — the same degradation `check-links` performs.
      private def readable_scan_source(file : String) : String?
        text = File.read(file)
        # Force the decode failure here, where it can be attributed to a file,
        # rather than later inside a regex over the whole corpus.
        return text if text.valid_encoding?
        Logger.warn "Skipping #{file}: not valid UTF-8"
        nil
      rescue ex : IO::Error | ArgumentError
        Logger.warn "Skipping #{file}: #{ex.message}"
        nil
      end

      # Extract referenced asset filenames from content and template files.
      # Uses regex to find filenames with known asset extensions, avoiding
      # substring false positives from plain string matching.
      private def build_referenced_basenames(scanned_text : String) : Set(String)
        refs = Set(String).new
        ext_pattern = /[\w\-\.%]+\.(?:png|jpe?g|gif|svg|webp|avif|ico|bmp|tiff?|css|js|woff2?|ttf|eot|otf|mp[34]|webm|ogg|wav|pdf|zip)\b/i

        scanned_text.scan(ext_pattern) do |match|
          token = match[0]
          refs << token
          if token.includes?('%')
            refs << URI.decode(token)
          end
        end

        # Files declared in `config.toml` (`[[assets.bundles]] files`,
        # `[auto_includes] dirs`, …) are consumed by the build pipeline
        # itself, not referenced from content/templates — without this
        # the scan reported them as "Unused" even though the build
        # actively reads them. See #488.
        add_config_references(refs)

        refs
      end

      private def add_config_references(refs : Set(String)) : Nil
        config_path = File.join(@project_root, "config.toml")
        return unless File.exists?(config_path)
        config = Models::Config.load(config_path)
        config.assets.bundles.each do |bundle|
          bundle.files.each { |path| refs << File.basename(path) }
          # The compiled bundle name (e.g. `main.css`) is referenced
          # from templates via `{{ asset(name=...) }}`; that already
          # gets picked up by the regex scan above, so no extra work
          # needed here.
        end
        config.auto_includes.dirs.each do |rel_dir|
          dir = File.join(@static_dir, rel_dir)
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "**", "*")) do |path|
            next if File.directory?(path)
            refs << File.basename(path)
          end
        end
      rescue Exception
        # Treat config-load failures as "no extra references" so the
        # tool stays best-effort rather than crashing on a partial
        # site.
      end
    end
  end
end
