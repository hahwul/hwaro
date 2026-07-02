# Validate command for checking content file quality
#
# This command validates content files for frontmatter completeness,
# accessibility, and structural correctness.
# Usage:
#   hwaro tool validate [options]

require "json"
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

            Runner.enable_json_mode! if json_output

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
              # Exit non-zero on hard errors so CI can gate on broken content
              # (mirrors `tool doctor`'s exit-code behavior).
              errors = issues.count { |i| i.level == :error }
              exit(errors > 0 ? Hwaro::Errors::EXIT_CONTENT : Hwaro::Errors::EXIT_SUCCESS)
            end

            Logger.heading("validate", content_dir)

            if issues.empty?
              Logger.outcome("checked", "no issues found — content looks great")
              return
            end

            Logger.info ""

            # Group by file: a dim file label, then one glyph item per issue.
            # Same severity glyphs as `tool doctor` so findings read the same
            # everywhere.
            by_file = issues.group_by(&.file)

            by_file.each do |file, file_issues|
              Logger.section(file || "(unknown)")
              file_issues.each { |issue| print_issue(issue) }
              Logger.info ""
            end

            # Summary — one severity-aware outcome line (mirrors `tool doctor`).
            errors = issues.count { |i| i.level == :error }
            warnings = issues.count { |i| i.level == :warning }
            infos = issues.count { |i| i.level == :info }

            worst = errors > 0 ? :err : (warnings > 0 ? :warn : :result)
            summary = "#{errors} #{errors == 1 ? "error" : "errors"} · " \
                      "#{warnings} #{warnings == 1 ? "warning" : "warnings"} · " \
                      "#{infos} info"
            Logger.outcome("checked", summary, worst)

            # Gate CI on hard errors (matches `tool doctor`).
            exit(Hwaro::Errors::EXIT_CONTENT) if errors > 0
          end

          private def print_issue(issue : Services::Issue)
            glyph = case issue.level
                    when :error   then :err
                    when :warning then :warn
                    else               :info
                    end
            Logger.item(issue.message, glyph: glyph, indent: 6)
          end
        end
      end
    end
  end
end
