require "./metadata"
require "./commands/init_command"
require "./commands/build_command"
require "./commands/serve_command"
require "./commands/new_command"
require "./commands/deploy_command"
require "./commands/tool_command"
require "./commands/completion_command"
require "../utils/logger"

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
        if ARGV.empty?
          print_help
          exit
        end

        command = ARGV.shift
        args = ARGV.dup

        case command
        when "version", "-v", "--version"
          Logger.info "hwaro version #{Hwaro::VERSION}"
        when "help", "-h", "--help"
          print_help
        else
          # Try to get command from registry
          if handler = CommandRegistry.get(command)
            handler.call(args)
          else
            Logger.error "Unknown command: #{command}"
            print_help
            exit(1)
          end
        end
      rescue ex : OptionParser::InvalidOption
        Logger.error "Error: #{ex.message}"
        exit(1)
      rescue ex : Exception
        Logger.error "Error: #{ex.message}"
        exit(1)
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

        # Register completion command
        CommandRegistry.register(Commands::CompletionCommand.metadata) do |args|
          Commands::CompletionCommand.new.run(args)
        end
      end

      private def print_help
        Logger.info "Usage: hwaro <command> [options]"
        Logger.info "Hwaro is a fast and lightweight static site generator written in Crystal."
        Logger.info ""
        Logger.info "Commands:"

        # Define priority order
        priority = ["init", "build", "serve", "new", "deploy"]

        # Print registered commands
        CommandRegistry.all.sort_by { |cmd|
          priority.index(cmd[:name]) || priority.size
        }.each do |cmd|
          Logger.info "  #{cmd[:name].ljust(8)} #{cmd[:description]}"
        end

        Logger.info "  version  Show version"
        Logger.info "  help     Show this help"
        Logger.info ""
        Logger.info "Run 'hwaro <command> --help' for more information on a command."
      end
    end
  end
end
