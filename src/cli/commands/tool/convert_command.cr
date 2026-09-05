# Convert command for converting frontmatter formats
#
# This command converts frontmatter in content files between YAML, TOML, and JSON formats.
# Usage:
#   hwaro tool convert to-yaml  - Convert all frontmatter to YAML format
#   hwaro tool convert to-toml  - Convert all frontmatter to TOML format
#   hwaro tool convert to-json  - Convert all frontmatter to JSON format

require "json"
require "option_parser"
require "../../metadata"
require "../../../services/frontmatter_converter"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ConvertCommand
          # Single source of truth for command metadata
          NAME               = "convert"
          DESCRIPTION        = "Convert frontmatter format (TOML / YAML / JSON)"
          POSITIONAL_ARGS    = ["format"]
          POSITIONAL_CHOICES = ["to-yaml", "to-toml", "to-json"]

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            CONTENT_DIR_FLAG,
            DRY_RUN_FLAG,
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
            content_dir = "content"
            format : String? = nil
            json_output = false
            dry_run = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool convert <to-yaml|to-toml|to-json> [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, DRY_RUN_FLAG) { |_| dry_run = true }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |unknown|
                format = unknown.first? if unknown.present?
              end
            end

            Runner.enable_json_mode! if json_output

            unless format
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <format> argument",
                hint: "Usage: hwaro tool convert <to-yaml|to-toml|to-json> — supported: #{POSITIONAL_CHOICES.join(", ")}.",
              )
            end

            converter = Services::FrontmatterConverter.new(content_dir, dry_run: dry_run)

            fmt = format.as(String).downcase
            if POSITIONAL_CHOICES.includes?(fmt)
              Logger.heading(NAME, fmt)
              # Conversion round-trips parsed values, so front-matter comments
              # (and exact formatting) have no representation to survive in.
              # Say so up front instead of silently discarding them —
              # `doctor --fix` edits config.toml as raw text for this exact
              # reason, but a format conversion can't.
              Logger.item("comments in front matter are not preserved by conversion", glyph: :info) unless json_output
            end

            result = case fmt
                     when "to-yaml" then converter.convert_to_yaml
                     when "to-toml" then converter.convert_to_toml
                     when "to-json" then converter.convert_to_json
                     else
                       raise Hwaro::HwaroError.new(
                         code: Hwaro::Errors::HWARO_E_USAGE,
                         message: "unknown format: #{format}",
                         hint: "Supported: #{POSITIONAL_CHOICES.join(", ")}.",
                       )
                     end
            puts result.to_json if json_output
            fail_conversion(result, json_output) unless result.success
          end

          # Surface the converter's own message instead of exiting 1 in
          # silence — a missing content directory used to produce no output
          # at all in human mode, with the reason only ever reachable via
          # `--json`.
          #
          # BOTH modes exit `HWARO_E_IO`. The `--json` payload was already
          # printed by the caller, so this path only needs the status code —
          # but it has to be the SAME code, or a machine consumer branching on
          # exit status gets a different (and less classified) answer for the
          # identical failure purely because it asked for JSON. The payload
          # shape is untouched; only the process exit code changes.
          private def fail_conversion(result : Services::ConversionResult, json_output : Bool) : NoReturn
            exit(Hwaro::Errors::EXIT_IO) if json_output

            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_IO,
              message: result.message,
              hint: "Pass -c DIR if your content lives outside 'content'; per-file errors are listed above.",
            )
          end
        end
      end
    end
  end
end
