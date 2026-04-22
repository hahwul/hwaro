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

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            CONTENT_DIR_FLAG,
            FlagInfo.new(short: nil, long: "--fix", description: "Auto-fix issues (add missing config sections)"),
            FlagInfo.new(short: nil, long: "--minimal", description: "With --fix, skip advanced optional sections (pwa, amp, assets, etc.)"),
            JSON_FLAG,
            QUIET_FLAG,
            HELP_FLAG,
          ]

          # A named check that is evaluated from the Doctor-generated issue list.
          # `issue_ids` matches issues by exact id; `id_prefixes` matches by prefix.
          private record CheckSpec, label : String, issue_ids : Array(String), id_prefixes : Array(String) = [] of String

          # Groups of checks shown inline in the human-readable output.
          # IMPORTANT: keep in sync with ids emitted by Services::Doctor.
          CONFIG_CHECKS = [
            CheckSpec.new("file present & parseable",
              ["config-not-found", "config-parse-error"]),
            CheckSpec.new("base_url, title",
              ["base-url-missing", "base-url-scheme", "base-url-trailing-slash", "title-default"]),
            CheckSpec.new("sitemap (changefreq, priority)",
              ["sitemap-changefreq-invalid", "sitemap-priority-range"]),
            CheckSpec.new("taxonomies (duplicates)",
              ["taxonomy-duplicate", "language-duplicate"]),
            CheckSpec.new("search (format)",
              ["search-format-invalid"]),
          ]

          TEMPLATE_CHECKS = [
            CheckSpec.new("required files (page.html, section.html)",
              ["template-dir-missing", "template-required-missing"]),
            CheckSpec.new("template syntax",
              ["template-unclosed-block", "template-mismatched-vars", "template-read-error"]),
          ]

          CONTENT_CHECKS = [
            CheckSpec.new("front matter (TOML/YAML parse)",
              ["content-frontmatter-invalid", "content-read-error"]),
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
            config_path = "config.toml"
            json_output = false
            fix_mode = false
            minimal_mode = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro doctor [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              parser.on("--fix", "Auto-fix issues (add missing config sections)") { fix_mode = true }
              parser.on("--minimal", "With --fix, skip advanced optional sections (pwa, amp, assets, etc.)") { minimal_mode = true }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            end

            doctor = Services::Doctor.new(content_dir: content_dir, config_path: config_path)

            if minimal_mode && !fix_mode
              Logger.warn "--minimal has no effect without --fix"
            end

            if fix_mode
              run_fix(doctor, minimal_mode)
              return
            end

            issues = doctor.run

            if json_output
              result = {
                "issues"  => issues,
                "summary" => {
                  "errors"   => issues.count { |i| i.level == :error },
                  "warnings" => issues.count { |i| i.level == :warning },
                  "infos"    => issues.count { |i| i.level == :info },
                  "total"    => issues.size,
                },
              }
              puts result.to_json
              exit(exit_code_for(issues))
            end

            render_human(issues, config_path)
            exit(exit_code_for(issues))
          end

          # Map any `:error`-level issues to an appropriate exit code so
          # CI pipelines can gate on `hwaro doctor` directly. Warnings
          # and infos don't change the exit code — only real errors do.
          # Picks the highest-numeric exit across reported errors so
          # mixed categories surface the most severe failure class
          # (mirrors `deploy_command.cr#worst_exit_for`).
          private def exit_code_for(issues : Array(Services::Issue)) : Int32
            worst = Hwaro::Errors::EXIT_SUCCESS
            issues.each do |issue|
              next unless issue.level == :error
              code = exit_code_for_category(issue.category)
              worst = code if code > worst
            end
            worst
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

          # Render human-readable diagnostics with inline status glyphs per check.
          private def render_human(issues : Array(Services::Issue), config_path : String)
            plain = plain_output?

            Logger.info "Running diagnostics..."
            Logger.info ""
            Logger.info "  #{config_path}"
            CONFIG_CHECKS.each do |spec|
              Logger.info "    #{render_check_line(spec, issues, plain)}"
            end
            Logger.info ""
            Logger.info "  templates/"
            TEMPLATE_CHECKS.each do |spec|
              Logger.info "    #{render_check_line(spec, issues, plain)}"
            end
            Logger.info ""
            Logger.info "  content/"
            CONTENT_CHECKS.each do |spec|
              Logger.info "    #{render_check_line(spec, issues, plain)}"
            end
            Logger.info ""

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
          private def render_check_line(spec : CheckSpec, issues : Array(Services::Issue), plain : Bool) : String
            matched = issues.select { |i| check_matches?(spec, i) }
            level = worst_level(matched)
            "#{status_glyph(level, plain)} #{spec.label}"
          end

          private def check_matches?(spec : CheckSpec, issue : Services::Issue) : Bool
            return true if spec.issue_ids.includes?(issue.id)
            spec.id_prefixes.any? { |p| issue.id.starts_with?(p) }
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

          private def run_fix(doctor : Services::Doctor, minimal : Bool = false)
            added = doctor.fix_config(minimal: minimal)
            plain = plain_output?

            if added.empty?
              Logger.info "#{ok_glyph(plain)} Config is up to date — no missing sections."
            else
              Logger.success "Added #{added.size} missing config section(s) to config.toml:"
              plus = plain ? "+" : "＋".colorize(:green).to_s
              added.each do |key|
                Logger.info "  #{plus} [#{key}]"
              end
              Logger.info ""
              Logger.info "All new sections are commented out by default."
              Logger.info "Edit config.toml to enable the features you need."
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
