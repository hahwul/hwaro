require "./commands/init_command"
require "./commands/build_command"
require "./commands/serve_command"
require "../logger/logger"

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
          Logger.info "hwaro version #{Hwaro::VERSION}"
        when "help", "-h", "--help"
          print_help
        else
          Logger.error "Unknown command: #{command}"
          print_help
          exit(1)
        end
      rescue ex : OptionParser::InvalidOption
        Logger.error "Error: #{ex.message}"
        exit(1)
      rescue ex : Exception
        Logger.error "Error: #{ex.message}"
        exit(1)
      end

      private def print_help
        Logger.info "Usage: hwaro <command> [options]"
        Logger.info ""
        Logger.info "Commands:"
        Logger.info "  init   Initialize a new project"
        Logger.info "  build  Build the project"
        Logger.info "  serve  Serve the project and watch for changes"
        Logger.info "  version Show version"
        Logger.info "  help    Show this help"
        Logger.info ""
        Logger.info "Run 'hwaro <command> --help' for more information on a command."
      end
    end
  end
end
