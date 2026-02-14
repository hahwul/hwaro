require "option_parser"
require "../metadata"
require "../../config/options/init_options"
require "../../services/initializer"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class InitCommand
        # Single source of truth for command metadata
        NAME               = "init"
        DESCRIPTION        = "Initialize a new project"
        POSITIONAL_ARGS    = ["path"]
        POSITIONAL_CHOICES = [] of String

        # Flags defined here are used both for OptionParser and completion generation
        FLAGS = [
          FlagInfo.new(short: "-f", long: "--force", description: "Force creation even if directory is not empty"),
          FlagInfo.new(short: nil, long: "--scaffold", description: "Scaffold type: simple, blog, docs", takes_value: true, value_hint: "TYPE"),
          FlagInfo.new(short: nil, long: "--skip-agents-md", description: "Skip creating AGENTS.md file"),
          FlagInfo.new(short: nil, long: "--skip-sample-content", description: "Skip creating sample content files"),
          FlagInfo.new(short: nil, long: "--skip-taxonomies", description: "Skip taxonomies configuration and templates"),
          FlagInfo.new(short: nil, long: "--include-multilingual", description: "Enable multilingual support (e.g., en,ko)", takes_value: true, value_hint: "LANGS"),
          HELP_FLAG,
        ]

        def self.metadata : CommandInfo
          CommandInfo.new(
            name: NAME,
            description: DESCRIPTION,
            flags: FLAGS,
            positional_args: POSITIONAL_ARGS,
            positional_choices: POSITIONAL_CHOICES
          )
        end

        def run(args : Array(String))
          options = parse_options(args)
          Services::Initializer.new.run(options)
        end

        def parse_options(args : Array(String)) : Config::Options::InitOptions
          path = "."
          force = false
          skip_agents_md = false
          skip_sample_content = false
          skip_taxonomies = false
          multilingual_languages = [] of String
          scaffold = "simple"

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro init [path] [options]"
            parser.on("-f", "--force", "Force creation even if directory is not empty") { force = true }
            parser.on("--scaffold TYPE", "Scaffold type: simple, blog, docs or URL (default: simple)") do |type|
              scaffold = type
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
