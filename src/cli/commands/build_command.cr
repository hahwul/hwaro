require "json"
require "option_parser"
require "../metadata"
require "../../config/options/build_options"
require "../../core/build/builder"
require "../../content/hooks"
require "../../utils/errors"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class BuildCommand
        # Single source of truth for command metadata
        NAME               = "build"
        DESCRIPTION        = "Build the project"
        POSITIONAL_ARGS    = [] of String
        POSITIONAL_CHOICES = [] of String

        # Flags defined here are used both for OptionParser and completion generation
        FLAGS = [
          # Path & URL
          INPUT_DIR_FLAG,
          FlagInfo.new(short: "-o", long: "--output", description: "Output directory (default: public)", takes_value: true, value_hint: "DIR"),
          BASE_URL_FLAG,
          ENV_FLAG,

          # Content filtering
          DRAFTS_FLAG,
          INCLUDE_EXPIRED_FLAG,
          INCLUDE_FUTURE_FLAG,

          # Build behavior
          MINIFY_FLAG,
          FlagInfo.new(short: nil, long: "--no-parallel", description: "Disable parallel file processing"),
          FlagInfo.new(short: nil, long: "--cache", description: "Enable build caching (skip unchanged files)"),
          FlagInfo.new(short: nil, long: "--full", description: "Force a complete rebuild (ignore cache)"),
          FlagInfo.new(short: nil, long: "--stream", description: "Enable streaming build to reduce memory usage"),
          FlagInfo.new(short: nil, long: "--memory-limit", description: "Memory limit for streaming build (e.g. 2G, 512M)", takes_value: true, value_hint: "SIZE"),

          # Skip options
          FlagInfo.new(short: nil, long: "--skip-highlighting", description: "Disable syntax highlighting"),
          SKIP_OG_IMAGE_FLAG,
          SKIP_IMAGE_PROCESSING_FLAG,
          SKIP_CACHE_BUSTING_FLAG,

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
          result, input_dir, json_output = parse_options(args)
          options, output_dir_explicit = result

          # --json implies quiet so only the final JSON document reaches stdout.
          Logger.quiet = true if json_output
          Runner.json_mode = true if json_output

          if dir = input_dir
            unless Dir.exists?(dir)
              err = Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Input directory does not exist: #{dir}",
              )
              if json_output
                puts err.to_error_payload.to_json
                exit(err.exit_code)
              end
              Logger.error "Error [#{err.code}]: #{err.message}"
              exit(err.exit_code)
            end

            # Only resolve output_dir to absolute path when -o was explicitly
            # specified, so it stays relative to the original CWD.
            # The default "public" should remain relative to the input directory.
            if output_dir_explicit && !Path[options.output_dir].absolute?
              options.output_dir = File.expand_path(options.output_dir)
            end

            Dir.cd(dir)
          end

          builder = Core::Build::Builder.new

          # Set logger level based on verbose option
          if options.verbose
            Logger.level = Logger::Level::Debug
          end

          # Register content hooks with lifecycle
          Content::Hooks.all.each do |hookable|
            builder.register(hookable)
          end

          start = Time.instant
          begin
            builder.run(options)
          rescue ex : Hwaro::HwaroError
            # Classified errors (config, template, content, …) are raised at
            # their source sites now, so we just forward the payload / rethrow.
            if json_output
              puts ex.to_error_payload.to_json
              exit(ex.exit_code)
            else
              raise ex
            end
          rescue ex
            # Unclassified failures keep the legacy `Error: <message>` text
            # form and exit 1. JSON mode still emits a minimal error envelope.
            if json_output
              puts({"status" => "error", "error" => {"message" => ex.message || "build failed"}}.to_json)
              exit(1)
            else
              raise ex
            end
          end

          if json_output
            ctx = builder.context
            stats = ctx.try(&.stats)
            duration_ms = if stats && stats.elapsed > 0
                            stats.elapsed.round(2)
                          else
                            (Time.instant - start).total_milliseconds.round(2)
                          end
            payload = {
              "status"              => "ok",
              "pages_generated"     => stats.try(&.pages_rendered) || 0,
              "duration_ms"         => duration_ms,
              "cache_hits"          => stats.try(&.cache_hits) || 0,
              "raw_files_processed" => stats.try(&.raw_files_processed) || 0,
            }
            puts payload.to_json
          end
        end

        def parse_options(args : Array(String)) : { {Config::Options::BuildOptions, Bool}, String?, Bool }
          # Path & URL
          input_dir = nil.as(String?)
          output_dir = "public"
          output_dir_explicit = false
          base_url = nil.as(String?)
          env_name = ENV["HWARO_ENV"]? || nil

          # Content filtering
          drafts = false
          include_expired = false
          include_future = false

          # Build behavior
          minify = false
          parallel = true
          cache = false
          full = false
          stream = false
          memory_limit = ENV["HWARO_MEMORYLIMIT"]? || nil

          # Skip options
          highlight = true
          skip_og_image = false
          skip_image_processing = false
          cache_busting = true

          # Debug & output
          verbose = false
          profile = false
          debug = false
          json_output = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro build [options]"

            # Path & URL
            CLI.register_flag(parser, INPUT_DIR_FLAG) { |v| input_dir = v }
            parser.on("-o DIR", "--output DIR", "Output directory (default: public)") { |dir| output_dir = dir; output_dir_explicit = true }
            CLI.register_flag(parser, BASE_URL_FLAG) do |v|
              begin
                Models::Config.validate_base_url!(v)
              rescue ex : ArgumentError
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: ex.message || "Invalid --base-url",
                  hint: "Examples: https://example.com, https://example.com/subpath, http://localhost:3000.",
                )
              end
              base_url = v
            end
            CLI.register_flag(parser, ENV_FLAG) { |v| env_name = v }

            # Content filtering
            CLI.register_flag(parser, DRAFTS_FLAG) { |_| drafts = true }
            CLI.register_flag(parser, INCLUDE_EXPIRED_FLAG) { |_| include_expired = true }
            CLI.register_flag(parser, INCLUDE_FUTURE_FLAG) { |_| include_future = true }

            # Build behavior
            CLI.register_flag(parser, MINIFY_FLAG) { |_| minify = true }
            parser.on("--no-parallel", "Disable parallel file processing") { parallel = false }
            parser.on("--cache", "Enable build caching (skip unchanged files)") { cache = true }
            parser.on("--full", "Force a complete rebuild (ignore cache)") { full = true }
            parser.on("--stream", "Enable streaming build to reduce memory usage") { stream = true }
            parser.on("--memory-limit SIZE", "Memory limit for streaming build (e.g. 2G, 512M)") { |size| memory_limit = size }

            # Skip options
            parser.on("--skip-highlighting", "Disable syntax highlighting") { highlight = false }
            CLI.register_flag(parser, SKIP_OG_IMAGE_FLAG) { |_| skip_og_image = true }
            CLI.register_flag(parser, SKIP_IMAGE_PROCESSING_FLAG) { |_| skip_image_processing = true }
            CLI.register_flag(parser, SKIP_CACHE_BUSTING_FLAG) { |_| cache_busting = false }

            # Debug & output
            CLI.register_flag(parser, VERBOSE_FLAG) { |_| verbose = true }
            # --quiet is stripped upstream in Runner.apply_global_quiet!; this
            # registration only ensures it appears in per-command --help.
            CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
            CLI.register_flag(parser, PROFILE_FLAG) { |_| profile = true }
            CLI.register_flag(parser, DEBUG_FLAG) { |_| debug = true }
            CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
            CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
          end

          { {Config::Options::BuildOptions.new(
            output_dir: output_dir,
            base_url: base_url,
            drafts: drafts,
            include_expired: include_expired,
            include_future: include_future,
            minify: minify,
            parallel: parallel,
            cache: cache,
            full: full,
            highlight: highlight,
            verbose: verbose,
            profile: profile,
            debug: debug,
            cache_busting: cache_busting,
            stream: stream,
            memory_limit: memory_limit,
            env: env_name,
            skip_og_image: skip_og_image,
            skip_image_processing: skip_image_processing,
          ), output_dir_explicit}, input_dir, json_output }
        end
      end
    end
  end
end
