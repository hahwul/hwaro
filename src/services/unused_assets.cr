# Unused Assets Service
#
# Scans static files and co-located content assets, then checks
# whether each asset is referenced by any content or template file.
# Reports unreferenced files that may be candidates for removal.

require "json"
require "uri"
require "./content_lister"
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
      #
      # `html`/`htm` belong here too. Hand-written pages under `static/` are
      # copied into the output verbatim by the build, so an `<img src=...>`
      # inside one is a fully static, literal reference — yet without the
      # extension the scan never read the file and reported its images as
      # unused, which `--delete` then removed (real data loss).
      STATIC_SCAN_EXTENSIONS = %w[css scss sass js json webmanifest xml svg txt html htm]

      # Data and translation sources that can name an asset (`logo: /img/a.png`
      # in `data/site.yml`, an icon path in `i18n/en.toml`). `data/` is loaded
      # by `Phases::Initialize#load_data_files` with exactly this extension
      # set, and i18n locale files are TOML; templates render whatever those
      # hold, so a path that only ever appears there is still in use.
      DATA_SCAN_EXTENSIONS = %w[yml yaml json toml]

      @content_dir : String
      @static_dir : String
      @templates_dir : String
      @project_root : String

      def initialize(
        @content_dir : String = "content",
        @static_dir : String = "static",
        @templates_dir : String = "templates",
        templates_dir_explicit : Bool = false,
        static_dir_explicit : Bool = false,
      )
        @project_root = resolve_project_root

        # Only the true defaults get re-rooted. An explicitly passed
        # `--templates-dir templates` (or `--static-dir static`) was
        # existence-checked by the command against the CWD; silently
        # re-rooting it would scan a different directory than the one the
        # user named — the `*_explicit` flags keep that path as given.
        if !templates_dir_explicit && @templates_dir == "templates"
          @templates_dir = rooted("templates")
        end
        if !static_dir_explicit && @static_dir == "static"
          @static_dir = rooted("static")
        end
      end

      # One coherent project root for every derived input (static/,
      # templates/, data/, i18n/, config.toml). The root used to be pinned to
      # "." as soon as the CWD held a config.toml — even when --content-dir
      # pointed into a DIFFERENT project — so the scan mixed two trees:
      # assets came from one project, references from another, and
      # `--delete --force` removed files the other project still uses.
      private def resolve_project_root : String
        candidate = find_project_root(@content_dir)
        # A config.toml next to the content tree is authoritative.
        return candidate if File.exists?(File.join(candidate, "config.toml"))
        # Fall back to the CWD only when the content tree actually lives
        # inside it; a foreign tree without its own config.toml still roots
        # at itself rather than borrowing the CWD's project files.
        return "." if File.exists?("config.toml") && inside_cwd?(@content_dir)
        candidate
      end

      private def inside_cwd?(path : String) : Bool
        expanded = File.expand_path(path)
        cwd = Dir.current
        expanded == cwd || expanded.starts_with?(cwd + File::SEPARATOR)
      end

      # Join `name` under the project root, keeping the historical relative
      # form ("static", not "./static") for the in-project case so reported
      # paths stay byte-identical.
      private def rooted(name : String) : String
        @project_root == "." ? name : File.join(@project_root, name)
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
          # A non-UTF-8 basename (possible on Linux filesystems; APFS refuses
          # them) cannot be matched against the UTF-8 scan corpus — building
          # a PCRE2 Regex from it raises ArgumentError, which used to abort
          # the whole command. Warn and leave the file alone rather than flag
          # it unused and let `--delete` remove something we could not check.
          unless basename.valid_encoding?
            Logger.warn "Skipping #{asset_path.inspect}: file name is not valid UTF-8"
            next
          end
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
          next if UnusedAssets.boundary_referenced?(scanned_text, basename)
          unused << asset_path
        end

        UnusedAssetsResult.new(
          unused_files: unused.sort,
          total_assets: assets.size,
          referenced_count: assets.size - unused.size,
          unused_count: unused.size,
        )
      end

      # Boundary-anchored literal check backing the safety net above. A class
      # method so it stays testable on filesystems (APFS) that refuse to
      # create non-UTF-8 filenames at all. A basename that is not valid UTF-8
      # cannot become a PCRE2 pattern — `Regex.new` raises `ArgumentError` —
      # so it is reported as not-referenced here without raising; `run` skips
      # (and warns about) such assets before this check is reached.
      def self.boundary_referenced?(scanned_text : String, basename : String) : Bool
        return false unless basename.valid_encoding?
        return true if scanned_text.matches?(/(?<![\w\-.])#{Regex.escape(basename)}(?![\w\-.])/)
        scanned_text.matches?(/(?<![\w\-.])#{Regex.escape(URI.encode_path(basename))}(?![\w\-.])/)
      end

      def delete_unused(files : Array(String))
        files.each do |file|
          if File.exists?(file)
            File.delete(file)
            Logger.action(:remove, file, Logger::Role::Warn)
          end
        end
      end

      # Walk `static/` and `content/` for candidate asset files.
      #
      # The extension test now runs BEFORE the filesystem test, and the old
      # `File.directory?` guard is gone: `File.directory?` resolves the path,
      # and on a symlink cycle (`ln -s loop.png static/img/loop.png`) that
      # raises `File::Error` (ELOOP) — nothing here caught it, so the whole
      # command died with a raw "Unable to get file info" on a tree `hwaro
      # build` walks fine. `ContentWalk.readable_file?` skips directories the
      # same way while surviving links it cannot follow, and testing the
      # extension first keeps that check (and its warning) off the thousands of
      # non-asset entries a content tree contains.
      private def collect_assets : Array(String)
        assets = [] of String

        # Static directory assets
        if Dir.exists?(@static_dir)
          Dir.glob(File.join(@static_dir, "**", "*")) do |path|
            ext = File.extname(path).downcase
            next unless ASSET_EXTENSIONS.includes?(ext)
            assets << path if ContentWalk.readable_file?(path)
          end
        end

        # Co-located assets in content directory
        if Dir.exists?(@content_dir)
          Dir.glob(File.join(@content_dir, "**", "*")) do |path|
            ext = File.extname(path).downcase
            next if CONTENT_EXTENSIONS.includes?(ext)
            next unless ASSET_EXTENSIONS.includes?(ext)
            assets << path if ContentWalk.readable_file?(path)
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

        # `data/` and `i18n/` are build inputs too — templates read them as
        # `site.data.*` / translation strings, so an asset path that lives only
        # in a data or locale file is genuinely referenced. Neither directory
        # was scanned at all, so those assets were reported unused and
        # `--delete` removed them.
        {"data", "i18n"}.each do |rel_dir|
          dir = File.join(@project_root, rel_dir)
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "**", "*.{#{DATA_SCAN_EXTENSIONS.join(",")}}")) { |f| scan_files << f }
        end

        String.build do |sb|
          scan_files.each do |file|
            text = readable_scan_source(file) || next
            sb << text << '\n'
          end

          # config.toml goes through the same UTF-8 gate as every other scan
          # source: concatenated raw, one invalid byte in it aborted the whole
          # command with a PCRE2 ArgumentError.
          config_path = File.join(@project_root, "config.toml")
          if File.exists?(config_path)
            if text = readable_scan_source(config_path)
              sb << text << '\n'
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
            # `File.directory?` raises on a symlink cycle, and the blanket
            # rescue below would have swallowed it — dropping EVERY
            # config-declared reference, so `--delete` removed bundle and
            # auto-include files the build still reads. Resolve the entry the
            # way the asset walk does instead.
            next unless ContentWalk.readable_file?(path)
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
