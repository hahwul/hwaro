require "option_parser"
require "../../options/new_options"
require "../../core/new/creator"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class NewCommand
        def run(args : Array(String))
          options = parse_options(args)
          Core::New::Creator.new.run(options)
        end

        private def parse_options(args : Array(String)) : Options::NewOptions
          path = nil
          title = nil

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro new [path]"
            parser.on("-t TITLE", "--title=TITLE", "Content title") { |t| title = t }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.any?
            end
          end

          Options::NewOptions.new(path: path, title: title)
        end
      end
    end
  end
end
