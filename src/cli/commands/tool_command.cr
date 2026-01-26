# Tool command - Parent command for various utility tools
#
# This command serves as a container for utility subcommands.
# Usage:
#   hwaro tool <subcommand> [options]
#
# Available subcommands:
#   convert  - Convert frontmatter between YAML and TOML formats

require "option_parser"
require "./tool/convert_command"
require "./tool/list_command"
require "./tool/check_command"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class ToolCommand
        SUBCOMMANDS = {
          "convert" => "Convert frontmatter format (YAML <-> TOML)",
          "list"    => "List content files (all, drafts, published)",
          "check"   => "Check for dead links in content files",
        }

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
          SUBCOMMANDS.each do |name, description|
            Logger.info "  #{name.ljust(10)} #{description}"
          end
          Logger.info ""
          Logger.info "Run 'hwaro tool <subcommand> --help' for more information on a subcommand."
        end
      end
    end
  end
end
