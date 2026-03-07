require "option_parser"
require "../metadata"
require "../../config/options/build_options"
require "../../core/build/builder"
require "../../content/hooks"
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
          FlagInfo.new(short: "-i", long: "--input", description: "Project directory to build (default: current directory)", takes_value: true, value_hint: "DIR"),
          FlagInfo.new(short: "-o", long: "--output-dir", description: "Output directory (default: public)", takes_value: true, value_hint: "DIR"),
          FlagInfo.new(short: nil, long: "--base-url", description: "Override base_url from config.toml", takes_value: true, value_hint: "URL"),
          FlagInfo.new(short: "-d", long: "--drafts", description: "Include draft content"),
          FlagInfo.new(short: nil, long: "--minify", description: "Minify HTML output (and minified json, xml)"),
          FlagInfo.new(short: nil, long: "--no-parallel", description: "Disable parallel file processing"),
          FlagInfo.new(short: nil, long: "--cache", description: "Enable build caching (skip unchanged files)"),
          FlagInfo.new(short: nil, long: "--skip-highlighting", description: "Disable syntax highlighting"),
          FlagInfo.new(short: "-v", long: "--verbose", description: "Show detailed output including generated files"),
          FlagInfo.new(short: nil, long: "--profile", description: "Show build timing profile for each phase"),
          FlagInfo.new(short: nil, long: "--debug", description: "Print debug information after build"),
          FlagInfo.new(short: nil, long: "--skip-cache-busting", description: "Disable cache busting query parameters on CSS/JS resources"),
          FlagInfo.new(short: nil, long: "--stream", description: "Enable streaming build to reduce memory usage"),
          FlagInfo.new(short: nil, long: "--memory-limit", description: "Memory limit for streaming build (e.g. 2G, 512M)", takes_value: true, value_hint: "SIZE"),
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
          result, input_dir = parse_options(args)
          options, output_dir_explicit = result

          if dir = input_dir
            unless Dir.exists?(dir)
              Logger.error "Input directory does not exist: #{dir}"
              exit(1)
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

          builder.run(options)
        end

        def parse_options(args : Array(String)) : { {Config::Options::BuildOptions, Bool}, String? }
          input_dir = nil.as(String?)
          output_dir = "public"
          output_dir_explicit = false
          base_url = nil.as(String?)
          drafts = false
          minify = false
          parallel = true
          cache = false
          highlight = true
          verbose = false
          profile = false
          debug = false
          cache_busting = true
          stream = false
          memory_limit = ENV["HWARO_MEMORYLIMIT"]? || nil

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro build [options]"
            parser.on("-i DIR", "--input DIR", "Project directory to build (default: current directory)") { |dir| input_dir = dir }
            parser.on("-o DIR", "--output-dir DIR", "Output directory (default: public)") { |dir| output_dir = dir; output_dir_explicit = true }
            parser.on("--base-url URL", "Override base_url from config.toml") { |url| base_url = url }
            parser.on("-d", "--drafts", "Include draft content") { drafts = true }
            parser.on("--minify", "Minify HTML output (and minified json, xml)") { minify = true }
            parser.on("--no-parallel", "Disable parallel file processing") { parallel = false }
            parser.on("--cache", "Enable build caching (skip unchanged files)") { cache = true }
            parser.on("--skip-highlighting", "Disable syntax highlighting") { highlight = false }
            parser.on("-v", "--verbose", "Show detailed output including generated files") { verbose = true }
            parser.on("--profile", "Show build timing profile for each phase") { profile = true }
            parser.on("--debug", "Print debug information after build") { debug = true }
            parser.on("--skip-cache-busting", "Disable cache busting query parameters on CSS/JS resources") { cache_busting = false }
            parser.on("--stream", "Enable streaming build to reduce memory usage") { stream = true }
            parser.on("--memory-limit SIZE", "Memory limit for streaming build (e.g. 2G, 512M)") { |size| memory_limit = size }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
          end

          { {Config::Options::BuildOptions.new(
            output_dir: output_dir,
            base_url: base_url,
            drafts: drafts,
            minify: minify,
            parallel: parallel,
            cache: cache,
            highlight: highlight,
            verbose: verbose,
            profile: profile,
            debug: debug,
            cache_busting: cache_busting,
            stream: stream,
            memory_limit: memory_limit
          ), output_dir_explicit}, input_dir }
        end
      end
    end
  end
end
