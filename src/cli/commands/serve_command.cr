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
          drafts = false
          open_browser = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro serve [options]"
            parser.on("-b HOST", "--bind HOST", "Bind address (default: 0.0.0.0)") { |h| host = h }
            parser.on("-p PORT", "--port PORT", "Port to listen on (default: 3000)") { |p| port = p.to_i }
            parser.on("-d", "--drafts", "Include draft content") { drafts = true }
            parser.on("--open", "Open browser after starting server") { open_browser = true }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
          end

          Config::Options::ServeOptions.new(
            host: host,
            port: port,
            drafts: drafts,
            open_browser: open_browser
          )
        end
      end
    end
  end
end
