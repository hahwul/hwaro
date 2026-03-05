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
          DESCRIPTION        = "Diagnose config and content issues"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            FlagInfo.new(
              short: "-c",
              long: "--content-dir",
              description: "Content directory to check",
              takes_value: true,
              value_hint: "DIR"
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
            content_dir = "content"
            config_path = "config.toml"

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool doctor [options]"
              parser.on("-c DIR", "--content-dir DIR", "Content directory to check") do |dir|
                content_dir = dir
              end
              parser.on("-h", "--help", "Show this help") do
                Logger.info parser.to_s
                exit
              end
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
            Logger.info "  #{content_dir}/"
            Logger.info "    ☐ frontmatter (title, description, date)"
            Logger.info "    ☐ frontmatter parse errors"
            Logger.info "    ☐ image alt text"
            Logger.info "    ☐ draft status"
            Logger.info ""

            doctor = Services::Doctor.new(content_dir: content_dir, config_path: config_path)
            issues = doctor.run

            if issues.empty?
              Logger.info "#{"✔".colorize(:green)} No issues found. Your site looks great!"
              return
            end

            # Group by category
            config_issues = issues.select { |i| i.category == "config" }
            content_issues = issues.select { |i| i.category == "content" }

            unless config_issues.empty?
              Logger.info "Config:"
              config_issues.each { |issue| print_issue(issue) }
              Logger.info ""
            end

            unless content_issues.empty?
              Logger.info "Content:"
              content_issues.each { |issue| print_issue(issue) }
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

            file_part = issue.file ? " #{issue.file}:" : ""
            Logger.info "  #{icon}#{file_part} #{issue.message}"
          end
        end
      end
    end
  end
end
