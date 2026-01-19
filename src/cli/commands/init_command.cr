require "option_parser"
require "../../config/options/init_options"
require "../../services/initializer"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class InitCommand
        def run(args : Array(String))
          options = parse_options(args)
          Services::Initializer.new.run(options)
        end

        private def parse_options(args : Array(String)) : Config::Options::InitOptions
          path = "."
          force = false
          skip_agents_md = false
          skip_sample_content = false
          skip_taxonomies = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro init [path] [options]"
            parser.on("-f", "--force", "Force creation even if directory is not empty") { force = true }
            parser.on("--skip-agents-md", "Skip creating AGENTS.md file") { skip_agents_md = true }
            parser.on("--skip-sample-content", "Skip creating sample content files") { skip_sample_content = true }
            parser.on("--skip-taxonomies", "Skip taxonomies configuration and templates") { skip_taxonomies = true }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.any?
            end
          end

          Config::Options::InitOptions.new(path: path, force: force, skip_agents_md: skip_agents_md, skip_sample_content: skip_sample_content, skip_taxonomies: skip_taxonomies)
        end
      end
    end
  end
end
