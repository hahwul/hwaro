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

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool convert <to-yaml|to-toml|to-json> [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |unknown|
                format = unknown.first? if unknown.present?
              end
            end

            Logger.quiet = true if json_output
            Runner.json_mode = true if json_output

            unless format
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <format> argument",
                hint: "Usage: hwaro tool convert <to-yaml|to-toml|to-json> — supported: #{POSITIONAL_CHOICES.join(", ")}.",
              )
            end

            converter = Services::FrontmatterConverter.new(content_dir)

            case format.as(String).downcase
            when "to-yaml"
              result = converter.convert_to_yaml
              puts result.to_json if json_output
              exit(1) unless result.success
            when "to-toml"
              result = converter.convert_to_toml
              puts result.to_json if json_output
              exit(1) unless result.success
            when "to-json"
              result = converter.convert_to_json
              puts result.to_json if json_output
              exit(1) unless result.success
            else
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "unknown format: #{format}",
                hint: "Supported: #{POSITIONAL_CHOICES.join(", ")}.",
              )
            end
          end
        end
      end
    end
  end
end
