require "option_parser"
require "../metadata"
require "../../config/options/serve_options"
require "../../services/server/server"
require "../../utils/errors"
require "../../utils/logger"
require "../../models/config"

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
          # Path & URL
          INPUT_DIR_FLAG,
          BASE_URL_FLAG,
          ENV_FLAG,

          # Content filtering
          DRAFTS_FLAG,
          INCLUDE_EXPIRED_FLAG,
          INCLUDE_FUTURE_FLAG,

          # Build behavior
          MINIFY_FLAG,
          JOBS_FLAG,
          FlagInfo.new(short: nil, long: "--cache", description: "Enable build caching (skip unchanged files)"),
          FlagInfo.new(short: nil, long: "--stream", description: "Enable streaming build to reduce memory usage"),
          FlagInfo.new(short: nil, long: "--memory-limit", description: "Memory limit for streaming build (e.g. 2G, 512M)", takes_value: true, value_hint: "SIZE"),
          FlagInfo.new(short: nil, long: "--fast-start", description: "Render homepage + latest N pages first, then background-render the rest"),
          FlagInfo.new(short: nil, long: "--fast-start-count", description: "Number of recent pages to render up front with --fast-start (default: 20)", takes_value: true, value_hint: "N"),

          # Server
          FlagInfo.new(short: "-b", long: "--bind", description: "Bind address (default: 127.0.0.1)", takes_value: true, value_hint: "HOST"),
          FlagInfo.new(short: "-p", long: "--port", description: "Port to listen on (default: 3000)", takes_value: true, value_hint: "PORT"),
          OPEN_BROWSER_FLAG,
          NO_OPEN_BROWSER_FLAG,
          FlagInfo.new(short: nil, long: "--access-log", description: "Show HTTP access log (e.g. GET requests)"),
          FlagInfo.new(short: nil, long: "--no-error-overlay", description: "Disable error overlay in browser"),
          FlagInfo.new(short: nil, long: "--live-reload", description: "Enable live reload on file changes (default: enabled)"),
          FlagInfo.new(short: nil, long: "--no-live-reload", description: "Disable live reload on file changes"),
          FlagInfo.new(short: nil, long: "--header", description: "Add custom response header (repeatable, e.g. --header 'X-Frame-Options: SAMEORIGIN')", takes_value: true, value_hint: "NAME: VALUE"),

          # Fast iteration helpers (very common for local development)
          SKIP_OG_IMAGE_FLAG,
          SKIP_IMAGE_PROCESSING_FLAG,
          SKIP_CACHE_BUSTING_FLAG,
          FlagInfo.new(short: nil, long: "--fast", description: "Fast dev mode: equivalent to --skip-og-image --skip-image-processing (great with -q)"),

          # Debug & output
          VERBOSE_FLAG,
          QUIET_FLAG,
          PROFILE_FLAG,
          DEBUG_FLAG,
          JSON_FLAG,
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

          # --json suppresses banners/action lines so the ready event is the
          # first line on stdout. Errors still go to stderr via Logger.error.
          Runner.enable_json_mode! if options.json

          if input_dir
            unless Dir.exists?(input_dir)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Input directory does not exist: #{input_dir}",
                hint: "Check the path passed to -i/--input.",
              )
            end
            Logger.info "Changing working directory to: #{input_dir}"
            Dir.cd(input_dir)
          end

          # Enrich CLI headers with [serve.headers] from config.toml (now in the correct
          # directory after any -i/--input chdir). CLI values win on duplicate keys.
          # This must happen after Dir.cd so `hwaro serve -i /other/project` reads the
          # right config. We deliberately do not load config earlier in parse_options.
          begin
            cfg = Models::Config.load(env: options.env)

            # Merge headers (CLI wins)
            final = cfg.serve.headers.dup
            options.headers.each { |k, v| final[k] = v }
            options.headers = final

            # Apply [serve.fast] default, but let explicit CLI skip flags win.
            # If user passed --fast on CLI, those skips are already true.
            if cfg.serve.fast
              options.skip_og_image ||= true
              options.skip_image_processing ||= true
            end
          rescue Hwaro::HwaroError
            # Missing/invalid config — proceed with CLI-provided values only.
          end

          Services::Server.new.run(options)
        end

        private def parse_options(args : Array(String)) : {String?, Config::Options::ServeOptions}
          # Path & URL
          input_dir = nil.as(String?)
          base_url = nil.as(String?)
          env_name = ENV["HWARO_ENV"]? || nil

          # Content filtering
          drafts = false
          include_expired = false
          include_future = false

          # Build behavior
          minify = false
          workers = 0
          cache = false
          stream = false
          memory_limit = ENV["HWARO_MEMORYLIMIT"]? || nil
          fast_start = false
          fast_start_count = 20

          # Server
          host = "127.0.0.1"
          port = 3000
          open_browser = false
          access_log = false
          error_overlay = true
          live_reload = true

          # CLI-provided headers only. Config [serve.headers] is merged later in #run
          # (after any -i chdir) so that `hwaro serve -i other/dir` works correctly.
          headers = {} of String => String

          # Skip options
          skip_og_image = false
          skip_image_processing = false
          cache_busting = true

          # Debug & output
          verbose = false
          profile = false
          debug = false
          json_output = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro serve [options]"

            # Path & URL
            CLI.register_flag(parser, INPUT_DIR_FLAG) { |v| input_dir = v }
            CLI.register_base_url(parser) { |v| base_url = v }
            CLI.register_flag(parser, ENV_FLAG) { |v| env_name = v }

            # Content filtering
            CLI.register_flag(parser, DRAFTS_FLAG) { |_| drafts = true }
            CLI.register_flag(parser, INCLUDE_EXPIRED_FLAG) { |_| include_expired = true }
            CLI.register_flag(parser, INCLUDE_FUTURE_FLAG) { |_| include_future = true }

            # Build behavior
            CLI.register_flag(parser, MINIFY_FLAG) { |_| minify = true }
            CLI.register_jobs(parser) { |n| workers = n }
            parser.on("--cache", "Enable build caching (skip unchanged files)") { cache = true }
            parser.on("--stream", "Enable streaming build to reduce memory usage") { stream = true }
            parser.on("--memory-limit SIZE", "Memory limit for streaming build (e.g. 2G, 512M)") { |size| memory_limit = size }
            parser.on("--fast-start", "Render homepage + latest N pages first, then background-render the rest") { fast_start = true }
            parser.on("--fast-start-count N", "Number of recent pages to render up front with --fast-start (default: 20)") do |n|
              parsed = n.to_i?
              if parsed.nil? || parsed < 1
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: "Invalid --fast-start-count value: #{n}",
                  hint: "Pass a positive integer, e.g. --fast-start-count 50.",
                )
              end
              fast_start_count = parsed
              fast_start = true
            end

            # Server
            parser.on("-b HOST", "--bind HOST", "Bind address (default: 127.0.0.1)") { |h| host = h }
            parser.on("-p PORT", "--port PORT", "Port to listen on (default: 3000)") do |p|
              parsed = p.to_i?
              if parsed.nil? || parsed < 1 || parsed > 65535
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: "Invalid --port value: #{p}",
                  hint: "Pass a port between 1 and 65535, e.g. -p 3000.",
                )
              end
              port = parsed
            end
            CLI.register_flag(parser, OPEN_BROWSER_FLAG) { |_| open_browser = true }
            CLI.register_flag(parser, NO_OPEN_BROWSER_FLAG) { |_| open_browser = false }
            parser.on("--access-log", "Show HTTP access log (e.g. GET requests)") { access_log = true }
            parser.on("--no-error-overlay", "Disable error overlay in browser") { error_overlay = false }
            parser.on("--live-reload", "Enable live reload on file changes (default: enabled; kept for backwards compatibility)") { live_reload = true }
            parser.on("--no-live-reload", "Disable live reload on file changes") { live_reload = false }
            parser.on("--header NAME:VALUE", "Add custom response header (repeatable)") do |h|
              key, value = parse_header(h)
              headers[key] = value
            end

            # Skip options
            CLI.register_flag(parser, SKIP_OG_IMAGE_FLAG) { |_| skip_og_image = true }
            CLI.register_flag(parser, SKIP_IMAGE_PROCESSING_FLAG) { |_| skip_image_processing = true }
            CLI.register_flag(parser, SKIP_CACHE_BUSTING_FLAG) { |_| cache_busting = false }
            parser.on("--fast", "Fast dev mode: skip heavy processing (OG images + image resizing)") do
              skip_og_image = true
              skip_image_processing = true
            end

            # Debug & output
            CLI.register_flag(parser, VERBOSE_FLAG) { |_| verbose = true }
            CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
            CLI.register_flag(parser, PROFILE_FLAG) { |_| profile = true }
            CLI.register_flag(parser, DEBUG_FLAG) { |_| debug = true }
            CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
            CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
          end

          {input_dir, Config::Options::ServeOptions.new(
            host: host,
            port: port,
            base_url: base_url,
            drafts: drafts,
            include_expired: include_expired,
            include_future: include_future,
            minify: minify,
            workers: workers,
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
            cache: cache,
            stream: stream,
            memory_limit: memory_limit,
            json: json_output,
            fast_start: fast_start,
            fast_start_count: fast_start_count,
            headers: headers,
          )}
        end

        # Parse "Name: Value" or "Name=Value" or "Name Value" into {name, value}.
        # Header names are case-insensitive per HTTP spec; we preserve the
        # casing the user gave us (common convention is Title-Case).
        private def parse_header(raw : String) : {String, String}
          s = raw.strip
          # Try "key: value", "key = value", "key value"
          if s.includes?(":")
            key, value = s.split(":", 2)
          elsif s.includes?("=")
            key, value = s.split("=", 2)
          elsif s =~ /\s/
            # Only treat as "key value" if there actually is whitespace.
            parts = s.split(/\s+/, 2)
            key = parts[0]? || ""
            value = parts[1]? || ""
          else
            # Bare token with no separator at all (e.g. --header "Foo").
            # This used to cause an IndexError on parallel assignment before the
            # safe split. Now we give the user the same friendly error as other
            # malformed inputs (addresses Copilot review feedback on #556).
            key = ""
            value = ""
          end
          key = key.strip
          value = value.strip

          if key.empty?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Invalid --header value: #{raw.inspect}",
              hint: "Use the form --header 'X-Foo: bar' or --header 'X-Foo=bar'.",
            )
          end

          # Prevent HTTP response splitting / header injection attacks.
          # Control characters (especially CR/LF) in names or values are dangerous.
          if key.each_char.any? { |c| c.ascii_control? || c == ':' } || value.each_char.any?(&.ascii_control?)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Invalid characters in --header: #{raw.inspect}",
              hint: "Header names and values must not contain control characters, newlines, or colons in the name.",
            )
          end

          {key, value}
        end
      end
    end
  end
end
