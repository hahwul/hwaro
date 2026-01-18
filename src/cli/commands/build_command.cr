require "option_parser"
require "../../config/options/build_options"
require "../../core/build/builder"
require "../../content/hooks"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class BuildCommand
        def run(args : Array(String))
          options = parse_options(args)
          builder = Core::Build::Builder.new

          # Register content hooks with lifecycle
          Content::Hooks.all.each do |hookable|
            builder.register(hookable)
          end

          builder.run(options)
        end

        private def parse_options(args : Array(String)) : Config::Options::BuildOptions
          output_dir = "public"
          drafts = false
          minify = false
          parallel = true
          cache = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro build [options]"
            parser.on("-o DIR", "--output-dir DIR", "Output directory (default: public)") { |dir| output_dir = dir }
            parser.on("-d", "--drafts", "Include draft content") { drafts = true }
            parser.on("--minify", "Minify HTML output") { minify = true }
            parser.on("--no-parallel", "Disable parallel file processing") { parallel = false }
            parser.on("--cache", "Enable build caching (skip unchanged files)") { cache = true }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
          end

          Config::Options::BuildOptions.new(
            output_dir: output_dir,
            drafts: drafts,
            minify: minify,
            parallel: parallel,
            cache: cache
          )
        end
      end
    end
  end
end
