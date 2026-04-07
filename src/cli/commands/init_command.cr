require "option_parser"
require "../metadata"
require "../../config/options/init_options"
require "../../services/initializer"
require "../../services/scaffolds/remote"
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
          # Project setup
          FlagInfo.new(short: "-f", long: "--force", description: "Force creation even if directory is not empty"),
          FlagInfo.new(short: nil, long: "--scaffold", description: "Scaffold type or remote source (e.g., blog, github:user/repo)", takes_value: true, value_hint: "TYPE"),
          FlagInfo.new(short: nil, long: "--include-multilingual", description: "Enable multilingual support (e.g., en,ko)", takes_value: true, value_hint: "LANGS"),
          FlagInfo.new(short: nil, long: "--minimal-config", description: "Generate minimal config.toml without comments and optional sections"),
          FlagInfo.new(short: nil, long: "--agents", description: "AGENTS.md content mode: remote (lightweight, default) or local (full embedded)", takes_value: true, value_hint: "MODE"),

          # Skip options
          FlagInfo.new(short: nil, long: "--skip-agents-md", description: "Skip creating AGENTS.md file"),
          FlagInfo.new(short: nil, long: "--skip-sample-content", description: "Skip creating sample content files"),
          FlagInfo.new(short: nil, long: "--skip-taxonomies", description: "Skip taxonomies configuration and templates"),

          # Debug & output
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
          # Project setup
          path = "."
          force = false
          scaffold = Config::Options::ScaffoldType::Simple
          scaffold_remote : String? = nil
          multilingual_languages = [] of String
          minimal_config = false
          agents_mode = Config::Options::AgentsMode::Remote

          # Skip options
          skip_agents_md = false
          skip_sample_content = false
          skip_taxonomies = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro init [path] [options]"

            # Project setup
            parser.on("-f", "--force", "Force creation even if directory is not empty") { force = true }
            parser.on("--scaffold TYPE", "Scaffold type or remote source (e.g., blog, github:user/repo)") do |type|
              if Services::Scaffolds::Remote.remote?(type)
                scaffold_remote = type
              else
                begin
                  scaffold = Config::Options::ScaffoldType.from_string(type)
                rescue ex : ArgumentError
                  Logger.error(ex.message || "Unknown error")
                  Logger.info "Available scaffolds:"
                  Logger.info "  simple    - Basic pages structure with homepage and about page"
                  Logger.info "  blog      - Blog-focused structure with posts, archives, and taxonomies"
                  Logger.info "  blog-dark - Blog-focused structure with dark theme"
                  Logger.info "  docs      - Documentation-focused structure with organized sections and sidebar"
                  Logger.info "  docs-dark - Documentation-focused structure with dark theme"
                  Logger.info "  book      - Book-style structure with chapters and prev/next navigation"
                  Logger.info "  book-dark - Book-style structure with dark theme"
                  Logger.info ""
                  Logger.info "Remote scaffolds:"
                  Logger.info "  github:owner/repo[/path] - GitHub repository shorthand"
                  Logger.info "  https://github.com/...   - Full GitHub URL (with optional subpath)"
                  exit(1)
                end
              end
            end
            parser.on("--include-multilingual LANGS", "Enable multilingual support (e.g., en,ko)") do |langs|
              multilingual_languages = langs.split(",").map(&.strip).reject(&.empty?)
            end
            parser.on("--minimal-config", "Generate minimal config.toml without comments and optional sections") { minimal_config = true }
            parser.on("--agents MODE", "AGENTS.md content mode: remote (default) or local") do |mode|
              begin
                agents_mode = Config::Options::AgentsMode.from_string(mode)
              rescue ex : ArgumentError
                Logger.error(ex.message || "Unknown error")
                Logger.info "Available modes:"
                Logger.info "  remote - Lightweight with links to online docs (default)"
                Logger.info "  local  - Full embedded reference for offline use"
                exit(1)
              end
            end

            # Skip options
            parser.on("--skip-agents-md", "Skip creating AGENTS.md file") { skip_agents_md = true }
            parser.on("--skip-sample-content", "Skip creating sample content files") { skip_sample_content = true }
            parser.on("--skip-taxonomies", "Skip taxonomies configuration and templates") { skip_taxonomies = true }

            # Debug & output
            parser.on("-h", "--help", "Show this help") do
              Logger.info parser.to_s
              Logger.info ""
              Logger.info "Available scaffolds:"
              Logger.info "  simple    - Basic pages structure with homepage and about page (default)"
              Logger.info "  blog      - Blog-focused structure with posts, archives, and taxonomies"
              Logger.info "  blog-dark - Blog-focused structure with dark theme"
              Logger.info "  docs      - Documentation-focused structure with organized sections and sidebar"
              Logger.info "  docs-dark - Documentation-focused structure with dark theme"
              Logger.info "  book      - Book-style structure with chapters and prev/next navigation"
              Logger.info "  book-dark - Book-style structure with dark theme"
              Logger.info ""
              Logger.info "Remote scaffolds:"
              Logger.info "  github:owner/repo        - GitHub repository shorthand"
              Logger.info "  https://github.com/...   - Full GitHub URL"
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
            scaffold: scaffold,
            scaffold_remote: scaffold_remote,
            agents_mode: agents_mode,
            minimal_config: minimal_config
          )
        end
      end
    end
  end
end
