# CLI Metadata - Centralized command and flag definitions
#
# This module provides structured metadata for all CLI commands and their options.
# It is used by the completion command to generate shell completion scripts
# and can be used for help generation and documentation.

module Hwaro
  module CLI
    # Flag information for CLI options
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
        @positional_choices : Array(String) = [] of String
      )
      end
    end

    # Central metadata registry for all CLI commands
    module Metadata
      # Standard help flag used by all commands
      HELP_FLAG = FlagInfo.new(short: "-h", long: "--help", description: "Show this help")

      # Get all command metadata
      def self.commands : Array(CommandInfo)
        [
          init_command,
          build_command,
          serve_command,
          new_command,
          deploy_command,
          tool_command,
          completion_command,
        ]
      end

      # Get command by name
      def self.get(name : String) : CommandInfo?
        commands.find { |cmd| cmd.name == name }
      end

      # Get all command names
      def self.command_names : Array(String)
        commands.map(&.name) + ["version", "help"]
      end

      # Init command metadata
      def self.init_command : CommandInfo
        CommandInfo.new(
          name: "init",
          description: "Initialize a new project",
          positional_args: ["path"],
          flags: [
            FlagInfo.new(short: "-f", long: "--force", description: "Force creation even if directory is not empty"),
            FlagInfo.new(short: nil, long: "--scaffold", description: "Scaffold type: simple, blog, docs", takes_value: true, value_hint: "TYPE"),
            FlagInfo.new(short: nil, long: "--skip-agents-md", description: "Skip creating AGENTS.md file"),
            FlagInfo.new(short: nil, long: "--skip-sample-content", description: "Skip creating sample content files"),
            FlagInfo.new(short: nil, long: "--skip-taxonomies", description: "Skip taxonomies configuration and templates"),
            FlagInfo.new(short: nil, long: "--include-multilingual", description: "Enable multilingual support (e.g., en,ko)", takes_value: true, value_hint: "LANGS"),
            HELP_FLAG,
          ]
        )
      end

      # Build command metadata
      def self.build_command : CommandInfo
        CommandInfo.new(
          name: "build",
          description: "Build the project",
          flags: [
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
            HELP_FLAG,
          ]
        )
      end

      # Serve command metadata
      def self.serve_command : CommandInfo
        CommandInfo.new(
          name: "serve",
          description: "Serve the project and watch for changes",
          flags: [
            FlagInfo.new(short: "-b", long: "--bind", description: "Bind address (default: 0.0.0.0)", takes_value: true, value_hint: "HOST"),
            FlagInfo.new(short: "-p", long: "--port", description: "Port to listen on (default: 3000)", takes_value: true, value_hint: "PORT"),
            FlagInfo.new(short: nil, long: "--base-url", description: "Override base_url from config.toml", takes_value: true, value_hint: "URL"),
            FlagInfo.new(short: "-d", long: "--drafts", description: "Include draft content"),
            FlagInfo.new(short: nil, long: "--open", description: "Open browser after starting server"),
            FlagInfo.new(short: "-v", long: "--verbose", description: "Show detailed output including generated files"),
            FlagInfo.new(short: nil, long: "--debug", description: "Print debug information after build"),
            HELP_FLAG,
          ]
        )
      end

      # New command metadata
      def self.new_command : CommandInfo
        CommandInfo.new(
          name: "new",
          description: "Create a new content file",
          positional_args: ["path"],
          flags: [
            FlagInfo.new(short: "-t", long: "--title", description: "Content title", takes_value: true, value_hint: "TITLE"),
            HELP_FLAG,
          ]
        )
      end

      # Deploy command metadata
      def self.deploy_command : CommandInfo
        CommandInfo.new(
          name: "deploy",
          description: "Deploy the built site using config.toml",
          positional_args: ["target"],
          flags: [
            FlagInfo.new(short: "-s", long: "--source", description: "Source directory to deploy", takes_value: true, value_hint: "DIR"),
            FlagInfo.new(short: nil, long: "--dry-run", description: "Show planned changes without writing"),
            FlagInfo.new(short: nil, long: "--confirm", description: "Ask for confirmation before deploying"),
            FlagInfo.new(short: nil, long: "--force", description: "Force upload/copy (ignore file comparisons)"),
            FlagInfo.new(short: nil, long: "--max-deletes", description: "Maximum number of deletes", takes_value: true, value_hint: "N"),
            FlagInfo.new(short: nil, long: "--list-targets", description: "List configured deployment targets and exit"),
            HELP_FLAG,
          ]
        )
      end

      # Tool command metadata
      def self.tool_command : CommandInfo
        CommandInfo.new(
          name: "tool",
          description: "Utility tools (convert, etc.)",
          subcommands: [
            tool_convert_subcommand,
            tool_list_subcommand,
            tool_check_subcommand,
          ],
          flags: [HELP_FLAG]
        )
      end

      # Tool convert subcommand
      def self.tool_convert_subcommand : CommandInfo
        CommandInfo.new(
          name: "convert",
          description: "Convert frontmatter format (YAML <-> TOML)",
          positional_args: ["format"],
          positional_choices: ["toYAML", "toTOML"],
          flags: [
            FlagInfo.new(short: "-c", long: "--content-dir", description: "Content directory (default: content)", takes_value: true, value_hint: "DIR"),
            HELP_FLAG,
          ]
        )
      end

      # Tool list subcommand
      def self.tool_list_subcommand : CommandInfo
        CommandInfo.new(
          name: "list",
          description: "List content files (all, drafts, published)",
          positional_args: ["filter"],
          positional_choices: ["all", "drafts", "published"],
          flags: [
            FlagInfo.new(short: "-c", long: "--content-dir", description: "Content directory (default: content)", takes_value: true, value_hint: "DIR"),
            HELP_FLAG,
          ]
        )
      end

      # Tool check subcommand
      def self.tool_check_subcommand : CommandInfo
        CommandInfo.new(
          name: "check",
          description: "Check for dead links in content files",
          flags: [HELP_FLAG]
        )
      end

      # Completion command metadata
      def self.completion_command : CommandInfo
        CommandInfo.new(
          name: "completion",
          description: "Generate shell completion scripts",
          positional_args: ["shell"],
          positional_choices: ["bash", "zsh", "fish"],
          flags: [HELP_FLAG]
        )
      end
    end
  end
end
