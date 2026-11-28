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
require "../utils/path_utils"
require "../models/config"

module Hwaro
  module Assets
    class SassCompiler
      SOURCE_DIR = "static"

      # The `.css` files the last `compile_all` wrote (output-dir paths).
      # Callers claim them (`Builder#claim_generated_output`) so a `--cache`
      # build prunes the stylesheet of a deleted or renamed `.scss` entry.
      getter written_paths : Array(String) = [] of String

      def initialize(@config : Models::SassConfig, @static_config : Models::StaticConfig)
      end

      # Whether a .scss path under static/ is an entry rather than a partial
      # or an excluded file. Callers apply the project source check separately.
      def self.entry_source?(path : String, static_config : Models::StaticConfig) : Bool
        !File.basename(path).starts_with?("_") && Utils::PathUtils.file?(path) &&
          !static_config.excluded?(Path[path].relative_to(SOURCE_DIR).to_s)
      end

      # Compiles every entry file and returns the compiled count. Partials
      # (`_*.scss`) and statically-excluded paths are skipped; the raw
      # sources themselves are excluded from the static copy separately
      # (Models::Config#sass_source?).
      def compile_all(output_dir : String) : Int32
        @written_paths = [] of String
        return 0 unless @config.enabled
        return 0 unless Dir.exists?(SOURCE_DIR)

        entries = [] of {String, String}
        glob_match = File::MatchOptions.glob_default | File::MatchOptions::DotFiles
        project_root = Dir.current
        Dir.glob(File.join(SOURCE_DIR, "**", "*.scss"), match: glob_match) do |src_path|
          next unless SassCompiler.entry_source?(src_path, @static_config)

          relative = Path[src_path].relative_to(SOURCE_DIR).to_s

          # Entry paths used to skip the outside-symlink guard imports already
          # have: a `static/css/style.scss` → /etc/passwd symlink would publish
          # the target's contents as CSS. Match static-copy / importer policy.
          unless Utils::PathUtils.publishable_project_source?(src_path, project_root)
            Logger.warn "  Sass: skipping entry outside project root or at a protected target (symlink?): #{relative}"
            next
          end

          css_path = relative.chomp(".scss") + ".css"
          if File.exists?(File.join(SOURCE_DIR, css_path))
            Logger.warn "  Sass: #{relative} compiles to #{css_path}, which also exists as a static source — remove one of the two."
          end

          css = SassCompiler.compile_source(File.read(src_path), src_path)
          css = Utils::CssMinifier.minify(css) if @config.minify

          entries << {css_path, css}
        end

        # A failed entry must leave the previous stylesheets in place during
        # serve. Finish compilation before replacing any output files.
        entries.each do |css_path, css|
          dest_path = File.join(output_dir, css_path)
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
          Hwaro::Utils::FileSafe.atomic_write(dest_path, css)
          @written_paths << dest_path
          Logger.debug "  Sass: #{css_path.chomp(".css")}.scss → #{css_path} (#{css.bytesize} bytes)"
        end
        @written_paths.size
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
