# Validate command for checking content file quality
#
# This command validates content files for frontmatter completeness,
# accessibility, and structural correctness.
# Usage:
#   hwaro tool validate [options]

require "json"
require "option_parser"
require "toml"
require "../../metadata"
require "../../../services/content_validator"
require "../../../content/front_matter_schema"
require "../../../utils/errors"
require "../../../utils/logger"
require "../../../utils/text_utils"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ValidateCommand
          NAME               = "validate"
          DESCRIPTION        = "Validate content frontmatter and markup"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          STRICT_FLAG       = FlagInfo.new(short: nil, long: "--strict", description: "Treat warnings as errors when computing the exit code")
          MAX_WARNINGS_FLAG = FlagInfo.new(short: nil, long: "--max-warnings", description: "Exit non-zero when warning count exceeds N (default: unlimited)", takes_value: true, value_hint: "N")

          FLAGS = [
            CONTENT_DIR_FLAG,
            STRICT_FLAG,
            MAX_WARNINGS_FLAG,
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
            strict_mode = false
            max_warnings = -1 # < 0 means "unlimited"

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool validate [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, STRICT_FLAG) { |_| strict_mode = true }
              CLI.register_flag(parser, MAX_WARNINGS_FLAG) do |v|
                parsed = v.to_i?
                unless parsed && parsed >= 0
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: "Invalid --max-warnings value: #{v}",
                    hint: "Pass a non-negative integer, e.g. --max-warnings 0.",
                  )
                end
                max_warnings = parsed
              end
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |before_dash, after_dash|
                unknown = before_dash + after_dash
                raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: "unexpected extra argument(s): '#{unknown.join("', '")}'",
                  hint: "hwaro tool validate accepts options only.",
                ) unless unknown.empty?
              end
            end

            Runner.enable_json_mode! if json_output

            validator = Services::ContentValidator.new(content_dir: content_dir)
            schema_results = [] of {String, Content::FrontMatterSchema::Result}
            begin
              issues = validator.run
              # `[[content.schema]]`: the build's own check (see
              # Doctor.content_schema_results), so validate and build agree.
              if config = load_schema_config(content_dir)
                schema_results = Services::Doctor.content_schema_results(content_dir, config)
                schema_results.each do |_, result|
                  issues.concat(result.violations.map { |v| Services::Doctor.schema_issue(v) })
                end
              end
            rescue ex
              if json_output
                # Keep a classified failure's own code and hint instead of
                # re-labelling every one of them HWARO_E_CONTENT.
                err = ex.as?(Hwaro::HwaroError) || Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_CONTENT,
                  message: ex.message || "validate failed",
                )
                Runner.exit_with_error_payload(err)
              else
                raise ex
              end
            end

            if json_output
              findings = issues.map do |issue|
                {
                  "file"     => issue.file,
                  "line"     => issue.line,
                  "rule"     => issue.id,
                  "severity" => issue.level.to_s,
                  "message"  => issue.message,
                }
              end
              if schema_results.empty?
                puts({"findings" => findings}.to_json)
              else
                # The defaults each schema'd page takes for its missing fields.
                defaults = {} of String => Hash(String, Models::SchemaValue)
                schema_results.each { |file, result| defaults[file] = result.defaults unless result.defaults.empty? }
                puts({"findings" => findings, "defaults" => defaults}.to_json)
              end
              # Exit non-zero on hard errors so CI can gate on broken content
              # (mirrors `tool doctor`'s exit-code behavior).
              exit(exit_code_for(issues, strict: strict_mode, max_warnings: max_warnings))
            end

            Logger.heading("validate", content_dir)

            if Logger.quiet?
              # `Logger.item` is silenced by --quiet, which left a failing run
              # with exit 5 and no output at all. Errors and warnings still
              # reach stderr under --quiet: one line per finding.
              issues.each do |issue|
                line = "#{Utils::TextUtils.strip_control(issue.file || "(unknown)")}: " \
                       "#{Utils::TextUtils.strip_control(issue.message)}"
                case issue.level
                when :error   then Logger.error line
                when :warning then Logger.warn line
                end
              end
              code = exit_code_for(issues, strict: strict_mode, max_warnings: max_warnings)
              exit(code) if code != Hwaro::Errors::EXIT_SUCCESS
              return
            end

            if issues.empty?
              Logger.outcome("checked", "no issues found — content looks great")
              return
            end

            # TTY already gets its blank line from `heading`; keep the plain
            # form's historical blank so piped output stays byte-identical.
            Logger.info "" unless Logger.color_enabled?

            # Group by file: a dim file label, then one glyph item per issue.
            # Same severity glyphs as `tool doctor` so findings read the same
            # everywhere.
            by_file = issues.group_by(&.file)

            by_file.each do |file, file_issues|
              Logger.section(Utils::TextUtils.strip_control(file || "(unknown)"))
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
            code = exit_code_for(issues, strict: strict_mode, max_warnings: max_warnings)
            exit(code) if code != Hwaro::Errors::EXIT_SUCCESS
          end

          # The config of the project `content_dir` belongs to (the
          # `config.toml` beside it), loaded only when it declares
          # `[[content.schema]]`: validate is a content linter, so a config
          # problem unrelated to schemas stays `hwaro build`'s to report. A
          # declared but malformed schema still raises (HWARO_E_CONFIG). Load
          # warnings belong to `hwaro build` / `doctor`.
          private def load_schema_config(content_dir : String) : Models::Config?
            path = File.join(File.dirname(File.expand_path(content_dir)), "config.toml")
            declared = begin
              TOML.parse(File.read(path))["content"]?.try(&.as_h?).try(&.has_key?("schema"))
            rescue
              nil
            end
            return unless declared
            previous = Logger.level
            Logger.level = Logger::Level::Error
            begin
              Models::Config.load(path)
            ensure
              Logger.level = previous
            end
          end

          # Mirrors `tool doctor`'s exit policy: hard errors keep their
          # category exit code (`EXIT_CONTENT` — everything validate reports
          # is content), while warning-driven failures (`--strict`,
          # `--max-warnings`) exit `EXIT_GENERIC` so a consumer can still
          # tell a broken file from a tightened gate.
          private def exit_code_for(issues : Array(Services::Issue), strict : Bool, max_warnings : Int32) : Int32
            errors = issues.count { |i| i.level == :error }
            warnings = issues.count { |i| i.level == :warning }
            return Hwaro::Errors::EXIT_CONTENT if errors > 0
            return Hwaro::Errors::EXIT_GENERIC if strict && warnings > 0
            return Hwaro::Errors::EXIT_GENERIC if max_warnings >= 0 && warnings > max_warnings
            Hwaro::Errors::EXIT_SUCCESS
          end

          # Issue messages quote author-controlled text (tags, link targets,
          # image markup), so escapes are stripped HERE — at the render layer —
          # and never in the model. `--json` above must emit the author's
          # bytes verbatim, or a consumer cannot locate the tag it is being
          # told about.
          private def print_issue(issue : Services::Issue)
            glyph = case issue.level
                    when :error   then :err
                    when :warning then :warn
                    else               :info
                    end
            Logger.item(Utils::TextUtils.strip_control(issue.message), glyph: glyph, indent: 4)
          end
        end
      end
    end
  end
end
