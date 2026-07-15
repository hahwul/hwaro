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
            FlagInfo.new(short: nil, long: "--fix", description: "Perform real fixes (normalize values like base_url trailing slash, sitemap priority, etc.)"),
            FlagInfo.new(short: nil, long: "--approve", description: "Approve and add recommended optional config sections (use with --fix or alone)"),
            FlagInfo.new(short: nil, long: "--full", description: "Equivalent to --fix --approve (real fixes + all recommended sections)"),
            FlagInfo.new(short: nil, long: "--dry-run", description: "Preview changes without writing config.toml"),
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

          # `invocation` lets the top-level `hwaro doctor` alias and the
          # canonical `hwaro tool doctor` form each show their own usage
          # banner, even though both share this single implementation.
          def run(args : Array(String), invocation : String = "hwaro tool doctor")
            content_dir = "content"
            config_path = "config.toml"
            json_output = false
            fix_mode = false
            approve_mode = false
            full_mode = false
            dry_run_mode = false
            strict_mode = false
            max_warnings = -1 # < 0 means "unlimited"

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: #{invocation} [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              parser.on("--fix", "Perform real fixes (normalize values like base_url trailing slash, sitemap priority, etc.)") { fix_mode = true }
              parser.on("--approve", "Approve and add recommended optional config sections") { approve_mode = true }
              parser.on("--full", "Perform real fixes and approve all recommended sections (equivalent to --fix --approve)") { full_mode = true }
              parser.on("--dry-run", "Preview changes without writing config.toml") { dry_run_mode = true }
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

            if dry_run_mode && !fix_mode && !approve_mode && !full_mode
              Logger.warn "--dry-run has no effect without --fix, --approve, or --full"
            end

            if full_mode
              fix_mode = true
              approve_mode = true
            end

            if fix_mode || approve_mode
              # `--fix` gates value normalization, `--approve` gates section
              # appends — a bare `--approve` must not silently edit values.
              run_fix(doctor, fix_values: fix_mode, approve_sections: approve_mode, dry_run: dry_run_mode, json_output: json_output)
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

            # A missing/unparseable config aborts `check_config` before any of
            # the other config sub-checks (and `check_referenced_paths`) run.
            # Those checks must render as skipped — a green ✓ for a check that
            # never executed is reassuring noise on top of a broken config.
            config_blocked = issues.any? { |i| i.id == "config-not-found" || i.id == "config-parse-error" }

            Logger.heading("doctor")
            Logger.info ""
            Services::CHECK_GROUPS.each do |group|
              heading = group.key == :config ? config_path : group.default_heading
              Logger.info "  #{heading}"
              group.checks.each do |spec|
                skipped = config_blocked && group.key == :config && !spec.issue_ids.includes?("config-parse-error")
                Logger.info "    #{render_check_line(spec, issues, plain, skipped)}"
              end
              Logger.info ""
            end

            if issues.empty?
              Logger.outcome("checked", "no issues found — your site looks great")
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
              Logger.info "Missing Config Sections (run 'hwaro doctor --full' to add):"
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

            # Summary — one severity-aware outcome line: the lead glyph reflects
            # the worst level found (✗ error / ⚠ warning / ▴ clean).
            errors = issues.count { |i| i.level == :error }
            warnings = issues.count { |i| i.level == :warning }
            infos = issues.count { |i| i.level == :info }

            worst = errors > 0 ? :err : (warnings > 0 ? :warn : :result)
            summary = "#{errors} #{errors == 1 ? "error" : "errors"} · " \
                      "#{warnings} #{warnings == 1 ? "warning" : "warnings"} · " \
                      "#{infos} info"
            Logger.outcome("checked", summary, worst)
            Logger.info ""
            Logger.info "Tip: Use 'hwaro tool validate' for content checks"
          end

          # Format a single named check line with an inline status glyph.
          # `skipped` marks a check that never executed (e.g. the config
          # failed to parse before it could run) — rendered as a dim dash,
          # never as a passing ✓.
          private def render_check_line(spec : Services::CheckSpec, issues : Array(Services::Issue), plain : Bool, skipped : Bool = false) : String
            if skipped
              glyph = plain ? "[--]  " : Logger.paint("–", Logger::Role::Dim)
              label = plain ? "#{spec.label} (skipped)" : "#{spec.label} #{Logger.paint("(skipped)", Logger::Role::Dim)}"
              return "#{glyph} #{label}"
            end

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
              # Route through the shared ember palette. Same colors as before
              # except :info, which moves off the off-brand :cyan to a recessive
              # dim role. truecolor terminals get the warm 24-bit tier for free.
              case level
              when :error   then Logger.paint("✗", Logger::Role::Error)
              when :warning then Logger.paint("⚠", Logger::Role::Warn)
              when :info    then Logger.paint("ℹ", Logger::Role::Dim)
              else               Logger.paint("✓", Logger::Role::Success)
              end
            end
          end

          private def ok_glyph(plain : Bool) : String
            plain ? "[ok]" : Logger.paint("✓", Logger::Role::Success)
          end

          private def run_fix(doctor : Services::Doctor, fix_values : Bool, approve_sections : Bool, dry_run : Bool, json_output : Bool)
            summary = doctor.fix_config(approve_sections: approve_sections, dry_run: dry_run, apply_value_fixes: fix_values)

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
                arrow = plain ? "->" : Logger.paint("→", Logger::Role::Success)
                Logger.info "  #{fix.field}: #{fix.before} #{arrow} #{fix.after}"
              end
              Logger.info ""
            end

            unless summary.sections_added.empty?
              if approve_sections
                Logger.success "#{verb_added} #{summary.sections_added.size} recommended config section(s):"
              else
                Logger.success "#{verb_added} #{summary.sections_added.size} config section(s):"
              end
              plus = plain ? "+" : Logger.paint("＋", Logger::Role::Success)
              summary.sections_added.each do |key|
                Logger.info "  #{plus} [#{key}]"
              end
              Logger.info ""
              Logger.info "These sections are added as comments by default."
              Logger.info "Uncomment the ones you want to enable."
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
