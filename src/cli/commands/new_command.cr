require "option_parser"
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
          Services::Creator.new.run(options)
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
