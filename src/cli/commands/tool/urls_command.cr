# URLs command: preview the URLs a build would publish
#
# Usage:
#   hwaro tool urls          - One URL per line, sorted
#   hwaro tool urls --json   - URLs with their kind and source file

require "json"
require "option_parser"
require "../../metadata"
require "../../../core/build/builder"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class UrlsCommand
          # Single source of truth for command metadata
          NAME               = "urls"
          DESCRIPTION        = "Preview the URLs a build would publish (no rendering, no output)"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            INPUT_DIR_FLAG,
            ENV_FLAG,
            DRAFTS_FLAG,
            INCLUDE_EXPIRED_FLAG,
            INCLUDE_FUTURE_FLAG,
            JSON_FLAG,
            QUIET_FLAG,
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
            options = Config::Options::BuildOptions.new
            input_dir : String? = nil
            json_output = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool urls [options]"
              CLI.register_flag(parser, INPUT_DIR_FLAG) { |v| input_dir = v }
              CLI.register_flag(parser, ENV_FLAG) { |v| options.env = v }
              CLI.register_flag(parser, DRAFTS_FLAG) { |_| options.drafts = true }
              CLI.register_flag(parser, INCLUDE_EXPIRED_FLAG) { |_| options.include_expired = true }
              CLI.register_flag(parser, INCLUDE_FUTURE_FLAG) { |_| options.include_future = true }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.result parser.to_s; exit }
              parser.unknown_args do |before_dash, after_dash|
                CLI.reject_unknown_flag!(before_dash)
                unknown = before_dash + after_dash
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: "unexpected extra argument(s): '#{unknown.join("', '")}'",
                  hint: "hwaro tool urls accepts options only.",
                ) unless unknown.empty?
              end
            end

            Runner.enable_json_mode! if json_output
            # The URL list is the only thing on stdout: the build phases'
            # info lines stay off it (warnings still reach stderr).
            Logger.quiet = true

            begin
              if dir = input_dir
                unless Dir.exists?(dir)
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_IO,
                    message: "Input directory does not exist: #{dir}",
                  )
                end
                Dir.cd(dir)
              end
              urls = Core::Build::Builder.new.plan_urls(options).sort_by!(&.url)
            rescue ex : Hwaro::HwaroError
              Runner.exit_with_error_payload(ex) if json_output
              raise ex
            end

            if json_output
              puts({
                "count" => urls.size,
                "urls"  => urls.map { |entry| {"url" => entry.url, "kind" => entry.kind, "source" => entry.source} },
              }.to_json)
            else
              urls.each { |entry| Logger.result entry.url }
            end
          end
        end
      end
    end
  end
end
