require "file_utils"
require "option_parser"
require "../../metadata"
require "./file_generator"
require "../../../utils/command_suggester"
require "../../../utils/errors"
require "../../../utils/logger"
require "../../../utils/file_safe"
require "../../../services/platform_config"
require "../../../models/config"

module Hwaro
  module CLI
    module Commands
      module Tool
        class PlatformCommand
          # Single source of truth for command metadata
          NAME               = "platform"
          DESCRIPTION        = "Generate platform config and CI/CD workflow files"
          POSITIONAL_ARGS    = ["platform"]
          POSITIONAL_CHOICES = Services::PlatformConfig::SUPPORTED_PLATFORMS

          FLAGS = FileGenerator::FLAGS

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
            platform : String? = nil
            output_path : String? = nil
            stdout_mode = false
            force = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool platform <#{Services::PlatformConfig::SUPPORTED_PLATFORMS.join("|")}> [options]"
              parser.on("-o PATH", "--output PATH", "Output file path (default: auto-detected)") { |p| output_path = p }
              parser.on("--stdout", "Print to stdout instead of writing file") { stdout_mode = true }
              parser.on("-f", "--force", "Overwrite existing file without warning") { force = true }
              CLI.register_flag(parser, HELP_FLAG) do |_|
                Logger.info parser.to_s
                Logger.info ""
                Logger.info "Supported platforms:"
                Services::PlatformConfig::SUPPORTED_PLATFORMS.each do |p|
                  Logger.info "  #{p}"
                end
                exit
              end
              parser.unknown_args do |unknown|
                platform = unknown.first? if unknown.present?
              end
            end

            supported = Services::PlatformConfig::SUPPORTED_PLATFORMS.join(", ")

            # Classified usage errors (exit 2), like every sibling `tool`
            # subcommand. These two used to print an unclassified message and
            # exit 1 — the same status the "file already exists" refusal and a
            # genuine write failure use, so a caller could not tell a typo from
            # a real error.
            unless platform_name = platform
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <platform> argument",
                hint: "Usage: hwaro tool platform <platform> — supported: #{supported}.",
              )
            end

            unless Services::PlatformConfig::SUPPORTED_PLATFORMS.includes?(platform_name)
              if suggestion = Utils::CommandSuggester.suggest(platform_name, Services::PlatformConfig::SUPPORTED_PLATFORMS)
                STDERR.puts "Did you mean '#{suggestion}'?"
              end
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "unsupported platform: #{platform_name}",
                hint: "Supported: #{supported}.",
              )
            end

            config = if File.exists?("config.toml")
                       Models::Config.load
                     else
                       Logger.warn "config.toml not found. Running outside a Hwaro project directory?"
                       Models::Config.new
                     end
            generator = Services::PlatformConfig.new(config)
            content = generator.generate(platform_name)
            filename = if op = output_path
                         op
                       else
                         generator.output_filename(platform_name)
                       end

            FileGenerator.emit(filename, content, stdout_mode, force)
          end
        end
      end
    end
  end
end
