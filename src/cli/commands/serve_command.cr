require "option_parser"
require "../../config/options/serve_options"
require "../../services/server/server"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class ServeCommand
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
