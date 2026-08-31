# List command for listing content files by status
#
# This command lists content files based on their publication status.
# Usage:
#   hwaro tool list all       - List all content files
#   hwaro tool list drafts    - List only draft content files
#   hwaro tool list published - List only published content files

require "json"
require "option_parser"
require "../../metadata"
require "../../../services/content_lister"
require "../../../models/config"
require "../../../core/build/data_disk"
require "../../../core/build/content_generate"
require "../../../content/processors/template"
require "../../../utils/date_utils"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class ListCommand
          # Single source of truth for command metadata
          NAME               = "list"
          DESCRIPTION        = "List content files (all, drafts, published)"
          POSITIONAL_ARGS    = ["filter"]
          POSITIONAL_CHOICES = ["all", "drafts", "published"]

          SORT_FLAG    = FlagInfo.new(short: nil, long: "--sort", description: "Sort key: date (newest first, default), title, or path", takes_value: true, value_hint: "KEY")
          REVERSE_FLAG = FlagInfo.new(short: "-r", long: "--reverse", description: "Reverse the sort order")
          LIMIT_FLAG   = FlagInfo.new(short: "-n", long: "--limit", description: "Show at most N files (applied after sorting)", takes_value: true, value_hint: "N")

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            CONTENT_DIR_FLAG,
            SORT_FLAG,
            REVERSE_FLAG,
            LIMIT_FLAG,
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
            filter : String? = nil
            json_output = false
            sort = Services::ContentSort::Date
            reverse = false
            limit : Int32? = nil

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool list <all|drafts|published> [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, SORT_FLAG) do |v|
                sort = Services::ContentSort.parse?(v) || raise Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_USAGE,
                  message: "Invalid --sort value: #{v}",
                  hint: "Supported keys: date, title, path.",
                )
              end
              CLI.register_flag(parser, REVERSE_FLAG) { |_| reverse = true }
              CLI.register_flag(parser, LIMIT_FLAG) do |v|
                parsed = v.to_i?
                unless parsed && parsed > 0
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: "Invalid --limit value: #{v}",
                    hint: "Pass a positive integer, e.g. --limit 10.",
                  )
                end
                limit = parsed
              end
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |unknown|
                filter = unknown.first? if unknown.present?
              end
            end

            Runner.enable_json_mode! if json_output

            supported = POSITIONAL_CHOICES.join(", ")

            unless filter
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "missing <filter> argument",
                hint: "Usage: hwaro tool list <all|drafts|published> — supported: #{supported}.",
              )
            end

            # A missing content directory is a failure, not an empty listing:
            # the command used to print "not found" on stderr, `[]` on stdout
            # and still exit 0, so a script could not tell "no content" from
            # "wrong directory". Matches `tool validate` / `tool check-links`.
            unless Dir.exists?(content_dir)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_CONTENT,
                message: "Content directory '#{content_dir}' does not exist",
                hint: "Create it or pass --content-dir DIR to point at your content root.",
              )
            end

            lister = Services::ContentLister.new(content_dir, generated_content_infos)

            content_filter = case filter.as(String).downcase
                             when "all"
                               Services::ContentFilter::All
                             when "drafts", "draft"
                               Services::ContentFilter::Drafts
                             when "published", "pub"
                               Services::ContentFilter::Published
                             else
                               raise Hwaro::HwaroError.new(
                                 code: Hwaro::Errors::HWARO_E_USAGE,
                                 message: "unknown filter: #{filter}",
                                 hint: "Supported: #{supported}.",
                               )
                             end

            if json_output
              contents = lister.list_content(content_filter, sort, reverse, limit)
              puts contents.to_json
            else
              lister.display(content_filter, sort, reverse, limit)
            end
          end

          # Plan `[[content.generate]]` pages so the listing shows what a
          # build actually publishes, not just what sits in content/ — a
          # generated page has no file for the walker to find, and "where
          # did my page go" needs an answer here. Planning uses DISK data
          # only (plus nothing from the network): a rule backed by a
          # not-yet-fetched [[data.remote]] key gets a note instead of rows,
          # and any planning failure degrades to a warning — a bad record
          # must not take down the listing of authored files.
          private def generated_content_infos : Array(Services::ContentInfo)
            return [] of Services::ContentInfo unless File.exists?("config.toml")

            config = begin
              Models::Config.load
            rescue Exception
              # An unloadable config disables generated rows, not the listing.
              return [] of Services::ContentInfo
            end
            return [] of Services::ContentInfo if config.content_generate.empty?

            disk_data = Core::Build::DataDisk.load_hash
            remote_keys = config.data_remote.map(&.key)

            plannable = config.content_generate.select do |rule|
              root_key = rule.source.split('.').first
              if !disk_data.has_key?(root_key) && remote_keys.includes?(root_key)
                Logger.info "  [[content.generate]] \"#{rule.source}\": remote source — its pages appear after a build fetches site.data.#{root_key}."
                false
              else
                true
              end
            end
            return [] of Services::ContentInfo if plannable.empty?

            config.content_generate = plannable
            env = Content::Processors::TemplateEngine.new.env
            plans = Core::Build::ContentGenerate.plan(config, disk_data, env, include_bodies: false)

            now = Time.utc
            plans.map do |plan|
              date = plan.date_raw.try { |raw| Utils::DateUtils.parse_content_date(raw) }
              status = date && date > now ? "future" : "published"
              Services::ContentInfo.new(
                path: plan.path,
                title: plan.title,
                draft: false,
                date: date,
                status: status,
                generated_from: plan.origin,
              )
            end
          rescue ex : Hwaro::HwaroError
            Logger.warn "  Skipping [[content.generate]] rows: #{ex.message}"
            [] of Services::ContentInfo
          end
        end
      end
    end
  end
end
