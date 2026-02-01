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
  end
end
