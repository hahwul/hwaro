# Build orchestrator for the built-in SCSS compiler (peer of Pipeline).
#
# Scans the static tree for non-partial `*.scss` entry files, compiles
# each with Assets::Sass, optionally minifies through the existing CSS
# minifier, and writes sibling `.css` files into the output directory.
# Compiler errors surface as classified HwaroErrors (HWARO_E_CONTENT)
# with a `path:line:col` location.

require "./sass"
require "../utils/css_minifier"
require "../utils/errors"
require "../utils/logger"
require "../models/config"

module Hwaro
  module Assets
    class SassCompiler
      def initialize(@config : Models::SassConfig, @static_config : Models::StaticConfig,
                     @source_dir : String = "static")
      end

      # Compiles every entry file and returns the compiled count. Partials
      # (`_*.scss`) and statically-excluded paths are skipped; the raw
      # sources themselves are excluded from the static copy separately
      # (Models::Config#sass_source?).
      def compile_all(output_dir : String) : Int32
        return 0 unless @config.enabled
        return 0 unless Dir.exists?(@source_dir)

        count = 0
        glob_match = File::MatchOptions.glob_default | File::MatchOptions::DotFiles
        Dir.glob(File.join(@source_dir, "**", "*.scss"), match: glob_match) do |src_path|
          next unless File.file?(src_path)
          next if File.basename(src_path).starts_with?("_")

          relative = Path[src_path].relative_to(@source_dir).to_s
          next if @static_config.excluded?(relative)

          # A hand-written sibling `.css` and this compiled output land on
          # the same path: full builds copy the raw file first and clobber it
          # here, while a serve session re-copies the raw file OVER the
          # compiled one on edit — warn so the mixed state isn't silent.
          raw_sibling = src_path.sub(/\.scss\z/i, ".css")
          if File.exists?(raw_sibling)
            Logger.warn "  Sass: #{relative} compiles to #{relative.sub(/\.scss\z/i, ".css")}, which also exists as a static source — remove one of the two."
          end

          css = SassCompiler.compile_source(File.read(src_path), src_path)
          css = Utils::CssMinifier.minify(css) if @config.minify

          dest_path = File.join(output_dir, relative.sub(/\.scss\z/i, ".css"))
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
          File.write(dest_path, css)
          Logger.debug "  Sass: #{relative} → #{relative.sub(/\.scss\z/i, ".css")} (#{css.bytesize} bytes)"
          count += 1
        end
        count
      end

      # Compiles one SCSS source, converting compiler errors into
      # classified build errors. Also used by the asset pipeline for
      # `.scss` bundle entries.
      def self.compile_source(source : String, path : String) : String
        Sass.compile(source, path: path)
      rescue ex : Sass::SyntaxError
        raise Hwaro::HwaroError.new(
          Hwaro::Errors::HWARO_E_CONTENT,
          "Sass: #{ex.location}: #{ex.message}",
          hint: "Fix the SCSS source at the location above. The supported subset and its limits are documented in features/sass."
        )
      rescue ex : File::Error
        # Import resolution stats/reads real files; anything the OS refuses
        # beyond "missing" (symlink loops → ELOOP, permissions) must still
        # come out classified, not as a bare File::Error the hook manager
        # downgrades to a generic abort.
        raise Hwaro::HwaroError.new(
          Hwaro::Errors::HWARO_E_CONTENT,
          # `ex.message` embeds the absolute path it tried to open; keep the
          # report relative to the project like every other Sass error.
          "Sass: #{path}: filesystem error while resolving imports: " \
          "#{ex.message.try(&.sub(Dir.current + "/", ""))}",
          hint: "Check for broken or looping symlinks and unreadable files under the imported paths."
        )
      end
    end
  end
end
