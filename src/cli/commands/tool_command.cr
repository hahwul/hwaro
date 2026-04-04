# Tool command - Parent command for various utility tools
#
# This command serves as a container for utility subcommands.
# Usage:
#   hwaro tool <subcommand> [options]
#
# Available subcommands:
#   convert  - Convert frontmatter between YAML and TOML formats
#   list     - List content files by status
#   check-links - Check for dead links
#   doctor   - Diagnose config and content issues
#   platform - Generate hosting platform config files
#   ci       - Generate CI/CD workflow files
#   import   - Import content from other systems
#   agents-md - Generate or update AGENTS.md file

require "option_parser"
require "../metadata"
require "./tool/convert_command"
require "./tool/list_command"
require "./tool/deadlink_command"
require "./tool/doctor_command"
require "./tool/platform_command"
require "./tool/ci_command"
require "./tool/import_command"
require "./tool/agents_md_command"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class ToolCommand
        # Single source of truth for command metadata
        NAME               = "tool"
        DESCRIPTION        = "Utility tools (convert, list, check-links, doctor, ...)"
        POSITIONAL_ARGS    = [] of String
        POSITIONAL_CHOICES = [] of String

        FLAGS = [
          HELP_FLAG,
        ]

        # Subcommand registry - single registration point for dispatch and metadata
        @@sub_handlers = {} of String => Proc(Array(String), Nil)
        @@sub_metadata = [] of CommandInfo

        private def self.register_sub(metadata : CommandInfo, &handler : Array(String) -> Nil)
          @@sub_handlers[metadata.name] = handler
          @@sub_metadata << metadata
        end

        # Register all subcommands
        register_sub(Tool::ConvertCommand.metadata) { |args| Tool::ConvertCommand.new.run(args) }
        register_sub(Tool::ListCommand.metadata) { |args| Tool::ListCommand.new.run(args) }
        register_sub(Tool::DeadlinkCommand.metadata) { |args| Tool::DeadlinkCommand.new.run(args) }
        register_sub(Tool::DoctorCommand.metadata) { |args| Tool::DoctorCommand.new.run(args) }
        register_sub(Tool::PlatformCommand.metadata) { |args| Tool::PlatformCommand.new.run(args) }
        register_sub(Tool::CICommand.metadata) { |args| Tool::CICommand.new.run(args) }
        register_sub(Tool::ImportCommand.metadata) { |args| Tool::ImportCommand.new.run(args) }
        register_sub(Tool::AgentsMdCommand.metadata) { |args| Tool::AgentsMdCommand.new.run(args) }

        def self.subcommands : Array(CommandInfo)
          @@sub_metadata
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
          when "-h", "--help", "help"
            print_help
          else
            if handler = @@sub_handlers[subcommand]?
              handler.call(args)
            else
              Logger.error "Unknown subcommand: #{subcommand}"
              print_help
              exit(1)
            end
          end
        end

        # Category display order and membership for help output
        CATEGORIES = {
          "Content" => ["list", "convert", "check-links"],
          "Site"    => ["platform", "doctor", "import", "agents-md"],
        }

        # Hidden from help but still executable (e.g. deprecated commands)
        HIDDEN = Set{"ci"}

        private def print_help
          visible = ToolCommand.subcommands.reject { |s| HIDDEN.includes?(s.name) }
          max_len = visible.max_of(&.name.size)
          sub_by_name = visible.index_by(&.name)

          Logger.info "Usage: hwaro tool <subcommand> [options]"
          Logger.info ""
          Logger.info "Available subcommands:"

          categorized = Set(String).new
          CATEGORIES.each do |category, names|
            Logger.info ""
            Logger.info "  #{category}:"
            names.each do |name|
              if sub = sub_by_name[name]?
                Logger.info "    #{sub.name.ljust(max_len + 2)} #{sub.description}"
                categorized << name
              end
            end
          end

          # Show uncategorized commands
          uncategorized = visible.reject { |s| categorized.includes?(s.name) }
          unless uncategorized.empty?
            Logger.info ""
            Logger.info "  Other:"
            uncategorized.each do |sub|
              Logger.info "    #{sub.name.ljust(max_len + 2)} #{sub.description}"
            end
          end

          Logger.info ""
          Logger.info "Run 'hwaro tool <subcommand> --help' for more information on a subcommand."
        end
      end
    end
  end
end
