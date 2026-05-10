# Tool command - Parent command for various utility tools
#
# This command serves as a container for utility subcommands.
# Usage:
#   hwaro tool <subcommand> [options]
#
# Available subcommands:
#   convert       - Convert frontmatter between YAML and TOML formats
#   list          - List content files by status
#   check-links   - Check for dead links
#   stats         - Show content statistics
#   validate      - Validate content frontmatter and markup
#   unused-assets - Find unreferenced static files
#   doctor        - Diagnose config, template, and structure issues
#   platform      - Generate hosting platform config files
#   ci            - Generate CI/CD workflow files
#   import        - Import content from other systems
#   export        - Export content to other platforms
#   agents-md     - Generate or update AGENTS.md file

require "option_parser"
require "../metadata"
require "./tool/convert_command"
require "./tool/list_command"
require "./tool/deadlink_command"
require "./tool/doctor_command"
require "./tool/platform_command"
require "./tool/ci_command"
require "./tool/import_command"
require "./tool/export_command"
require "./tool/stats_command"
require "./tool/validate_command"
require "./tool/unused_assets_command"
require "./tool/agents_md_command"
require "../../utils/errors"
require "../../utils/logger"
require "../../utils/command_suggester"

module Hwaro
  module CLI
    module Commands
      class ToolCommand
        # Single source of truth for command metadata
        NAME               = "tool"
        DESCRIPTION        = "Utility tools (stats, validate, export, doctor, ...)"
        POSITIONAL_ARGS    = [] of String
        POSITIONAL_CHOICES = [] of String

        FLAGS = [
          QUIET_FLAG,
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
        register_sub(Tool::ExportCommand.metadata) { |args| Tool::ExportCommand.new.run(args) }
        register_sub(Tool::StatsCommand.metadata) { |args| Tool::StatsCommand.new.run(args) }
        register_sub(Tool::ValidateCommand.metadata) { |args| Tool::ValidateCommand.new.run(args) }
        register_sub(Tool::UnusedAssetsCommand.metadata) { |args| Tool::UnusedAssetsCommand.new.run(args) }
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
              ToolCommand.report_unknown_subcommand(subcommand, args)
            end
          end
        end

        # Raise a classified usage error for an unknown `tool <subcommand>`,
        # mirroring the top-level Runner behavior. The `Did you mean …`
        # suggestion is printed to stderr in text mode only; the final
        # `Error [HWARO_E_USAGE]: …` line (and the help hint) come from the
        # Runner's shared `emit_hwaro_error` path.
        def self.report_unknown_subcommand(subcommand : String, args : Array(String) = [] of String)
          json_mode = args.includes?("--json")
          unless json_mode
            candidates = ToolCommand.subcommands.map(&.name)
            if suggestion = Utils::CommandSuggester.suggest(subcommand, candidates)
              STDERR.puts "Did you mean '#{suggestion}'?"
            end
          end
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "unknown command 'tool #{subcommand}'",
            hint: "Run 'hwaro tool --help' to see all subcommands.",
          )
        end

        # Category display order and membership for help output
        CATEGORIES = {
          "Content" => ["list", "convert", "check-links", "stats", "validate", "unused-assets"],
          "Site"    => ["platform", "doctor", "import", "export", "agents-md"],
        }

        # Hidden from help but still executable (e.g. deprecated commands)
        HIDDEN = Set{"ci"}

        private def print_help
          visible = ToolCommand.subcommands.reject { |s| HIDDEN.includes?(s.name) }
          sub_by_name = visible.index_by(&.name)

          # Render usage syntax inline so mandatory positional args (e.g.
          # `<all|drafts|published>` for `list`) are visible without
          # drilling into each subcommand's `--help`. Width is computed
          # over the rendered "name + args" string, not just the name.
          name_with_args = ->(sub : CommandInfo) { format_usage(sub) }
          max_len = visible.max_of { |s| name_with_args.call(s).size }

          Logger.info "Usage: hwaro tool <subcommand> [options]"
          Logger.info ""
          Logger.info "Available subcommands:"

          categorized = Set(String).new
          CATEGORIES.each do |category, names|
            Logger.info ""
            Logger.info "  #{category}:"
            names.each do |name|
              if sub = sub_by_name[name]?
                Logger.info "    #{name_with_args.call(sub).ljust(max_len + 2)} #{sub.description}"
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
              Logger.info "    #{name_with_args.call(sub).ljust(max_len + 2)} #{sub.description}"
            end
          end

          Logger.info ""
          Logger.info "Run 'hwaro tool <subcommand> --help' for more information on a subcommand."
        end

        # Render a subcommand's usage signature for the help summary:
        # `name <choice|...>` when the command exposes a closed choice
        # positional (list, convert, export), `name <arg>` for free-form
        # positionals, or just `name`. Inline choice lists longer than
        # CHOICE_INLINE_LIMIT collapse to the positional arg name (e.g.
        # `import <source-type> <path>`) so wide alternatives like
        # `wordpress|jekyll|hugo|notion|...` don't blow out the column.
        private CHOICE_INLINE_LIMIT = 40

        private def format_usage(sub : CommandInfo) : String
          parts = [sub.name]
          if !sub.positional_choices.empty?
            joined = sub.positional_choices.join("|")
            head = if joined.size <= CHOICE_INLINE_LIMIT
                     "<#{joined}>"
                   else
                     # Fall back to the positional arg label when the
                     # choices list is too wide for the summary table.
                     placeholder = sub.positional_args.first? || "value"
                     "<#{placeholder}>"
                   end
            parts << head
            # Tail args after the choice slot — e.g. `import` takes
            # `<source-type> <path>`, where path is free-form.
            sub.positional_args[1..]?.try &.each { |arg| parts << "<#{arg}>" }
          else
            sub.positional_args.each { |arg| parts << "<#{arg}>" }
          end
          parts.join(" ")
        end
      end
    end
  end
end
