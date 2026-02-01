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
          FlagInfo.new(short: "-t", long: "--title", description: "Content title", takes_value: true, value_hint: "TITLE"),
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

        private def parse_options(args : Array(String)) : Config::Options::NewOptions
          path = nil
          title = nil
          archetype = nil

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro new [path]"
            parser.on("-t TITLE", "--title=TITLE", "Content title") { |t| title = t }
            parser.on("-a NAME", "--archetype=NAME", "Archetype to use") { |a| archetype = a }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
            parser.unknown_args do |unknown|
              path = unknown.first if unknown.any?
            end
          end

          Config::Options::NewOptions.new(path: path, title: title, archetype: archetype)
        end
      end
    end
  end
end
