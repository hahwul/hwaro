# Export command for exporting content to other platforms
#
# This command exports hwaro content to other static site generator formats.
# Usage:
#   hwaro tool export <target-type> [options]

require "option_parser"
require "../../metadata"
require "../../../config/options/export_options"
require "../../../services/exporters/base"
require "../../../services/exporters/hugo_exporter"
require "../../../services/exporters/jekyll_exporter"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ExportCommand
          NAME               = "export"
          DESCRIPTION        = "Export content to other platforms"
          POSITIONAL_ARGS    = ["target-type"]
          POSITIONAL_CHOICES = ["hugo", "jekyll"]

          FLAGS = [
            FlagInfo.new(short: "-o", long: "--output", description: "Output directory (default: export)", takes_value: true, value_hint: "DIR"),
            CONTENT_DIR_FLAG,
            DRAFTS_FLAG,
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

            if options.target_type.empty?
              Logger.error "Missing target type. Usage: hwaro tool export <target-type> [options]"
              Logger.info "Supported: #{supported}"
              exit(1)
            end

            exporter = case options.target_type
                       when "hugo"
                         Services::Exporters::HugoExporter.new
                       when "jekyll"
                         Services::Exporters::JekyllExporter.new
                       else
                         Logger.error "Unknown target type: #{options.target_type}"
                         Logger.info "Supported: #{supported}"
                         exit(1)
                       end

            Logger.info "Exporting to #{options.target_type}: #{options.output_dir}"
            Logger.info "Content directory: #{options.content_dir}"

            result = exporter.run(options)

            if result.success
              Logger.success "Export complete: #{result.exported_count} exported, #{result.skipped_count} skipped, #{result.error_count} errors"
            else
              Logger.error "Export failed: #{result.message}"
              exit(1)
            end
          end

          private def parse_options(args : Array(String)) : Config::Options::ExportOptions
            output_dir = "export"
            content_dir = "content"
            drafts = false
            verbose = false
            positional = [] of String

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool export <target-type> [options]"
              parser.on("-o DIR", "--output DIR", "Output directory (default: export)") { |dir| output_dir = dir }
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, DRAFTS_FLAG) { |_| drafts = true }
              CLI.register_flag(parser, VERBOSE_FLAG) { |_| verbose = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |remaining|
                positional = remaining
              end
            end

            target_type = positional.shift? || ""

            Config::Options::ExportOptions.new(
              target_type: target_type,
              output_dir: output_dir,
              content_dir: content_dir,
              drafts: drafts,
              verbose: verbose,
            )
          end
        end
      end
    end
  end
end
