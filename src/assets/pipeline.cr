# Built-in asset pipeline for CSS/JS bundling, minification, and fingerprinting
#
# Processes static CSS/JS files into optimized bundles with content-hash
# based filenames for cache busting.

require "digest/sha256"
require "file_utils"
require "../utils/css_minifier"
require "../utils/js_minifier"
require "../utils/logger"
require "../models/config"
require "./sass_compiler"

module Hwaro
  module Assets
    class Pipeline
      # Manifest mapping original names to fingerprinted output paths
      # e.g. "main.css" => "/assets/main.a1b2c3d4.css"
      getter manifest : Hash(String, String)

      # `sass_enabled` mirrors `[sass].enabled`: `.scss` bundle entries
      # compile through the built-in compiler only when the feature is on;
      # otherwise they concatenate verbatim (pre-Sass behavior, and the
      # escape hatch for sources outside the supported subset).
      def initialize(@config : Models::AssetsConfig, @base_url : String, @sass_enabled : Bool = false)
        @manifest = {} of String => String
      end

      def process(output_dir : String)
        return unless @config.enabled

        assets_output = File.join(output_dir, @config.output_dir)
        Hwaro::Utils::FileSafe.mkdir_p(assets_output)

        @config.bundles.each do |bundle|
          process_bundle(bundle, assets_output)
        end
      end

      private def process_bundle(bundle : Models::AssetBundleConfig, assets_output : String)
        # Read and concatenate source files
        contents = String.build do |io|
          bundle.files.each_with_index do |file, i|
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
            io << "\n" if i > 0
            content = File.read(source)
            # `.scss` bundle entries compile before concatenation when the
            # built-in Sass feature is on; verbatim otherwise.
            if @sass_enabled && file.ends_with?(".scss")
              content = SassCompiler.compile_source(content, source)
            end
            io << content
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
        Hwaro::Utils::FileSafe.mkdir_p(File.dirname(output_path))
        File.write(output_path, contents)

        # Record in manifest
        manifest_path = "/" + File.join(@config.output_dir, output_name)
        @manifest[bundle.name] = manifest_path

        Logger.debug "  Asset: #{bundle.name} → #{manifest_path} (#{contents.bytesize} bytes)"
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
