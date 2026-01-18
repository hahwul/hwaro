require "./commands/init_command"
require "./commands/build_command"
require "./commands/serve_command"
require "./commands/new_command"
require "../utils/logger"

module Hwaro
  module CLI
    # Command interface for all CLI commands
    abstract class Command
      abstract def name : String
      abstract def description : String
      abstract def run(args : Array(String))
    end

    # Command registry for dynamic command management
    # Allows plugins to register new commands at runtime
    class CommandRegistry
      @@commands = {} of String => Proc(Array(String), Nil)
      @@descriptions = {} of String => String

      # Register a command with its handler
      def self.register(name : String, description : String, &handler : Array(String) -> Nil)
        @@commands[name] = handler
        @@descriptions[name] = description
      end

      # Get a command handler by name
      def self.get(name : String) : Proc(Array(String), Nil)?
        @@commands[name]?
      end

      # Check if a command exists
      def self.has?(name : String) : Bool
        @@commands.has_key?(name)
      end

      # Get all registered command names
      def self.names : Array(String)
        @@commands.keys.sort
      end

      # Get command description
      def self.description(name : String) : String
        @@descriptions[name]? || ""
      end

      # List all commands with descriptions
      def self.all : Array({name: String, description: String})
        names.map { |n| {name: n, description: description(n)} }
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
        # Register init command
        CommandRegistry.register("init", "Initialize a new project") do |args|
          Commands::InitCommand.new.run(args)
        end

        # Register build command
        CommandRegistry.register("build", "Build the project") do |args|
          Commands::BuildCommand.new.run(args)
        end

        # Register serve command
        CommandRegistry.register("serve", "Serve the project and watch for changes") do |args|
          Commands::ServeCommand.new.run(args)
        end

        # Register new command
        CommandRegistry.register("new", "Create a new content file") do |args|
          Commands::NewCommand.new.run(args)
        end
      end

      private def print_help
        Logger.info "Usage: hwaro <command> [options]"
        Logger.info ""
        Logger.info "Commands:"

        # Print registered commands
        CommandRegistry.all.each do |cmd|
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
