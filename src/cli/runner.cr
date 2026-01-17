require "./commands/init_command"
require "./commands/build_command"
require "./commands/serve_command"

module Hwaro
  module CLI
    class Runner
      def run
        if ARGV.empty?
          print_help
          exit
        end

        command = ARGV.shift
        args = ARGV.dup

        case command
        when "init"
          Commands::InitCommand.new.run(args)
        when "build"
          Commands::BuildCommand.new.run(args)
        when "serve"
          Commands::ServeCommand.new.run(args)
        when "version", "-v", "--version"
          puts "hwaro version #{Hwaro::VERSION}"
        when "help", "-h", "--help"
          print_help
        else
          puts "Unknown command: #{command}"
          print_help
          exit(1)
        end
      rescue ex : OptionParser::InvalidOption
        puts "Error: #{ex.message}"
        exit(1)
      rescue ex : Exception
        puts "Error: #{ex.message}"
        exit(1)
      end

      private def print_help
        puts "Usage: hwaro <command> [options]"
        puts
        puts "Commands:"
        puts "  init   Initialize a new project"
        puts "  build  Build the project"
        puts "  serve  Serve the project and watch for changes"
        puts "  version Show version"
        puts "  help    Show this help"
        puts
        puts "Run 'hwaro <command> --help' for more information on a command."
      end
    end
  end
end
