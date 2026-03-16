require "option_parser"
require "../../metadata"
require "../../../utils/logger"
require "../../../services/platform_config"
require "../../../models/config"

module Hwaro
  module CLI
    module Commands
      module Tool
        class PlatformCommand
          # Single source of truth for command metadata
          NAME               = "platform"
          DESCRIPTION        = "Generate hosting platform config files"
          POSITIONAL_ARGS    = ["platform"]
          POSITIONAL_CHOICES = Services::PlatformConfig::SUPPORTED_PLATFORMS

          FLAGS = [
            FlagInfo.new(
              short: "-o",
              long: "--output",
              description: "Output file path (default: auto-detected)",
              takes_value: true,
              value_hint: "PATH"
            ),
            FlagInfo.new(
              short: nil,
              long: "--stdout",
              description: "Print to stdout instead of writing file"
            ),
            FlagInfo.new(
              short: "-f",
              long: "--force",
              description: "Overwrite existing file without warning"
            ),
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
            platform : String? = nil
            output_path : String? = nil
            stdout_mode = false
            force = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool platform <netlify|vercel|cloudflare> [options]"
              parser.on("-o PATH", "--output PATH", "Output file path (default: auto-detected)") { |p| output_path = p }
              parser.on("--stdout", "Print to stdout instead of writing file") { stdout_mode = true }
              parser.on("-f", "--force", "Overwrite existing file without warning") { force = true }
              parser.on("-h", "--help", "Show this help") do
                Logger.info parser.to_s
                Logger.info ""
                Logger.info "Supported platforms:"
                Services::PlatformConfig::SUPPORTED_PLATFORMS.each do |p|
                  Logger.info "  #{p}"
                end
                exit
              end
              parser.unknown_args do |unknown|
                platform = unknown.first? if unknown.any?
              end
            end

            unless platform
              Logger.error "Platform name required. Use: netlify, vercel, or cloudflare"
              exit(1)
            end

            platform_name = platform.not_nil!

            unless Services::PlatformConfig::SUPPORTED_PLATFORMS.includes?(platform_name)
              Logger.error "Unsupported platform: #{platform_name}"
              Logger.info "Supported platforms: #{Services::PlatformConfig::SUPPORTED_PLATFORMS.join(", ")}"
              exit(1)
            end

            unless File.exists?("config.toml")
              Logger.warn "config.toml not found. Running outside a Hwaro project directory?"
            end

            config = Models::Config.load
            generator = Services::PlatformConfig.new(config)
            content = generator.generate(platform_name)
            filename = (output_path || generator.output_filename(platform_name)).not_nil!

            if stdout_mode
              puts content
            else
              if File.exists?(filename) && !force
                Logger.warn "#{filename} already exists. Use --force to overwrite."
                exit(1)
              end

              File.write(filename, content)
              Logger.success "Generated #{filename}"
            end
          end
        end
      end
    end
  end
end
