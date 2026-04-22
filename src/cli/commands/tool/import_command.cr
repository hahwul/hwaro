require "option_parser"
require "../../metadata"
require "../../../config/options/import_options"
require "../../../services/importers/base"
require "../../../services/importers/html_to_markdown"
require "../../../services/importers/wordpress_importer"
require "../../../services/importers/jekyll_importer"
require "../../../services/importers/hugo_importer"
require "../../../services/importers/notion_importer"
require "../../../services/importers/obsidian_importer"
require "../../../services/importers/hexo_importer"
require "../../../services/importers/astro_importer"
require "../../../services/importers/eleventy_importer"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ImportCommand
          NAME               = "import"
          DESCRIPTION        = "Import content from various platforms"
          POSITIONAL_ARGS    = ["source-type", "path"]
          POSITIONAL_CHOICES = ["wordpress", "jekyll", "hugo", "notion", "obsidian", "hexo", "astro", "eleventy"]

          FORCE_FLAG = FlagInfo.new(short: nil, long: "--force", description: "Overwrite existing files instead of skipping")

          FLAGS = [
            FlagInfo.new(short: "-o", long: "--output", description: "Output content directory (default: content)", takes_value: true, value_hint: "DIR"),
            DRAFTS_FLAG,
            FORCE_FLAG,
            VERBOSE_FLAG,
            HELP_FLAG,
          ]

          def self.metadata : CommandInfo
            CommandInfo.new(
              name: NAME,
              description: DESCRIPTION,
              flags: FLAGS,
              positional_args: POSITIONAL_ARGS,
              positional_choices: POSITIONAL_CHOICES
            )
          end

          def run(args : Array(String))
            options = parse_options(args)

            supported = POSITIONAL_CHOICES.join(", ")

            if options.source_type.empty?
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <source-type> argument",
                hint: "Usage: hwaro tool import <source-type> <path> — supported: #{supported}.",
              )
            end

            unless POSITIONAL_CHOICES.includes?(options.source_type)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "unknown source type: #{options.source_type}",
                hint: "Supported: #{supported}.",
              )
            end

            if options.path.empty?
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <path> argument",
                hint: "Usage: hwaro tool import #{options.source_type} <path> — run 'hwaro tool import --help' for details.",
              )
            end

            importer = case options.source_type
                       when "wordpress"
                         Services::Importers::WordPressImporter.new
                       when "jekyll"
                         Services::Importers::JekyllImporter.new
                       when "hugo"
                         Services::Importers::HugoImporter.new
                       when "notion"
                         Services::Importers::NotionImporter.new
                       when "obsidian"
                         Services::Importers::ObsidianImporter.new
                       when "hexo"
                         Services::Importers::HexoImporter.new
                       when "astro"
                         Services::Importers::AstroImporter.new
                       when "eleventy"
                         Services::Importers::EleventyImporter.new
                       else
                         # Unreachable: POSITIONAL_CHOICES check above covers this.
                         raise Hwaro::HwaroError.new(
                           code: Hwaro::Errors::HWARO_E_INTERNAL,
                           message: "unhandled source type: #{options.source_type}",
                         )
                       end

            Logger.info "Importing from #{options.source_type}: #{options.path}"
            Logger.info "Output directory: #{options.output_dir}"

            result = importer.run(options)

            unless result.success
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: result.message,
                hint: importer_hint(options.source_type),
              )
            end

            total = result.imported_count + result.skipped_count + result.error_count
            if total == 0
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "no importable content found at: #{options.path}",
                hint: importer_hint(options.source_type),
              )
            end

            Logger.success "Import complete: #{result.imported_count} imported, #{result.skipped_count} skipped, #{result.error_count} errors"

            if result.skipped_count > 0 && !options.force
              Logger.warn "#{result.skipped_count} file(s) skipped because the destination already exists. Re-run with --force to overwrite."
            end
          end

          # Source-type-specific hint describing where/what the importer
          # expects to find. Used for both "empty source" and "importer
          # failed" paths so the user gets a concrete next step.
          private def importer_hint(source_type : String) : String
            case source_type
            when "wordpress"
              "Expected a WXR XML file (WordPress Tools → Export → All content)."
            when "jekyll"
              "Expected a Jekyll site root containing _posts/ (and optionally _drafts/)."
            when "hugo"
              "Expected a Hugo site root containing content/."
            when "notion"
              "Expected an unzipped Notion Markdown export directory."
            when "obsidian"
              "Expected an Obsidian vault directory containing .md files."
            when "hexo"
              "Expected a Hexo site root containing source/_posts/ (and optionally source/_drafts/)."
            when "astro"
              "Expected an Astro project root containing src/content/."
            when "eleventy"
              "Expected an Eleventy project root containing .md files."
            else
              "Run 'hwaro tool import --help' for supported source types."
            end
          end

          private def parse_options(args : Array(String)) : Config::Options::ImportOptions
            output_dir = "content"
            drafts = false
            verbose = false
            force = false
            positional = [] of String

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool import <source-type> <path> [options]"
              parser.on("-o DIR", "--output DIR", "Output content directory (default: content)") { |dir| output_dir = dir }
              CLI.register_flag(parser, DRAFTS_FLAG) { |_| drafts = true }
              CLI.register_flag(parser, FORCE_FLAG) { |_| force = true }
              CLI.register_flag(parser, VERBOSE_FLAG) { |_| verbose = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |remaining|
                positional = remaining
              end
            end

            source_type = positional.shift? || ""
            path = positional.shift? || ""

            Config::Options::ImportOptions.new(
              source_type: source_type,
              path: path,
              output_dir: output_dir,
              drafts: drafts,
              verbose: verbose,
              force: force,
            )
          end
        end
      end
    end
  end
end
