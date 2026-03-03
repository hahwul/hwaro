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
          FlagInfo.new(short: "-i", long: "--input", description: "Input directory (default: current directory)", takes_value: true, value_hint: "DIR"),
          FlagInfo.new(short: "-b", long: "--bind", description: "Bind address (default: 0.0.0.0)", takes_value: true, value_hint: "HOST"),
          FlagInfo.new(short: "-p", long: "--port", description: "Port to listen on (default: 3000)", takes_value: true, value_hint: "PORT"),
          FlagInfo.new(short: nil, long: "--base-url", description: "Override base_url from config.toml", takes_value: true, value_hint: "URL"),
          FlagInfo.new(short: "-d", long: "--drafts", description: "Include draft content"),
          FlagInfo.new(short: nil, long: "--minify", description: "Minify HTML output (and minified json, xml)"),
          FlagInfo.new(short: nil, long: "--open", description: "Open browser after starting server"),
          FlagInfo.new(short: "-v", long: "--verbose", description: "Show detailed output including generated files"),
          FlagInfo.new(short: nil, long: "--debug", description: "Print debug information after build"),
          FlagInfo.new(short: nil, long: "--access-log", description: "Show HTTP access log (e.g. GET requests)"),
          FlagInfo.new(short: nil, long: "--no-error-overlay", description: "Disable error overlay in browser"),
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
          input_dir, options = parse_options(args)

          if input_dir
            unless Dir.exists?(input_dir)
              Logger.error "Input directory does not exist: #{input_dir}"
              exit(1)
            end
            Logger.info "Changing working directory to: #{input_dir}"
            Dir.cd(input_dir)
          end

          Services::Server.new.run(options)
        end

        private def parse_options(args : Array(String)) : {String?, Config::Options::ServeOptions}
          input_dir = nil.as(String?)
          host = "0.0.0.0"
          port = 3000
          base_url = nil.as(String?)
          drafts = false
          minify = false
          open_browser = false
          verbose = false
          debug = false
          access_log = false
          error_overlay = true

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro serve [options]"
            parser.on("-i DIR", "--input DIR", "Input directory (default: current directory)") { |dir| input_dir = dir }
            parser.on("-b HOST", "--bind HOST", "Bind address (default: 0.0.0.0)") { |h| host = h }
            parser.on("-p PORT", "--port PORT", "Port to listen on (default: 3000)") { |p| port = p.to_i }
            parser.on("--base-url URL", "Override base_url from config.toml") { |url| base_url = url }
            parser.on("-d", "--drafts", "Include draft content") { drafts = true }
            parser.on("--minify", "Minify HTML output (and minified json, xml)") { minify = true }
            parser.on("--open", "Open browser after starting server") { open_browser = true }
            parser.on("-v", "--verbose", "Show detailed output including generated files") { verbose = true }
            parser.on("--debug", "Print debug information after build") { debug = true }
            parser.on("--access-log", "Show HTTP access log (e.g. GET requests)") { access_log = true }
            parser.on("--no-error-overlay", "Disable error overlay in browser") { error_overlay = false }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
          end

          {input_dir, Config::Options::ServeOptions.new(
            host: host,
            port: port,
            base_url: base_url,
            drafts: drafts,
            minify: minify,
            open_browser: open_browser,
            verbose: verbose,
            debug: debug,
            access_log: access_log,
            error_overlay: error_overlay,
          )}
        end
      end
    end
  end
end
