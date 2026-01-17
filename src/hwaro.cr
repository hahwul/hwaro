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
        force = false
        if ARGV.includes?("-f") || ARGV.includes?("--force")
          force = true
          ARGV.delete("-f")
          ARGV.delete("--force")
        end
        path = ARGV.shift? || "."
        Init.new.run(path, force)
      when "build"
        Build.new.run
      when "serve"
        Serve.new.run
      when "version", "-v", "--version"
        puts "hwaro version #{VERSION}"
      when "help", "-h", "--help"
        print_help
      else
        puts "Unknown command: #{command}"
        print_help
        exit(1)
      end
    rescue ex : Exception
      puts "Error: #{ex.message}"
      # Uncomment for debugging
      # ex.backtrace.each do |line|
      #   puts line
      # end
      exit(1)
    end

    private def print_help
      puts "Usage: hwaro <command> [options]"
      puts
      puts "Commands:"
      puts "  init [path]  Initialize a new project (use -f/--force to overwrite)"
      puts "  build        Build the project"
      puts "  serve  Serve the project and watch for changes"
    end
  end
end

Hwaro::CLI.new.run
