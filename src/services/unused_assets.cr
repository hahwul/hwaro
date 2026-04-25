# Unused Assets Service
#
# Scans static files and co-located content assets, then checks
# whether each asset is referenced by any content or template file.
# Reports unreferenced files that may be candidates for removal.

require "json"
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

      @content_dir : String
      @static_dir : String
      @templates_dir : String

      def initialize(
        @content_dir : String = "content",
        @static_dir : String = "static",
        @templates_dir : String = "templates",
      )
      end

      def run : UnusedAssetsResult
        assets = collect_assets
        return UnusedAssetsResult.new if assets.empty?

        referenced = build_referenced_basenames

        unused = [] of String
        assets.each do |asset_path|
          basename = File.basename(asset_path)
          unless referenced.includes?(basename)
            unused << asset_path
          end
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
            Logger.info "  Deleted: #{file}"
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

      # Extract referenced asset filenames from content and template files.
      # Uses regex to find filenames with known asset extensions, avoiding
      # substring false positives from plain string matching.
      private def build_referenced_basenames : Set(String)
        refs = Set(String).new
        ext_pattern = /[\w\-\.]+\.(?:png|jpe?g|gif|svg|webp|avif|ico|bmp|tiff?|css|js|woff2?|ttf|eot|otf|mp[34]|webm|ogg|wav|pdf|zip)\b/i

        scan_files = [] of String

        if Dir.exists?(@content_dir)
          Dir.glob(File.join(@content_dir, "**", "*.md")) { |f| scan_files << f }
          Dir.glob(File.join(@content_dir, "**", "*.markdown")) { |f| scan_files << f }
        end

        if Dir.exists?(@templates_dir)
          Dir.glob(File.join(@templates_dir, "**", "*.html")) { |f| scan_files << f }
          Dir.glob(File.join(@templates_dir, "**", "*.css")) { |f| scan_files << f }
          Dir.glob(File.join(@templates_dir, "**", "*.js")) { |f| scan_files << f }
        end

        scan_files.each do |file|
          text = File.read(file) rescue next
          text.scan(ext_pattern) do |match|
            refs << match[0]
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
        return unless File.exists?("config.toml")
        config = Models::Config.load
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
      rescue
        # Treat config-load failures as "no extra references" so the
        # tool stays best-effort rather than crashing on a partial
        # site.
      end
    end
  end
end
