require "option_parser"
require "json"
require "../metadata"
require "../../config/options/new_options"
require "../../services/creator"
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

          # Introspection
          FlagInfo.new(short: nil, long: "--list-archetypes", description: "List archetypes available in the current project and exit"),
          FlagInfo.new(short: nil, long: "--json", description: "Emit machine-readable JSON output (with --list-archetypes)"),

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

          options = parse_options(args)

          # `hwaro new` is flag-only: there is no interactive prompt, so a
          # missing <path> always fails fast with a clear usage error. This
          # keeps behavior identical across TTY, CI, and agent environments.
          if options.path.nil?
            STDERR.puts "Error: missing <path> argument"
            STDERR.puts "Usage: hwaro new <path> [options]"
            STDERR.puts "Run 'hwaro new --help' for details."
            exit(2)
          end

          Services::Creator.new.run(options)
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

        def parse_options(args : Array(String)) : Config::Options::NewOptions
          path = nil.as(String?)
          title = nil.as(String?)
          archetype = nil.as(String?)
          date = nil.as(String?)
          draft = nil.as(Bool?)
          tags = [] of String
          section = nil.as(String?)

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro new <path> [options]"

            # Content metadata
            parser.on("-t TITLE", "--title TITLE", "Content title") { |t| title = t }
            parser.on("--date DATE", "Content date (default: now)") { |d| date = d }
            parser.on("--draft", "Mark as draft") { draft = true }
            parser.on("--tags TAGS", "Comma-separated tags") { |t| tags = t.split(",").map(&.strip).reject(&.empty?) }
            parser.on("-s NAME", "--section NAME", "Section directory (e.g. blog, docs)") { |s| section = s }
            parser.on("-a NAME", "--archetype NAME", "Archetype to use") { |a| archetype = a }
            CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
            CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.any?
            end
          end

          Config::Options::NewOptions.new(
            path: path,
            title: title,
            archetype: archetype,
            date: date,
            draft: draft,
            tags: tags,
            section: section,
          )
        end
      end
    end
  end
end
