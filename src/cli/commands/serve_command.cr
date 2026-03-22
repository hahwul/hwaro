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
          INPUT_DIR_FLAG,
          FlagInfo.new(short: "-b", long: "--bind", description: "Bind address (default: 127.0.0.1)", takes_value: true, value_hint: "HOST"),
          FlagInfo.new(short: "-p", long: "--port", description: "Port to listen on (default: 3000)", takes_value: true, value_hint: "PORT"),
          BASE_URL_FLAG,
          DRAFTS_FLAG,
          INCLUDE_EXPIRED_FLAG,
          MINIFY_FLAG,
          FlagInfo.new(short: nil, long: "--open", description: "Open browser after starting server"),
          VERBOSE_FLAG,
          DEBUG_FLAG,
          FlagInfo.new(short: nil, long: "--access-log", description: "Show HTTP access log (e.g. GET requests)"),
          FlagInfo.new(short: nil, long: "--no-error-overlay", description: "Disable error overlay in browser"),
          FlagInfo.new(short: nil, long: "--live-reload", description: "Enable live reload on file changes"),
          PROFILE_FLAG,
          SKIP_CACHE_BUSTING_FLAG,
          SKIP_OG_IMAGE_FLAG,
          SKIP_IMAGE_PROCESSING_FLAG,
          ENV_FLAG,
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
          host = "127.0.0.1"
          port = 3000
          base_url = nil.as(String?)
          drafts = false
          include_expired = false
          minify = false
          open_browser = false
          verbose = false
          debug = false
          access_log = false
          error_overlay = true
          live_reload = false
          profile = false
          cache_busting = true
          skip_og_image = false
          skip_image_processing = false
          env_name = ENV["HWARO_ENV"]? || nil

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro serve [options]"
            CLI.register_flag(parser, INPUT_DIR_FLAG) { |v| input_dir = v }
            parser.on("-b HOST", "--bind HOST", "Bind address (default: 127.0.0.1)") { |h| host = h }
            parser.on("-p PORT", "--port PORT", "Port to listen on (default: 3000)") { |p| port = p.to_i }
            CLI.register_flag(parser, BASE_URL_FLAG) { |v| base_url = v }
            CLI.register_flag(parser, DRAFTS_FLAG) { |_| drafts = true }
            CLI.register_flag(parser, INCLUDE_EXPIRED_FLAG) { |_| include_expired = true }
            CLI.register_flag(parser, MINIFY_FLAG) { |_| minify = true }
            parser.on("--open", "Open browser after starting server") { open_browser = true }
            CLI.register_flag(parser, VERBOSE_FLAG) { |_| verbose = true }
            CLI.register_flag(parser, DEBUG_FLAG) { |_| debug = true }
            parser.on("--access-log", "Show HTTP access log (e.g. GET requests)") { access_log = true }
            parser.on("--no-error-overlay", "Disable error overlay in browser") { error_overlay = false }
            parser.on("--live-reload", "Enable live reload on file changes") { live_reload = true }
            CLI.register_flag(parser, PROFILE_FLAG) { |_| profile = true }
            CLI.register_flag(parser, SKIP_CACHE_BUSTING_FLAG) { |_| cache_busting = false }
            CLI.register_flag(parser, SKIP_OG_IMAGE_FLAG) { |_| skip_og_image = true }
            CLI.register_flag(parser, SKIP_IMAGE_PROCESSING_FLAG) { |_| skip_image_processing = true }
            CLI.register_flag(parser, ENV_FLAG) { |v| env_name = v }
            CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
          end

          {input_dir, Config::Options::ServeOptions.new(
            host: host,
            port: port,
            base_url: base_url,
            drafts: drafts,
            include_expired: include_expired,
            minify: minify,
            open_browser: open_browser,
            verbose: verbose,
            debug: debug,
            access_log: access_log,
            error_overlay: error_overlay,
            live_reload: live_reload,
            profile: profile,
            cache_busting: cache_busting,
            env: env_name,
            skip_og_image: skip_og_image,
            skip_image_processing: skip_image_processing,
          )}
        end
      end
    end
  end
end
