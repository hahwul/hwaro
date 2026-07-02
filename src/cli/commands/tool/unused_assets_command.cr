# Unused Assets command for finding unreferenced static files
#
# This command scans static and co-located assets, then reports
# files not referenced by any content or template.
# Usage:
#   hwaro tool unused-assets [options]

require "json"
require "option_parser"
require "../../metadata"
require "../../prompt"
require "../../../services/unused_assets"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class UnusedAssetsCommand
          NAME               = "unused-assets"
          DESCRIPTION        = "Find unreferenced static files"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          FLAGS = [
            CONTENT_DIR_FLAG,
            FlagInfo.new(short: "-s", long: "--static-dir", description: "Static files directory (default: static)", takes_value: true, value_hint: "DIR"),
            FlagInfo.new(short: nil, long: "--delete", description: "Delete unused files (with confirmation)"),
            FlagInfo.new(short: "-f", long: "--force", description: "Skip confirmation prompt when deleting"),
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
            static_dir = "static"
            delete_mode = false
            force = false
            json_output = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool unused-assets [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              parser.on("-s DIR", "--static-dir DIR", "Static files directory (default: static)") { |v| static_dir = v }
              parser.on("--delete", "Delete unused files (with confirmation)") { delete_mode = true }
              parser.on("-f", "--force", "Skip confirmation prompt when deleting") { force = true }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            end

            # In JSON mode stdout must stay a single parseable document, so
            # silence `Logger.info`/`.success` (the `delete_unused` "Deleted: …"
            # lines included) the same way the sibling tool commands do.
            # `Logger.warn`/`.error` still reach stderr, so the no-force notice
            # below survives.
            Runner.enable_json_mode! if json_output

            service = Services::UnusedAssets.new(
              content_dir: content_dir,
              static_dir: static_dir,
            )
            result = service.run

            if json_output
              # Honour --delete in JSON mode too: previously the early return
              # printed the report and skipped deletion entirely, so
              # `--delete --json` was a silent no-op. Deletion in JSON mode
              # requires --force, since there is no interactive prompt — and
              # rather than fail silently without it, warn on stderr so the
              # skipped destructive action is visible without polluting stdout.
              if delete_mode && !result.unused_files.empty?
                if force
                  service.delete_unused(result.unused_files)
                else
                  Logger.warn "Skipping deletion in JSON mode: pass --force to confirm."
                end
              end
              puts result.to_json
              return
            end

            receipt = Logger::Receipt.new(NAME, static_dir)
              .row("total", result.total_assets.to_s)
              .row("referenced", result.referenced_count.to_s)
              .row("unused", result.unused_count.to_s)

            if result.unused_files.empty?
              receipt.outcome("found", "no unused assets")
              receipt.emit
              return
            end

            receipt.emit
            Logger.section("unused files")
            result.unused_files.each do |file|
              Logger.item(file, glyph: :bullet)
            end
            Logger.item("dynamic references (e.g. template variables) may cause false positives", glyph: :info)

            unless delete_mode
              Logger.outcome("found", "#{result.unused_count} unused assets", glyph: :warn)
              return
            end

            confirmed = force
            unless confirmed
              confirmed = Prompt.confirm?("Delete #{result.unused_count} unused file(s)?", default: false) == true
            end
            if confirmed
              service.delete_unused(result.unused_files)
              Logger.outcome("deleted", "#{result.unused_count} files")
            else
              Logger.outcome("cancelled", "no files deleted", glyph: :info)
            end
          end
        end
      end
    end
  end
end
