require "option_parser"
require "../../options/init_options"
require "../../core/init"

module Hwaro
  module CLI
    module Commands
      class InitCommand
        def run(args : Array(String))
          options = parse_options(args)
          Core::Init.new.run(options)
        end

        private def parse_options(args : Array(String)) : Options::InitOptions
          path = "."
          force = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro init [path] [options]"
            parser.on("-f", "--force", "Force creation even if directory is not empty") { force = true }
            parser.on("-h", "--help", "Show this help") { puts parser; exit }
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.any?
            end
          end

          Options::InitOptions.new(path: path, force: force)
        end
      end
    end
  end
end
