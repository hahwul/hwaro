require "option_parser"
require "../../metadata"
require "../../../utils/errors"
require "../../../utils/logger"
require "../../../utils/file_safe"
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
            # A blank spacer, not a second warning: `Logger.warn ""` rendered
            # as an empty, prefix-only `[WARN] ` line above the usage output.
            # On STDERR with the notice it spaces — `Logger.info` writes to
            # stdout, which `--stdout > deploy.yml` captures, and the file
            # then began with an empty line.
            STDERR.puts
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

            supported = Services::CIConfig::SUPPORTED_PROVIDERS.join(", ")

            unless provider_name = provider
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <provider> argument",
                hint: "Usage: hwaro tool ci <provider> — supported: #{supported}.",
              )
            end

            unless Services::CIConfig::SUPPORTED_PROVIDERS.includes?(provider_name)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "unsupported CI provider: #{provider_name}",
                hint: "Supported: #{supported}.",
              )
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
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_IO,
                  message: "#{filename} already exists",
                  hint: "Pass --force to overwrite it, -o PATH to write elsewhere, or --stdout to print it.",
                )
              end

              dir = File.dirname(filename)
              Hwaro::Utils::FileSafe.mkdir_p(dir) unless Dir.exists?(dir)
              File.write(filename, content)
              Logger.outcome("created", filename)
            end
          end
        end
      end
    end
  end
end
