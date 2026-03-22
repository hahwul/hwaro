# CLI Metadata - Base structures for command metadata
#
# This module provides the base structures for CLI command metadata.
# Each command defines its own FLAGS constant which is used both for
# OptionParser and for completion generation.

module Hwaro
  module CLI
    # Flag information for CLI options
    # This is the single source of truth for flag metadata
    record FlagInfo,
      short : String?,
      long : String,
      description : String,
      takes_value : Bool = false,
      value_hint : String? = nil

    # Command information including subcommands and flags
    class CommandInfo
      property name : String
      property description : String
      property flags : Array(FlagInfo)
      property subcommands : Array(CommandInfo)
      property positional_args : Array(String)
      property positional_choices : Array(String)

      def initialize(
        @name : String,
        @description : String,
        @flags : Array(FlagInfo) = [] of FlagInfo,
        @subcommands : Array(CommandInfo) = [] of CommandInfo,
        @positional_args : Array(String) = [] of String,
        @positional_choices : Array(String) = [] of String,
      )
      end
    end

    # Common help flag used by all commands
    HELP_FLAG = FlagInfo.new(short: "-h", long: "--help", description: "Show this help")

    # Common JSON output flag
    JSON_FLAG = FlagInfo.new(short: "-j", long: "--json", description: "Output result as JSON")

    # Global flags - shared across multiple commands
    VERBOSE_FLAG               = FlagInfo.new(short: "-v", long: "--verbose", description: "Show detailed output")
    DEBUG_FLAG                 = FlagInfo.new(short: nil, long: "--debug", description: "Print debug information")
    ENV_FLAG                   = FlagInfo.new(short: "-e", long: "--env", description: "Environment name (loads config.<env>.toml override)", takes_value: true, value_hint: "ENV")
    PROFILE_FLAG               = FlagInfo.new(short: nil, long: "--profile", description: "Show build timing profile")
    DRAFTS_FLAG                = FlagInfo.new(short: "-d", long: "--drafts", description: "Include draft content")
    INCLUDE_EXPIRED_FLAG       = FlagInfo.new(short: nil, long: "--include-expired", description: "Include expired content")
    MINIFY_FLAG                = FlagInfo.new(short: nil, long: "--minify", description: "Minify HTML output (and minified json, xml)")
    BASE_URL_FLAG              = FlagInfo.new(short: nil, long: "--base-url", description: "Override base_url from config.toml", takes_value: true, value_hint: "URL")
    SKIP_CACHE_BUSTING_FLAG    = FlagInfo.new(short: nil, long: "--skip-cache-busting", description: "Disable cache busting query parameters on CSS/JS resources")
    SKIP_OG_IMAGE_FLAG         = FlagInfo.new(short: nil, long: "--skip-og-image", description: "Skip auto OG image generation")
    SKIP_IMAGE_PROCESSING_FLAG = FlagInfo.new(short: nil, long: "--skip-image-processing", description: "Skip image resizing and LQIP generation")
    INPUT_DIR_FLAG             = FlagInfo.new(short: "-i", long: "--input", description: "Input directory (default: current directory)", takes_value: true, value_hint: "DIR")
    CONTENT_DIR_FLAG           = FlagInfo.new(short: "-c", long: "--content-dir", description: "Content directory (default: content)", takes_value: true, value_hint: "DIR")

    # Register a FlagInfo on an OptionParser, eliminating manual duplication
    # between FLAGS metadata and OptionParser definitions.
    def self.register_flag(parser : OptionParser, flag : FlagInfo, &block : String ->)
      if flag.takes_value
        hint = flag.value_hint || "VALUE"
        if short = flag.short
          parser.on("#{short} #{hint}", "#{flag.long} #{hint}", flag.description) { |v| block.call(v) }
        else
          parser.on("#{flag.long} #{hint}", flag.description) { |v| block.call(v) }
        end
      else
        if short = flag.short
          parser.on(short, flag.long, flag.description) { block.call("") }
        else
          parser.on(flag.long, flag.description) { block.call("") }
        end
      end
    end
  end
end
