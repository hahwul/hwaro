require "option_parser"
require "json"
require "../metadata"
require "../../config/options/new_options"
require "../../models/config"
require "../../services/creator"
require "../../utils/errors"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class NewCommand
        # Single source of truth for command metadata
        NAME               = "new"
        DESCRIPTION        = "Create a new content file"
        POSITIONAL_ARGS    = ["path"]
        POSITIONAL_CHOICES = [] of String

        # Flags defined here are used both for OptionParser and completion generation
        FLAGS = [
          # Content metadata
          FlagInfo.new(short: "-t", long: "--title", description: "Content title", takes_value: true, value_hint: "TITLE"),
          FlagInfo.new(short: nil, long: "--date", description: "Content date (default: now, e.g. 2026-03-22)", takes_value: true, value_hint: "DATE"),
          FlagInfo.new(short: nil, long: "--draft", description: "Mark as draft"),
          FlagInfo.new(short: nil, long: "--tags", description: "Comma-separated tags", takes_value: true, value_hint: "TAGS"),
          FlagInfo.new(short: "-s", long: "--section", description: "Section directory (e.g. blog, docs)", takes_value: true, value_hint: "NAME"),
          FlagInfo.new(short: "-a", long: "--archetype", description: "Archetype to use", takes_value: true, value_hint: "NAME"),
          FlagInfo.new(short: nil, long: "--bundle", description: "Create a leaf-bundle directory (foo/index.md) instead of a single file"),
          FlagInfo.new(short: nil, long: "--no-bundle", description: "Create a single file (foo.md); overrides config default"),

          # Introspection
          FlagInfo.new(short: nil, long: "--list-archetypes", description: "List archetypes available in the current project and exit"),
          FlagInfo.new(short: nil, long: "--json", description: "Emit machine-readable JSON output"),

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

        ARCHETYPES_DIR = "archetypes"

        def run(args : Array(String))
          if args.includes?("--list-archetypes")
            json_mode = args.includes?("--json")
            print_archetypes(json_mode)
            return
          end

          options, json_output = parse_options(args)

          # Signal json mode to the Runner so any HwaroError we raise is
          # rendered as the structured payload on stdout instead of the
          # human "Error [CODE]: …" line on stderr. Also silence the
          # `Created new content: …` info line so stdout stays pure JSON.
          if json_output
            Runner.json_mode = true
            Logger.quiet = true
          end

          # `hwaro new` is flag-only: there is no interactive prompt, so a
          # missing <path> always fails fast with a classified usage error.
          # Keeping this a HwaroError lets both text and --json consumers see
          # the same taxonomy (code/category/exit).
          raw_path = options.path
          if raw_path.nil?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "missing <path> argument",
              hint: "Usage: hwaro new <path> [options] — run 'hwaro new --help' for details.",
            )
          end

          # Canonicalize early so the rest of the pipeline (and the
          # `Created new content: …` log line) works with a path that
          # has no `..`, no absolute-root leak, and no double slashes.
          # Empty / absolute / content-escaping paths fail here with a
          # classified usage error instead of silently landing at an
          # unexpected filesystem location.
          begin
            normalized = Services::Creator.validate_and_normalize_path!(raw_path)
          rescue ex : ArgumentError
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: ex.message || "Invalid <path> argument",
              hint: "Usage: hwaro new <path> [options] — run 'hwaro new --help' for details.",
            )
          end

          # Auto-sanitize URL-unsafe characters (spaces, `!@#$%…`) in each
          # path segment so the on-disk directory also works as a clean URL
          # path once the site is built. CJK / Unicode letters, digits, and
          # the RFC 3986 unreserved ASCII set pass through untouched. We
          # surface the rewrite via `Logger.info` so the author sees what
          # landed on disk — silent transformation would be confusing.
          sanitized = Services::Creator.sanitize_url_path(normalized)
          if sanitized != normalized
            Logger.info "Sanitized path: '#{normalized}' → '#{sanitized}' (URL-unsafe characters replaced)"
          end

          # Feed the sanitized path back into the Creator. The stored
          # path keeps the `content/` prefix so downstream branches that
          # check `starts_with?("content/")` take the already-rooted
          # path as-is (see Creator#run).
          options.path = sanitized

          created_path = Services::Creator.new.run(options, load_config_if_present)

          if json_output
            payload = {
              "status" => "ok",
              "path"   => created_path,
            }
            STDOUT.puts payload.to_json
          end
        end

        # Try to load `config.toml` so `hwaro new` can honour site-level
        # preferences (front matter format, default fields). A missing
        # `config.toml` is tolerated (freshly-scaffolded projects), but a
        # malformed one is surfaced as the same classified HwaroError every
        # other command raises — silent fallback would mask user typos.
        private def load_config_if_present : Models::Config?
          return unless File.exists?("config.toml")
          Models::Config.load
        end

        # Print archetypes found under the current project's archetypes/ dir.
        # When the directory does not exist, the list is empty (not an error).
        private def print_archetypes(json : Bool)
          entries = discover_archetypes

          if json
            mapped = entries.map { |e| {name: e[:name], path: e[:path]} }
            STDOUT.puts mapped.to_json
          else
            if entries.empty?
              Logger.info "No archetypes found."
              return
            end

            Logger.info "Available archetypes:"
            entries.each do |e|
              Logger.info "  #{e[:name].ljust(16)} #{e[:path]}"
            end
          end
        end

        private def discover_archetypes : Array(NamedTuple(name: String, path: String))
          results = [] of NamedTuple(name: String, path: String)
          return results unless Dir.exists?(ARCHETYPES_DIR)

          Dir.glob(File.join(ARCHETYPES_DIR, "**", "*.md")).sort.each do |path|
            # Strip the leading "archetypes/" segment and the ".md" suffix so
            # the name matches how users pass it via --archetype.
            prefix = "#{ARCHETYPES_DIR}/"
            rel = path.starts_with?(prefix) ? path[prefix.size..] : path
            name = rel.ends_with?(".md") ? rel[0...-3] : rel
            results << {name: name, path: path}
          end

          results
        end

        def parse_options(args : Array(String)) : {Config::Options::NewOptions, Bool}
          path = nil.as(String?)
          title = nil.as(String?)
          archetype = nil.as(String?)
          date = nil.as(String?)
          draft = nil.as(Bool?)
          tags = [] of String
          section = nil.as(String?)
          bundle = nil.as(Bool?)
          json_output = args.includes?("--json")

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro new <path> [options]"

            # Content metadata
            parser.on("-t TITLE", "--title TITLE", "Content title") { |t| title = t }
            parser.on("--date DATE", "Content date (default: now)") { |d| date = d }
            parser.on("--draft", "Mark as draft") { draft = true }
            parser.on("--tags TAGS", "Comma-separated tags") { |t| tags = t.split(",").map(&.strip).reject(&.empty?) }
            parser.on("-s NAME", "--section NAME", "Section directory (e.g. blog, docs)") { |s| section = s }
            parser.on("-a NAME", "--archetype NAME", "Archetype to use") { |a| archetype = a }
            # `--bundle` / `--no-bundle` are mutually exclusive in intent but
            # OptionParser doesn't enforce that — last one wins, which matches
            # typical Unix convention.
            parser.on("--bundle", "Create a leaf-bundle directory (foo/index.md)") { bundle = true }
            parser.on("--no-bundle", "Create a single file (foo.md)") { bundle = false }
            parser.on("--json", "Emit machine-readable JSON output") { json_output = true }
            CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
            CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.present?
            end
          end

          {Config::Options::NewOptions.new(
            path: path,
            title: title,
            archetype: archetype,
            date: date,
            draft: draft,
            tags: tags,
            section: section,
            bundle: bundle,
          ), json_output}
        end
      end
    end
  end
end
