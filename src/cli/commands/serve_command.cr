require "option_parser"
require "../metadata"
require "../../config/options/serve_options"
require "../../services/server/server"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class ServeCommand
        # Single source of truth for command metadata
        NAME               = "serve"
        DESCRIPTION        = "Serve the project and watch for changes"
        POSITIONAL_ARGS    = [] of String
        POSITIONAL_CHOICES = [] of String

        # Flags defined here are used both for OptionParser and completion generation
        FLAGS = [
          FlagInfo.new(short: "-b", long: "--bind", description: "Bind address (default: 0.0.0.0)", takes_value: true, value_hint: "HOST"),
          FlagInfo.new(short: "-p", long: "--port", description: "Port to listen on (default: 3000)", takes_value: true, value_hint: "PORT"),
          FlagInfo.new(short: nil, long: "--base-url", description: "Override base_url from config.toml", takes_value: true, value_hint: "URL"),
          FlagInfo.new(short: "-d", long: "--drafts", description: "Include draft content"),
          FlagInfo.new(short: nil, long: "--open", description: "Open browser after starting server"),
          FlagInfo.new(short: "-v", long: "--verbose", description: "Show detailed output including generated files"),
          FlagInfo.new(short: nil, long: "--debug", description: "Print debug information after build"),
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
          Services::Server.new.run(options)
        end

        private def parse_options(args : Array(String)) : Config::Options::ServeOptions
          host = "0.0.0.0"
          port = 3000
          base_url = nil.as(String?)
          drafts = false
          open_browser = false
          verbose = false
          debug = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro serve [options]"
            parser.on("-b HOST", "--bind HOST", "Bind address (default: 0.0.0.0)") { |h| host = h }
            parser.on("-p PORT", "--port PORT", "Port to listen on (default: 3000)") { |p| port = p.to_i }
            parser.on("--base-url URL", "Override base_url from config.toml") { |url| base_url = url }
            parser.on("-d", "--drafts", "Include draft content") { drafts = true }
            parser.on("--open", "Open browser after starting server") { open_browser = true }
            parser.on("-v", "--verbose", "Show detailed output including generated files") { verbose = true }
            parser.on("--debug", "Print debug information after build") { debug = true }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
          end

          Config::Options::ServeOptions.new(
            host: host,
            port: port,
            base_url: base_url,
            drafts: drafts,
            open_browser: open_browser,
            verbose: verbose,
            debug: debug
          )
        end
      end
    end
  end
end
