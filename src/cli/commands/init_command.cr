require "option_parser"
require "json"
require "../metadata"
require "../prompt"
require "./init_wizard"
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
          FlagInfo.new(short: "-f", long: "--force", description: "Allow init even if directory is not empty (keeps existing files, adds missing scaffold files)"),
          FlagInfo.new(short: nil, long: "--clean", description: "Remove existing files in target before scaffolding (implies --force; refuses if target contains .git/)"),
          FlagInfo.new(short: nil, long: "--scaffold", description: "Scaffold type or remote source (e.g., blog, github:user/repo)", takes_value: true, value_hint: "TYPE"),
          FlagInfo.new(short: nil, long: "--include-multilingual", description: "Enable multilingual support (e.g., en,ko)", takes_value: true, value_hint: "LANGS"),
          FlagInfo.new(short: nil, long: "--minimal-config", description: "Generate minimal config.toml without comments and optional sections"),
          FlagInfo.new(short: nil, long: "--full-config", description: "Generate full config.toml with maximum comments and optional sections for discoverability"),
          FlagInfo.new(short: nil, long: "--agents", description: "AGENTS.md content mode: remote (lightweight, default) or local (full embedded)", takes_value: true, value_hint: "MODE"),

          # Skip options
          FlagInfo.new(short: nil, long: "--skip-agents-md", description: "Skip creating AGENTS.md file"),
          FlagInfo.new(short: nil, long: "--skip-sample-content", description: "Skip creating sample content files"),
          FlagInfo.new(short: nil, long: "--skip-taxonomies", description: "Skip taxonomies configuration and templates"),

          # Introspection
          FlagInfo.new(short: nil, long: "--list-scaffolds", description: "List available built-in scaffolds and exit"),
          FlagInfo.new(short: "-j", long: "--json", description: "Emit machine-readable JSON output (with --list-scaffolds)"),

          # Wizard control
          FlagInfo.new(short: nil, long: "--wizard", description: "Run the interactive wizard (TTY only)"),

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

        # Parser state that is not part of InitOptions. Set by #parse_options
        # so #run can act on it after — rather than before — full option
        # parsing, which is what makes invalid flags alongside
        # `--list-scaffolds` an error instead of a silent no-op.
        @list_scaffolds = false
        @json_output = false
        @wizard = false
        # Whether the user actually supplied `<path>` / `--scaffold`. The
        # wizard needs the distinction: `InitOptions` defaults both fields, so
        # "not given" and "given the default value" are otherwise identical.
        @path_given = false
        @scaffold_given = false

        def run(args : Array(String))
          # Parse first: introspection and wizard eligibility are decided from
          # parsed state, so an unknown flag is rejected in every mode.
          options = parse_options(args)

          if @list_scaffolds
            print_scaffolds(@json_output)
            return
          end

          # The guided wizard runs only when `--wizard` is passed explicitly in
          # an interactive session. Every other invocation — bare `hwaro init`,
          # flags, pipes/CI, and `--quiet` — initializes immediately with
          # defaults (the former `-y`/`--yes` path).
          if wizard_eligible?
            # The wizard fills in only what the user did not already supply;
            # every other flag (`--force`, `--clean`, `--skip-*`, config mode,
            # `--agents`, `--include-multilingual`) rides along untouched.
            wizard_options = InitWizard.new.run(
              @path_given ? options.path : nil,
              options,
              @scaffold_given ? options.scaffold : nil,
            )
            if wizard_options.nil?
              Logger.info "Cancelled."
              return
            end
            Services::Initializer.new.run(wizard_options)
            return
          end

          Services::Initializer.new.run(options)
        end

        private def wizard_eligible? : Bool
          return false unless @wizard
          return false unless Prompt.interactive?
          return false if Logger.quiet?
          true
        end

        # Print the list of built-in scaffolds.
        #
        # Remote scaffolds are user-supplied (e.g. `github:owner/repo`) and
        # cannot be enumerated without additional input, so only built-ins
        # are listed here.
        private def print_scaffolds(json : Bool)
          if json
            entries = Services::Scaffolds::Registry.all.map do |scaffold|
              {name: scaffold.type.to_s, description: scaffold.description, kind: "builtin"}
            end
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
          scaffolds = Services::Scaffolds::Registry.all
          name_width = scaffolds.max_of(&.type.to_s.size)
          Logger.info "Available scaffolds:"
          scaffolds.each do |scaffold|
            name = scaffold.type.to_s
            suffix = scaffold.type == default_type ? " (default)" : ""
            Logger.info "  #{name.ljust(name_width)} - #{scaffold.description}#{suffix}"
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
          full_config = false
          agents_mode = Config::Options::AgentsMode::Remote

          # Skip options
          skip_agents_md = false
          skip_sample_content = false
          skip_taxonomies = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro init [path] [options]"

            # Project setup
            parser.on("-f", "--force", "Allow init even if directory is not empty (keeps existing files)") { force = true }
            parser.on("--clean", "Remove existing files in target before scaffolding (implies --force; refuses if target contains .git/)") { clean = true }
            parser.on("--scaffold TYPE", "Scaffold type or remote source (e.g., blog, github:user/repo)") do |type|
              @scaffold_given = true
              if Services::Scaffolds::Remote.remote?(type)
                # Validate the shorthand/URL now rather than at fetch time:
                # a malformed source used to surface as an unclassified
                # `Error: …` (exit 1) only *after* the target directory had
                # been created.
                begin
                  Services::Scaffolds::Remote.parse_source(type)
                rescue ex : ArgumentError
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: ex.message || "Invalid remote scaffold source",
                    hint: "Use github:owner/repo[/path] or https://github.com/owner/repo[/tree/branch/path].",
                  )
                end
                scaffold_remote = type
              else
                begin
                  scaffold = Config::Options::ScaffoldType.from_string(type)
                rescue ex : ArgumentError
                  # Classify so the Runner emits `Error [HWARO_E_USAGE]: …`
                  # and exits with the documented usage code (2).
                  log_scaffold_list
                  Logger.info ""
                  Logger.info "Remote scaffolds:"
                  Logger.info "  github:owner/repo[/path] - GitHub repository shorthand"
                  Logger.info "  https://github.com/...   - Full GitHub URL (with optional subpath)"
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: ex.message || "Unknown scaffold type",
                    hint: "Run 'hwaro init --list-scaffolds' to see every built-in scaffold.",
                  )
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
            parser.on("--full-config", "Generate full config.toml with all comments and optional sections (maximum discoverability)") { full_config = true }
            parser.on("--agents MODE", "AGENTS.md content mode: remote (default) or local") do |mode|
              agents_mode = Config::Options::AgentsMode.from_string(mode)
            rescue ex : ArgumentError
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: ex.message || "Unknown agents mode",
                hint: "remote = lightweight with links to online docs (default); local = full embedded reference for offline use.",
              )
            end

            # Skip options
            parser.on("--skip-agents-md", "Skip creating AGENTS.md file") { skip_agents_md = true }
            parser.on("--skip-sample-content", "Skip creating sample content files") { skip_sample_content = true }
            parser.on("--skip-taxonomies", "Skip taxonomies configuration and templates") { skip_taxonomies = true }

            # Introspection (acted on by #run after parsing, so an unknown
            # flag alongside them is still a usage error).
            parser.on("--list-scaffolds", "List available built-in scaffolds and exit") { @list_scaffolds = true }
            parser.on("-j", "--json", "Emit machine-readable JSON output (with --list-scaffolds)") { @json_output = true }

            # Wizard control (acted on by #run after parsing).
            parser.on("--wizard", "Run the interactive wizard (TTY only)") { @wizard = true }

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
            parser.unknown_args do |before_dash, after_dash|
              # Accept the single <path> from either side of `--` (the latter
              # lets users target a leading-dash directory name). Anything
              # beyond one positional is almost always an unquoted multi-word
              # site name (`hwaro init My Blog Site`) — silently dropping the
              # extras used to scaffold a whole project into a directory named
              # `My`, so reject instead. Flag-looking leftovers are not
              # positionals — leave them for OptionParser's invalid-option
              # error, which names the actual offending flag.
              positionals = before_dash.reject(&.starts_with?('-')) + after_dash
              if positionals.size > 1
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: "unexpected extra argument(s): '#{positionals[1..].join("', '")}'",
                  hint: "hwaro init takes a single [path]. Quote multi-word values, e.g. hwaro init \"My Blog\".",
                )
              end
              if first = positionals.first?
                path = first
                @path_given = true
              end
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
            minimal_config: minimal_config,
            full_config: full_config
          )
        end
      end
    end
  end
end
