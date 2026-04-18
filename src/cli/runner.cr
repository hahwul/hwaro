require "json"
require "./metadata"
require "./commands/init_command"
require "./commands/build_command"
require "./commands/serve_command"
require "./commands/new_command"
require "./commands/deploy_command"
require "./commands/tool_command"
require "./commands/doctor_command"
require "./commands/completion_command"
require "../utils/errors"
require "../utils/logger"
require "../utils/command_suggester"

module Hwaro
  module CLI
    # Command registry for dynamic command management
    # Allows plugins to register new commands at runtime
    class CommandRegistry
      @@commands = {} of String => Proc(Array(String), Nil)
      @@metadata = {} of String => CommandInfo

      # Register a command with its handler and metadata
      def self.register(metadata : CommandInfo, &handler : Array(String) -> Nil)
        @@commands[metadata.name] = handler
        @@metadata[metadata.name] = metadata
      end

      # Get a command handler by name
      def self.get(name : String) : Proc(Array(String), Nil)?
        @@commands[name]?
      end

      # Get command metadata by name
      def self.get_metadata(name : String) : CommandInfo?
        @@metadata[name]?
      end

      # Check if a command exists
      def self.has?(name : String) : Bool
        @@commands.has_key?(name)
      end

      # Get all registered command names
      def self.names : Array(String)
        @@commands.keys.sort!
      end

      # Get command description
      def self.description(name : String) : String
        @@metadata[name]?.try(&.description) || ""
      end

      # List all commands with descriptions
      def self.all : Array({name: String, description: String})
        names.map { |n| {name: n, description: description(n)} }
      end

      # Get all command metadata
      def self.all_metadata : Array(CommandInfo)
        @@metadata.values
      end
    end

    class Runner
      def initialize
        # Register built-in commands
        register_default_commands
      end

      def run
        # Global `--quiet` / `-q` is pre-parsed here so every command
        # (including subcommands and help output) honors it without needing
        # per-command OptionParser wiring. Removed entries no longer reach
        # the command-level parser, so they never trigger InvalidOption.
        Runner.apply_global_quiet!(ARGV)

        if ARGV.empty?
          Runner.print_help
          exit
        end

        command = ARGV.shift
        args = ARGV.dup

        case command
        when "-V", "--version"
          Logger.info "#{Hwaro::VERSION}"
        when "-h", "--help"
          Runner.print_help
        else
          # Try to get command from registry
          if handler = CommandRegistry.get(command)
            handler.call(args)
          else
            # Classified usage error. The "Did you mean …" suggestion prints
            # to stderr here (text mode only) so the final error line emitted
            # by the rescue block below is the `Error [CODE]: …` form.
            if args.any? { |a| a == "--json" }
              @@json_mode = true
            else
              if suggestion = Utils::CommandSuggester.suggest(command, CommandRegistry.names)
                STDERR.puts "Did you mean '#{suggestion}'?"
              end
            end
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "unknown command '#{command}'",
              hint: "Run 'hwaro --help' to see all commands.",
            )
          end
        end
      rescue ex : Hwaro::HwaroError
        Runner.emit_hwaro_error(ex)
        exit(ex.exit_code)
      rescue ex : OptionParser::InvalidOption
        # Treat bad flags as classified usage errors so exit codes stay
        # consistent with the documented taxonomy.
        err = Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_USAGE,
          message: ex.message || "invalid option",
        )
        Runner.emit_hwaro_error(err)
        exit(err.exit_code)
      rescue ex : Exception
        Logger.error "Error: #{ex.message}"
        exit(1)
      end

      # Track --json globally so the Runner's top-level rescue can emit the
      # structured payload even after the subcommand consumed the flag.
      # Command handlers set this via `Runner.json_mode = true` as soon as
      # they parse the flag.
      @@json_mode : Bool = false

      def self.json_mode? : Bool
        @@json_mode
      end

      def self.json_mode=(value : Bool)
        @@json_mode = value
      end

      # Emit a classified error in either the quiet/JSON machine shape or the
      # human-friendly `Error [CODE]: message` form. JSON mode is detected
      # from `Runner.json_mode?` (set by commands that saw `--json`) or from
      # the raw ARGV (unknown-command path, before any parser runs).
      def self.emit_hwaro_error(err : Hwaro::HwaroError, io : IO = STDERR)
        json = @@json_mode || ARGV.includes?("--json")
        if json
          STDOUT.puts err.to_error_payload.to_json
        else
          msg = "Error [#{err.code}]: #{err.message}"
          Logger.error msg
          if hint = err.hint
            io.puts hint unless hint.empty?
          end
        end
      end

      # Strip `--quiet` / `-q` from argv and enable Logger.quiet when present.
      # Mutates the given array in place so subsequent parsers don't see it.
      def self.apply_global_quiet!(argv : Array(String))
        found = false
        argv.reject! do |arg|
          if arg == "--quiet" || arg == "-q"
            found = true
            true
          else
            false
          end
        end
        Logger.quiet = true if found
      end

      private def register_default_commands
        # Register init command using metadata from command class
        CommandRegistry.register(Commands::InitCommand.metadata) do |args|
          Commands::InitCommand.new.run(args)
        end

        # Register build command
        CommandRegistry.register(Commands::BuildCommand.metadata) do |args|
          Commands::BuildCommand.new.run(args)
        end

        # Register serve command
        CommandRegistry.register(Commands::ServeCommand.metadata) do |args|
          Commands::ServeCommand.new.run(args)
        end

        # Register new command
        CommandRegistry.register(Commands::NewCommand.metadata) do |args|
          Commands::NewCommand.new.run(args)
        end

        # Register deploy command
        CommandRegistry.register(Commands::DeployCommand.metadata) do |args|
          Commands::DeployCommand.new.run(args)
        end

        # Register tool command
        CommandRegistry.register(Commands::ToolCommand.metadata) do |args|
          Commands::ToolCommand.new.run(args)
        end

        # Register doctor command (top-level alias for `tool doctor`)
        CommandRegistry.register(Commands::DoctorCommand.metadata) do |args|
          Commands::DoctorCommand.new.run(args)
        end

        # Register completion command
        CommandRegistry.register(Commands::CompletionCommand.metadata) do |args|
          Commands::CompletionCommand.new.run(args)
        end

        # Register version command
        CommandRegistry.register(CommandInfo.new(name: "version", description: "Show version")) do |_|
          Logger.info "#{Hwaro::VERSION}"
        end

        # Register help command
        CommandRegistry.register(CommandInfo.new(name: "help", description: "Show help")) do |_|
          Runner.print_help
        end
      end

      # Write a concise unknown-command error to stderr with an optional
      # "Did you mean" suggestion. Intentionally avoids dumping the ASCII
      # banner or full command list — users can run `hwaro --help` for that.
      def self.report_unknown_command(command : String, io : IO = STDERR)
        io.puts "Error: unknown command '#{command}'"
        if suggestion = Utils::CommandSuggester.suggest(command, CommandRegistry.names)
          io.puts "Did you mean '#{suggestion}'?"
        end
        io.puts "Run 'hwaro --help' to see all commands."
      end

      def self.print_help
        # In quiet mode the banner and command listing are suppressed
        # entirely — scripts/CI just get a silent help invocation.
        return if Logger.quiet?

        art = [
          "                             ",
          "    █████████████████████    ",
          "    ██                 ██    ",
          "    ██ ███████████████ ██    ",
          "    ██ ███████████████ ██    ",
          "    ██ █ █ █ █ █ █ █ █ ██    ",
          "                             ",
          "    █████████████████████    ",
        ]

        use_color = Logger.color_enabled?
        brand = use_color ? "Hwaro".colorize(:cyan).bold.to_s : "Hwaro"
        info = [
          "",
          "",
          "",
          "  #{brand} v#{Hwaro::VERSION}",
          "",
          "  A fast and lightweight static site",
          "  generator written in Crystal.",
          "",
          "  Usage: hwaro <command> [options]",
          "",
          "",
          "",
        ]

        Logger.info ""
        art.each_with_index do |line, i|
          right = info[i]? || ""
          art_line = use_color ? line.colorize(:light_red).to_s : line
          Logger.info "#{art_line}#{right}"
        end

        Logger.info ""
        Logger.info "Commands:"

        # Define display order
        priority = ["init", "build", "serve", "new", "deploy", "doctor", "tool", "completion", "version", "help"]

        # Print registered commands in priority order
        CommandRegistry.all.sort_by { |cmd|
          priority.index(cmd[:name]) || priority.size
        }.each do |cmd|
          Logger.info "  #{cmd[:name].ljust(12)} #{cmd[:description]}"
        end

        Logger.info ""
        Logger.info "Run 'hwaro <command> --help' for more information on a command."
      end
    end
  end
end
