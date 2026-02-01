# Tool command - Parent command for various utility tools
#
# This command serves as a container for utility subcommands.
# Usage:
#   hwaro tool <subcommand> [options]
#
# Available subcommands:
#   convert  - Convert frontmatter between YAML and TOML formats
#   list     - List content files by status
#   check    - Check for dead links

require "option_parser"
require "../metadata"
require "./tool/convert_command"
require "./tool/list_command"
require "./tool/check_command"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class ToolCommand
        # Single source of truth for command metadata
        NAME               = "tool"
        DESCRIPTION        = "Utility tools (convert, etc.)"
        POSITIONAL_ARGS    = [] of String
        POSITIONAL_CHOICES = [] of String

        FLAGS = [
          HELP_FLAG,
        ]

        # Get subcommand metadata from subcommand classes
        def self.subcommands : Array(CommandInfo)
          [
            Tool::ConvertCommand.metadata,
            Tool::ListCommand.metadata,
            Tool::CheckCommand.metadata,
          ]
        end

        def self.metadata : CommandInfo
          CommandInfo.new(
            name: NAME,
            description: DESCRIPTION,
            flags: FLAGS,
            subcommands: subcommands,
            positional_args: POSITIONAL_ARGS,
            positional_choices: POSITIONAL_CHOICES
          )
        end

        def run(args : Array(String))
          if args.empty?
            print_help
            exit(1)
          end

          subcommand = args.shift

          case subcommand
          when "convert"
            Tool::ConvertCommand.new.run(args)
          when "list"
            Tool::ListCommand.new.run(args)
          when "check"
            Tool::CheckCommand.new.run(args)
          when "-h", "--help", "help"
            print_help
          else
            Logger.error "Unknown subcommand: #{subcommand}"
            print_help
            exit(1)
          end
        end

        private def print_help
          Logger.info "Usage: hwaro tool <subcommand> [options]"
          Logger.info ""
          Logger.info "Available subcommands:"
          ToolCommand.subcommands.each do |sub|
            Logger.info "  #{sub.name.ljust(10)} #{sub.description}"
          end
          Logger.info ""
          Logger.info "Run 'hwaro tool <subcommand> --help' for more information on a subcommand."
        end
      end
    end
  end
end
