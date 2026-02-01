# Convert command for converting frontmatter formats
#
# This command converts frontmatter in content files between YAML and TOML formats.
# Usage:
#   hwaro tool convert toYAML  - Convert all frontmatter to YAML format
#   hwaro tool convert toTOML  - Convert all frontmatter to TOML format

require "option_parser"
require "../../metadata"
require "../../../services/frontmatter_converter"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ConvertCommand
          # Single source of truth for command metadata
          NAME               = "convert"
          DESCRIPTION        = "Convert frontmatter format (YAML <-> TOML)"
          POSITIONAL_ARGS    = ["format"]
          POSITIONAL_CHOICES = ["toYAML", "toTOML"]

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            FlagInfo.new(short: "-c", long: "--content-dir", description: "Content directory (default: content)", takes_value: true, value_hint: "DIR"),
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

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool convert <toYAML|toTOML> [options]"
              parser.on("-c DIR", "--content-dir DIR", "Content directory (default: content)") { |dir| content_dir = dir }
              parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
              parser.unknown_args do |unknown|
                format = unknown.first? if unknown.any?
              end
            end

            unless format
              Logger.error "Missing format argument. Use 'toYAML' or 'toTOML'"
              Logger.info ""
              Logger.info "Usage: hwaro tool convert <toYAML|toTOML> [options]"
              Logger.info ""
              Logger.info "Examples:"
              Logger.info "  hwaro tool convert toYAML"
              Logger.info "  hwaro tool convert toTOML"
              Logger.info "  hwaro tool convert toYAML --content-dir=posts"
              exit(1)
            end

            converter = Services::FrontmatterConverter.new(content_dir)

            case format.not_nil!.downcase
            when "toyaml"
              result = converter.convert_to_yaml
              exit(1) unless result.success
            when "totoml"
              result = converter.convert_to_toml
              exit(1) unless result.success
            else
              Logger.error "Unknown format: #{format}"
              Logger.info "Use 'toYAML' or 'toTOML'"
              exit(1)
            end
          end
        end
      end
    end
  end
end
