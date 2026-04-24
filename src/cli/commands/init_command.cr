require "option_parser"
require "json"
require "../metadata"
require "../../config/options/init_options"
require "../../services/initializer"
require "../../services/scaffolds/registry"
require "../../services/scaffolds/remote"
require "../../utils/errors"
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
          FlagInfo.new(short: nil, long: "--clean", description: "Remove existing files in target before scaffolding (implies --force; refuses if target contains .git/)"),
          FlagInfo.new(short: nil, long: "--scaffold", description: "Scaffold type or remote source (e.g., blog, github:user/repo)", takes_value: true, value_hint: "TYPE"),
          FlagInfo.new(short: nil, long: "--include-multilingual", description: "Enable multilingual support (e.g., en,ko)", takes_value: true, value_hint: "LANGS"),
          FlagInfo.new(short: nil, long: "--minimal-config", description: "Generate minimal config.toml without comments and optional sections"),
          FlagInfo.new(short: nil, long: "--agents", description: "AGENTS.md content mode: remote (lightweight, default) or local (full embedded)", takes_value: true, value_hint: "MODE"),

          # Skip options
          FlagInfo.new(short: nil, long: "--skip-agents-md", description: "Skip creating AGENTS.md file"),
          FlagInfo.new(short: nil, long: "--skip-sample-content", description: "Skip creating sample content files"),
          FlagInfo.new(short: nil, long: "--skip-taxonomies", description: "Skip taxonomies configuration and templates"),

          # Introspection
          FlagInfo.new(short: nil, long: "--list-scaffolds", description: "List available built-in scaffolds and exit"),
          FlagInfo.new(short: nil, long: "--json", description: "Emit machine-readable JSON output (with --list-scaffolds)"),

          # Debug & output
          QUIET_FLAG,
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
          # Handle introspection flags before full option parsing so users can
          # list scaffolds without supplying any other arguments.
          if args.includes?("--list-scaffolds")
            json_mode = args.includes?("--json")
            print_scaffolds(json_mode)
            return
          end

          options = parse_options(args)
          Services::Initializer.new.run(options)
        end

        # Print the list of built-in scaffolds.
        #
        # Remote scaffolds are user-supplied (e.g. `github:owner/repo`) and
        # cannot be enumerated without additional input, so only built-ins
        # are listed here.
        private def print_scaffolds(json : Bool)
          entries = Services::Scaffolds::Registry.all.map do |scaffold|
            {name: scaffold.type.to_s, description: scaffold.description, kind: "builtin"}
          end

          if json
            STDOUT.puts entries.to_json
          else
            log_scaffold_list
          end
        end

        # Emit the built-in scaffold list to the standard info logger.
        # Shared by `--help`, `--list-scaffolds`, and the invalid-scaffold
        # error path so the three outputs stay in sync with the Registry.
        private def log_scaffold_list
          default_type = Config::Options::ScaffoldType::Simple
          Logger.info "Available scaffolds:"
          Services::Scaffolds::Registry.all.each do |scaffold|
            name = scaffold.type.to_s
            suffix = scaffold.type == default_type ? " (default)" : ""
            Logger.info "  #{name.ljust(10)} - #{scaffold.description}#{suffix}"
          end
        end

        def parse_options(args : Array(String)) : Config::Options::InitOptions
          # Project setup
          path = "."
          force = false
          clean = false
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
            parser.on("--clean", "Remove existing files in target before scaffolding (implies --force; refuses if target contains .git/)") { clean = true }
            parser.on("--scaffold TYPE", "Scaffold type or remote source (e.g., blog, github:user/repo)") do |type|
              if Services::Scaffolds::Remote.remote?(type)
                scaffold_remote = type
              else
                begin
                  scaffold = Config::Options::ScaffoldType.from_string(type)
                rescue ex : ArgumentError
                  Logger.error(ex.message || "Unknown error")
                  log_scaffold_list
                  Logger.info ""
                  Logger.info "Remote scaffolds:"
                  Logger.info "  github:owner/repo[/path] - GitHub repository shorthand"
                  Logger.info "  https://github.com/...   - Full GitHub URL (with optional subpath)"
                  exit(1)
                end
              end
            end
            parser.on("--include-multilingual LANGS", "Enable multilingual support (e.g., en,ko)") do |langs|
              parsed = langs.split(",").map(&.strip).reject(&.empty?)
              begin
                parsed.each { |code| Config::Options::InitOptions.validate_language_code!(code) }
              rescue ex : ArgumentError
                # Classify so the Runner emits `Error [HWARO_E_USAGE]: …`
                # and exits with the documented usage code (2).
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: ex.message || "Invalid language code",
                  hint: "Examples: 'en', 'ko', 'en,ko', 'pt-BR', 'zh-Hant'.",
                )
              end
              multilingual_languages = parsed
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

            # Introspection (handled in #run before parsing; registered here so
            # they appear in --help output).
            parser.on("--list-scaffolds", "List available built-in scaffolds and exit") { }
            parser.on("--json", "Emit machine-readable JSON output (with --list-scaffolds)") { }

            # Debug & output
            CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
            parser.on("-h", "--help", "Show this help") do
              Logger.info parser.to_s
              Logger.info ""
              log_scaffold_list
              Logger.info ""
              Logger.info "Remote scaffolds:"
              Logger.info "  github:owner/repo        - GitHub repository shorthand"
              Logger.info "  https://github.com/...   - Full GitHub URL"
              exit
            end
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.present?
            end
          end

          Config::Options::InitOptions.new(
            path: path,
            force: force,
            clean: clean,
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
