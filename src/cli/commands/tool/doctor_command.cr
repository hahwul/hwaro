require "json"
require "colorize"
require "option_parser"
require "../../metadata"
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
              return
            end

            Logger.info "Running diagnostics..."
            Logger.info ""
            Logger.info "  #{config_path}"
            Logger.info "    ☐ base_url, title"
            Logger.info "    ☐ feeds (enabled + filename)"
            Logger.info "    ☐ sitemap (changefreq, priority)"
            Logger.info "    ☐ taxonomies (duplicates)"
            Logger.info "    ☐ search (format)"
            Logger.info ""
            Logger.info "  templates/"
            Logger.info "    ☐ required files (page.html, section.html)"
            Logger.info "    ☐ template syntax"
            Logger.info ""

            if issues.empty?
              Logger.info "#{"✔".colorize(:green)} No issues found. Your site looks great!"
              return
            end

            # Group by category
            config_issues = issues.select { |i| i.category == "config" }
            config_missing = issues.select { |i| i.category == "config_missing" }
            template_issues = issues.select { |i| i.category == "template" }
            structure_issues = issues.select { |i| i.category == "structure" }

            unless config_issues.empty?
              Logger.info "Config:"
              config_issues.each { |issue| print_issue(issue) }
              Logger.info ""
            end

            unless config_missing.empty?
              Logger.info "Missing Config Sections (run 'hwaro doctor --fix' to add):"
              config_missing.each { |issue| print_issue(issue) }
              Logger.info ""
            end

            unless template_issues.empty?
              Logger.info "Templates:"
              template_issues.each { |issue| print_issue(issue) }
              Logger.info ""
            end

            unless structure_issues.empty?
              Logger.info "Structure:"
              structure_issues.each { |issue| print_issue(issue) }
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

          private def run_fix(doctor : Services::Doctor, minimal : Bool = false)
            added = doctor.fix_config(minimal: minimal)

            if added.empty?
              Logger.info "#{"✔".colorize(:green)} Config is up to date — no missing sections."
            else
              Logger.success "Added #{added.size} missing config section(s) to config.toml:"
              added.each do |key|
                Logger.info "  #{"＋".colorize(:green)} [#{key}]"
              end
              Logger.info ""
              Logger.info "All new sections are commented out by default."
              Logger.info "Edit config.toml to enable the features you need."
            end
          end

          private def print_issue(issue : Services::Issue)
            icon = case issue.level
                   when :error   then "✘".colorize(:red)
                   when :warning then "⚠".colorize(:yellow)
                   when :info    then "ℹ".colorize(:cyan)
                   else               "?"
                   end

            file_part = issue.file ? " #{issue.file}:" : ""
            Logger.info "  #{icon}#{file_part} #{issue.message}"
          end
        end
      end
    end
  end
end
