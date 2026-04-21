require "option_parser"
require "../../metadata"
require "../../../utils/logger"
require "../../../services/ci_config"

module Hwaro
  module CLI
    module Commands
      module Tool
        class CICommand
          # Single source of truth for command metadata
          NAME               = "ci"
          DESCRIPTION        = "Generate CI/CD workflow files"
          POSITIONAL_ARGS    = ["provider"]
          POSITIONAL_CHOICES = Services::CIConfig::SUPPORTED_PROVIDERS

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
            Logger.warn "DEPRECATED: 'tool ci' is deprecated. Use 'tool platform github-pages' instead."
            Logger.warn ""
            provider : String? = nil
            output_file : String? = nil
            stdout_mode = false
            force = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool ci <github-actions> [options]"
              parser.on("-o PATH", "--output PATH", "Output file path (default: auto-detected)") { |p| output_file = p }
              parser.on("--stdout", "Print to stdout instead of writing file") { stdout_mode = true }
              parser.on("-f", "--force", "Overwrite existing file without warning") { force = true }
              CLI.register_flag(parser, HELP_FLAG) do |_|
                Logger.info parser.to_s
                Logger.info ""
                Logger.info "Supported providers:"
                Services::CIConfig::SUPPORTED_PROVIDERS.each do |p|
                  Logger.info "  #{p}"
                end
                exit
              end
              parser.unknown_args do |unknown|
                provider = unknown.first? if unknown.present?
              end
            end

            unless provider_name = provider
              Logger.error "CI provider name required. Use: github-actions"
              exit(1)
            end

            unless Services::CIConfig::SUPPORTED_PROVIDERS.includes?(provider_name)
              Logger.error "Unsupported CI provider: #{provider_name}"
              Logger.info "Supported providers: #{Services::CIConfig::SUPPORTED_PROVIDERS.join(", ")}"
              exit(1)
            end

            generator = Services::CIConfig.new
            content = generator.generate(provider_name)
            filename = if of = output_file
                         of
                       else
                         generator.output_path(provider_name)
                       end

            if stdout_mode
              puts content
            else
              if File.exists?(filename) && !force
                Logger.warn "#{filename} already exists. Use --force to overwrite."
                exit(1)
              end

              dir = File.dirname(filename)
              FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
              File.write(filename, content)
              Logger.success "Generated #{filename}"
            end
          end
        end
      end
    end
  end
end
