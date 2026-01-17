require "option_parser"
require "../../options/build_options"
require "../../core/build"
require "../../logger/logger"

module Hwaro
  module CLI
    module Commands
      class BuildCommand
        def run(args : Array(String))
          options = parse_options(args)
          Core::Build.new.run(options)
        end

        private def parse_options(args : Array(String)) : Options::BuildOptions
          output_dir = "public"
          drafts = false
          minify = false
          parallel = true

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro build [options]"
            parser.on("-o DIR", "--output-dir DIR", "Output directory (default: public)") { |dir| output_dir = dir }
            parser.on("-d", "--drafts", "Include draft content") { drafts = true }
            parser.on("--minify", "Minify HTML output") { minify = true }
            parser.on("--no-parallel", "Disable parallel file processing") { parallel = false }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
          end

          Options::BuildOptions.new(
            output_dir: output_dir,
            drafts: drafts,
            minify: minify,
            parallel: parallel
          )
        end
      end
    end
  end
end
