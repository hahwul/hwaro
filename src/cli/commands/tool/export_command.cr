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
require "../../../utils/errors"
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
            DRY_RUN_FLAG,
            VERBOSE_FLAG,
            JSON_FLAG,
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
            options, json_output = parse_options(args)

            Runner.enable_json_mode! if json_output

            supported = POSITIONAL_CHOICES.join(", ")

            if options.target_type.empty?
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <target-type> argument",
                hint: "Usage: hwaro tool export <target-type> — supported: #{supported}.",
              )
            end

            exporter = case options.target_type
                       when "hugo"
                         Services::Exporters::HugoExporter.new
                       when "jekyll"
                         Services::Exporters::JekyllExporter.new
                       else
                         raise Hwaro::HwaroError.new(
                           code: Hwaro::Errors::HWARO_E_USAGE,
                           message: "unknown target type: #{options.target_type}",
                           hint: "Supported: #{supported}.",
                         )
                       end

            # `-o` was stored verbatim, so `-o .` (or `-o ""`, or `-o content`)
            # made every destination collapse back onto the source file the
            # exporter had just read — rewriting the project's own content/ in
            # place and still exiting 0. Validate before the receipt so the
            # failure is reported instead of a bogus "exported" header.
            Services::Exporters::Base.guard_output_dir!(options.output_dir, options.content_dir)

            receipt = Logger::Receipt.new(NAME, options.target_type)
              .row("source", options.content_dir)
              .row("output", options.output_dir)
            receipt.row("mode", "dry run — nothing will be written") if options.dry_run
            receipt.emit

            exporter.dry_run = options.dry_run
            result = exporter.run(options)

            if json_output
              # The manifest is printed for failed runs too (success=false,
              # error_count set), then the process exits with the same
              # classified IO status the human path raises — mirroring
              # `tool convert`, so a machine consumer branching on exit
              # status gets the identical answer in both modes.
              puts({
                "success"        => result.success,
                "dry_run"        => options.dry_run,
                "exported_count" => result.exported_count,
                "skipped_count"  => result.skipped_count,
                "error_count"    => result.error_count,
                "files"          => exporter.file_actions,
              }.to_json)
              exit(Hwaro::Errors::EXIT_IO) unless result.success
              return
            end

            unless result.success
              # A classified error instead of the old bare `exit(1)`: every
              # sibling tool command reports failures through HwaroError, so
              # the exit code lands in the documented IO class. A run with
              # ANY per-file error fails here — `success` no longer reports
              # a partial export as clean.
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: result.message,
                hint: "Pass -c DIR if your content lives outside 'content'; per-file errors are listed above.",
              )
            end

            summary = "#{result.exported_count} files · #{result.skipped_count} skipped"
            summary += " · #{result.error_count} errors" if result.error_count > 0
            Logger.info "" if Logger.color_enabled?
            Logger.outcome(options.dry_run ? "would export" : "exported", summary, glyph: result.error_count > 0 ? :err : :result)

            overwritten = exporter.file_actions.count { |a| a.action == "overwritten" }
            if overwritten > 0
              Logger.warn "#{overwritten} existing file(s) #{options.dry_run ? "would be" : "were"} overwritten in #{options.output_dir} (re-exports replace previous output)."
            end
          end

          private def parse_options(args : Array(String)) : {Config::Options::ExportOptions, Bool}
            output_dir = "export"
            content_dir = "content"
            drafts = false
            verbose = false
            dry_run = false
            json_output = false
            positional = [] of String

            supported_targets = POSITIONAL_CHOICES.join("|")

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool export <#{supported_targets}> [options]"
              parser.on("-o DIR", "--output DIR", "Output directory (default: export)") { |dir| output_dir = dir }
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, DRAFTS_FLAG) { |_| drafts = true }
              CLI.register_flag(parser, DRY_RUN_FLAG) { |_| dry_run = true }
              CLI.register_flag(parser, VERBOSE_FLAG) { |_| verbose = true }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) do |_|
                Logger.info parser.to_s
                Logger.info ""
                Logger.info "Supported targets: #{POSITIONAL_CHOICES.join(", ")}"
                exit
              end
              parser.unknown_args do |remaining|
                positional = remaining
              end
            end

            target_type = positional.shift? || ""

            options = Config::Options::ExportOptions.new(
              target_type: target_type,
              output_dir: output_dir,
              content_dir: content_dir,
              drafts: drafts,
              verbose: verbose,
              dry_run: dry_run,
            )
            {options, json_output}
          end
        end
      end
    end
  end
end
