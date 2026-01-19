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
          multilingual_languages = [] of String
          scaffold = Config::Options::ScaffoldType::Simple

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro init [path] [options]"
            parser.on("-f", "--force", "Force creation even if directory is not empty") { force = true }
            parser.on("--scaffold TYPE", "Scaffold type: simple, blog, docs (default: simple)") do |type|
              begin
                scaffold = Config::Options::ScaffoldType.from_string(type)
              rescue ex : ArgumentError
                Logger.error ex.message.not_nil!
                Logger.info "Available scaffolds:"
                Logger.info "  simple  - Basic pages structure with homepage and about page"
                Logger.info "  blog    - Blog-focused structure with posts, archives, and taxonomies"
                Logger.info "  docs    - Documentation-focused structure with organized sections and sidebar"
                exit(1)
              end
            end
            parser.on("--skip-agents-md", "Skip creating AGENTS.md file") { skip_agents_md = true }
            parser.on("--skip-sample-content", "Skip creating sample content files") { skip_sample_content = true }
            parser.on("--skip-taxonomies", "Skip taxonomies configuration and templates") { skip_taxonomies = true }
            parser.on("--include-multilingual LANGS", "Enable multilingual support (e.g., en,ko)") do |langs|
              multilingual_languages = langs.split(",").map(&.strip).reject(&.empty?)
            end
            parser.on("-h", "--help", "Show this help") do
              Logger.info parser.to_s
              Logger.info ""
              Logger.info "Available scaffolds:"
              Logger.info "  simple  - Basic pages structure with homepage and about page (default)"
              Logger.info "  blog    - Blog-focused structure with posts, archives, and taxonomies"
              Logger.info "  docs    - Documentation-focused structure with organized sections and sidebar"
              exit
            end
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.any?
            end
          end

          Config::Options::InitOptions.new(
            path: path,
            force: force,
            skip_agents_md: skip_agents_md,
            skip_sample_content: skip_sample_content,
            skip_taxonomies: skip_taxonomies,
            multilingual_languages: multilingual_languages,
            scaffold: scaffold
          )
        end
      end
    end
  end
end
