require "json"
require "colorize"
require "option_parser"
require "../../metadata"
require "../../../utils/errors"
require "../../../utils/logger"
require "../../../services/doctor"

module Hwaro
  module CLI
    module Commands
      module Tool
        class DoctorCommand
          # Single source of truth for command metadata
          NAME               = "doctor"
          DESCRIPTION        = "Diagnose config, template, and structure issues"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          # Schema version for `--json` output. Bump when adding fields
          # that machine consumers may rely on.
          JSON_SCHEMA_VERSION = 1

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            CONTENT_DIR_FLAG,
            FlagInfo.new(short: nil, long: "--fix", description: "Auto-fix issues (add missing sections, normalize safe values)"),
            FlagInfo.new(short: nil, long: "--minimal", description: "With --fix, skip advanced optional sections (pwa, amp, assets, etc.)"),
            FlagInfo.new(short: nil, long: "--dry-run", description: "With --fix, preview changes without writing config.toml"),
            FlagInfo.new(short: nil, long: "--strict", description: "Treat warnings as errors when computing the exit code"),
            FlagInfo.new(short: nil, long: "--max-warnings=N", description: "Exit non-zero when warning count exceeds N (default: unlimited)"),
            JSON_FLAG,
            QUIET_FLAG,
            HELP_FLAG,
          ]

          # Inline check groups now live on the Doctor service so this
          # command renders whatever the service declares — adding a new
          # diagnostic only touches one file. See
          # `Services::CHECK_GROUPS`.

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
            config_path = "config.toml"
            json_output = false
            fix_mode = false
            minimal_mode = false
            dry_run_mode = false
            strict_mode = false
            max_warnings = -1 # < 0 means "unlimited"

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro doctor [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              parser.on("--fix", "Auto-fix issues (add missing sections, normalize safe values)") { fix_mode = true }
              parser.on("--minimal", "With --fix, skip advanced optional sections (pwa, amp, assets, etc.)") { minimal_mode = true }
              parser.on("--dry-run", "With --fix, preview changes without writing config.toml") { dry_run_mode = true }
              parser.on("--strict", "Treat warnings as errors when computing the exit code") { strict_mode = true }
              parser.on("--max-warnings=N", "Exit non-zero when warning count exceeds N") do |v|
                parsed = v.to_i?
                unless parsed && parsed >= 0
                  Logger.error "--max-warnings expects a non-negative integer (got: #{v.inspect})"
                  exit(Hwaro::Errors::EXIT_GENERIC)
                end
                max_warnings = parsed
              end
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            end

            doctor = Services::Doctor.new(content_dir: content_dir, config_path: config_path)

            if minimal_mode && !fix_mode
              Logger.warn "--minimal has no effect without --fix"
            end

            if dry_run_mode && !fix_mode
              Logger.warn "--dry-run has no effect without --fix"
            end

            if fix_mode
              run_fix(doctor, minimal_mode, dry_run_mode, json_output)
              return
            end

            issues = doctor.run
            code = exit_code_for(issues, strict: strict_mode, max_warnings: max_warnings)

            if json_output
              result = {
                "schema_version" => JSON_SCHEMA_VERSION,
                "issues"         => issues,
                "summary"        => {
                  "errors"   => issues.count { |i| i.level == :error },
                  "warnings" => issues.count { |i| i.level == :warning },
                  "infos"    => issues.count { |i| i.level == :info },
                  "total"    => issues.size,
                },
                "exit_code" => code,
              }
              puts result.to_json
              exit(code)
            end

            if Logger.quiet?
              render_quiet(issues, code)
            else
              render_human(issues, config_path)
            end
            exit(code)
          end

          # Map any `:error`-level issues to an appropriate exit code so
          # CI pipelines can gate on `hwaro doctor` directly. Warnings
          # don't change the exit code by default — only real errors do.
          # `strict` promotes any warning to an error for exit-code
          # purposes; `max_warnings` triggers a generic failure when the
          # warning count exceeds the threshold (negative = unlimited).
          # Picks the highest-numeric exit across reported errors so
          # mixed categories surface the most severe failure class
          # (mirrors `deploy_command.cr#worst_exit_for`).
          private def exit_code_for(issues : Array(Services::Issue), strict : Bool = false, max_warnings : Int32 = -1) : Int32
            worst = Hwaro::Errors::EXIT_SUCCESS
            warnings = 0
            issues.each do |issue|
              warnings += 1 if issue.level == :warning
              next unless issue.level == :error
              code = exit_code_for_category(issue.category)
              worst = code if code > worst
            end
            return worst unless worst == Hwaro::Errors::EXIT_SUCCESS
            return Hwaro::Errors::EXIT_GENERIC if strict && warnings > 0
            return Hwaro::Errors::EXIT_GENERIC if max_warnings >= 0 && warnings > max_warnings
            Hwaro::Errors::EXIT_SUCCESS
          end

          private def exit_code_for_category(category : String) : Int32
            case category
            when "config", "config_missing"
              Hwaro::Errors::EXIT_CONFIG
            when "template"
              Hwaro::Errors::EXIT_TEMPLATE
            when "content"
              Hwaro::Errors::EXIT_CONTENT
            else
              Hwaro::Errors::EXIT_GENERIC
            end
          end

          # Terse rendering for `--quiet`. The previous behaviour (rely
          # on `Logger.quiet = true` to silence `.info`) blackholed the
          # full error summary too, so a CI run that failed produced no
          # output and the user had to re-run without `--quiet` to see
          # what was wrong. Now `--quiet` skips the inline check headers
          # and prints one line per non-info issue, exit-code only on
          # success.
          private def render_quiet(issues : Array(Services::Issue), exit_code : Int32)
            # Logger.quiet silences `Logger.info`, but a CI run that fails
            # still needs *something* on stdout. Use direct STDOUT.puts so
            # the output bypasses the Logger gate and surfaces the
            # actionable issues only — no inline check headers, no banner.
            issues.each do |issue|
              next if issue.level == :info
              file_part = issue.file ? "#{issue.file}: " : ""
              STDOUT.puts "[#{issue.level}] #{file_part}#{issue.message}"
            end
          end

          # Render human-readable diagnostics with inline status glyphs per check.
          private def render_human(issues : Array(Services::Issue), config_path : String)
            plain = plain_output?

            Logger.info "Running diagnostics..."
            Logger.info ""
            Services::CHECK_GROUPS.each do |group|
              heading = group.key == :config ? config_path : group.default_heading
              Logger.info "  #{heading}"
              group.checks.each do |spec|
                Logger.info "    #{render_check_line(spec, issues, plain)}"
              end
              Logger.info ""
            end

            if issues.empty?
              Logger.info "#{ok_glyph(plain)} No issues found. Your site looks great!"
              return
            end

            # Group by category for detail lines.
            config_issues = issues.select { |i| i.category == "config" }
            config_missing = issues.select { |i| i.category == "config_missing" }
            template_issues = issues.select { |i| i.category == "template" }
            content_issues = issues.select { |i| i.category == "content" }
            structure_issues = issues.select { |i| i.category == "structure" }

            unless config_issues.empty?
              Logger.info "Config:"
              config_issues.each { |issue| print_issue(issue, plain) }
              Logger.info ""
            end

            unless config_missing.empty?
              Logger.info "Missing Config Sections (run 'hwaro doctor --fix' to add):"
              config_missing.each { |issue| print_issue(issue, plain) }
              Logger.info ""
            end

            unless template_issues.empty?
              Logger.info "Templates:"
              template_issues.each { |issue| print_issue(issue, plain) }
              Logger.info ""
            end

            unless content_issues.empty?
              Logger.info "Content:"
              content_issues.each { |issue| print_issue(issue, plain) }
              Logger.info ""
            end

            unless structure_issues.empty?
              Logger.info "Structure:"
              structure_issues.each { |issue| print_issue(issue, plain) }
              Logger.info ""
            end

            # Summary
            errors = issues.count { |i| i.level == :error }
            warnings = issues.count { |i| i.level == :warning }
            infos = issues.count { |i| i.level == :info }

            Logger.info "Found #{errors} error(s), #{warnings} warning(s), #{infos} info(s)"
            Logger.info ""
            Logger.info "Tip: Use 'hwaro tool validate' for content checks"
          end

          # Format a single named check line with an inline status glyph.
          private def render_check_line(spec : Services::CheckSpec, issues : Array(Services::Issue), plain : Bool) : String
            matched = issues.select { |i| spec.issue_ids.includes?(i.id) }
            level = worst_level(matched)
            "#{status_glyph(level, plain)} #{spec.label}"
          end

          # Collapse matched issues to the most severe level.
          # Returns nil when nothing matched → check passed.
          private def worst_level(matched : Array(Services::Issue)) : Symbol?
            return if matched.empty?
            return :error if matched.any? { |i| i.level == :error }
            return :warning if matched.any? { |i| i.level == :warning }
            return :info if matched.any? { |i| i.level == :info }
            nil
          end

          # Returns true when we should suppress color + Unicode glyphs
          # Delegates to `Logger.color_enabled?` so NO_COLOR / non-TTY / explicit
          # overrides are all honored consistently across the CLI.
          private def plain_output? : Bool
            !Logger.color_enabled?
          end

          private def status_glyph(level : Symbol?, plain : Bool) : String
            if plain
              case level
              when :error   then "[err] "
              when :warning then "[warn]"
              when :info    then "[info]"
              else               "[ok]  "
              end
            else
              case level
              when :error   then "✗".colorize(:red).to_s
              when :warning then "⚠".colorize(:yellow).to_s
              when :info    then "ℹ".colorize(:cyan).to_s
              else               "✓".colorize(:green).to_s
              end
            end
          end

          private def ok_glyph(plain : Bool) : String
            plain ? "[ok]" : "✓".colorize(:green).to_s
          end

          private def run_fix(doctor : Services::Doctor, minimal : Bool, dry_run : Bool, json_output : Bool)
            summary = doctor.fix_config(minimal: minimal, dry_run: dry_run)

            if json_output
              puts summary.to_json
              return
            end

            plain = plain_output?

            if summary.empty?
              Logger.info "#{ok_glyph(plain)} Config is up to date — no fixable issues."
              return
            end

            verb_added = dry_run ? "Would add" : "Added"
            verb_updated = dry_run ? "Would update" : "Updated"

            unless summary.value_fixes.empty?
              Logger.success "#{verb_updated} #{summary.value_fixes.size} value(s) in config.toml:"
              summary.value_fixes.each do |fix|
                arrow = plain ? "->" : "→".colorize(:green).to_s
                Logger.info "  #{fix.field}: #{fix.before} #{arrow} #{fix.after}"
              end
              Logger.info ""
            end

            unless summary.sections_added.empty?
              Logger.success "#{verb_added} #{summary.sections_added.size} missing config section(s) to config.toml:"
              plus = plain ? "+" : "＋".colorize(:green).to_s
              summary.sections_added.each do |key|
                Logger.info "  #{plus} [#{key}]"
              end
              Logger.info ""
              Logger.info "All new sections are commented out by default."
              Logger.info "Edit config.toml to enable the features you need."
            end

            if dry_run
              Logger.info ""
              Logger.info "Dry run — no changes were written. Re-run without --dry-run to apply."
            end
          end

          private def print_issue(issue : Services::Issue, plain : Bool = plain_output?)
            icon = status_glyph(issue.level, plain)
            file_part = issue.file ? " #{issue.file}:" : ""
            Logger.info "  #{icon}#{file_part} #{issue.message}"
          end
        end
      end
    end
  end
end
