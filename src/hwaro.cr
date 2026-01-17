require "option_parser"
require "yaml"
require "ecr"
require "file_utils"
require "http/server"
require "markd"
require "./hwaro/*"

module Hwaro
  VERSION = "0.1.0"

  class CLI
    def run
      if ARGV.empty?
        print_help
        exit
      end

      command = ARGV.shift

      case command
      when "init"
        run_init
      when "build"
        run_build
      when "serve"
        run_serve
      when "version", "-v", "--version"
        puts "hwaro version #{VERSION}"
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

    private def run_init
      force = false
      path = "."

      OptionParser.parse do |parser|
        parser.banner = "Usage: hwaro init [path] [options]"
        parser.on("-f", "--force", "Force creation even if directory is not empty") { force = true }
        parser.on("-h", "--help", "Show this help") { puts parser; exit }
        parser.unknown_args do |args|
          path = args.first if args.any?
        end
      end

      Init.new.run(path, force)
    end

    private def run_build
      OptionParser.parse do |parser|
        parser.banner = "Usage: hwaro build [options]"
        parser.on("-h", "--help", "Show this help") { puts parser; exit }
      end
      Build.new.run
    end

    private def run_serve
      OptionParser.parse do |parser|
        parser.banner = "Usage: hwaro serve [options]"
        parser.on("-h", "--help", "Show this help") { puts parser; exit }
      end
      Serve.new.run
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
    end
  end
end

Hwaro::CLI.new.run
