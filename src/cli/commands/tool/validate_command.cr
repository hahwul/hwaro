# Validate command for checking content file quality
#
# This command validates content files for frontmatter completeness,
# accessibility, and structural correctness.
# Usage:
#   hwaro tool validate [options]

require "json"
require "colorize"
require "option_parser"
require "../../metadata"
require "../../../services/content_validator"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ValidateCommand
          NAME               = "validate"
          DESCRIPTION        = "Validate content frontmatter and markup"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          FLAGS = [
            CONTENT_DIR_FLAG,
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
            content_dir = "content"
            json_output = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool validate [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            end

            Logger.quiet = true if json_output
            Runner.json_mode = true if json_output

            validator = Services::ContentValidator.new(content_dir: content_dir)
            begin
              issues = validator.run
            rescue ex
              if json_output
                err = Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_CONTENT,
                  message: ex.message || "validate failed",
                )
                puts err.to_error_payload.to_json
                exit(err.exit_code)
              else
                raise ex
              end
            end

            if json_output
              findings = issues.map do |issue|
                {
                  "file"     => issue.file,
                  "line"     => nil.as(Int32?),
                  "rule"     => issue.id,
                  "severity" => issue.level.to_s,
                  "message"  => issue.message,
                }
              end
              puts({"findings" => findings}.to_json)
              return
            end

            Logger.info "Validating content in '#{content_dir}'..."
            Logger.info ""

            if issues.empty?
              Logger.info "#{"✔".colorize(:green)} No issues found. Content looks great!"
              return
            end

            # Group by file
            by_file = issues.group_by(&.file)

            by_file.each do |file, file_issues|
              Logger.info "  #{file || "(unknown)"}:"
              file_issues.each { |issue| print_issue(issue) }
              Logger.info ""
            end

            # Summary
            errors = issues.count { |i| i.level == :error }
            warnings = issues.count { |i| i.level == :warning }
            infos = issues.count { |i| i.level == :info }

            Logger.info "Found #{errors} error(s), #{warnings} warning(s), #{infos} info(s)"
          end

          private def print_issue(issue : Services::Issue)
            icon = case issue.level
                   when :error   then "✘".colorize(:red)
                   when :warning then "⚠".colorize(:yellow)
                   when :info    then "ℹ".colorize(:cyan)
                   else               "?"
                   end

            Logger.info "    #{icon} #{issue.message}"
          end
        end
      end
    end
  end
end
