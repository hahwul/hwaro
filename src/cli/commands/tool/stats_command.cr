# Stats command for displaying content statistics
#
# This command shows content statistics including post counts,
# word count metrics, tag distribution, and publishing frequency.
# Usage:
#   hwaro tool stats [options]

require "json"
require "option_parser"
require "../../metadata"
require "../../../services/content_stats"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class StatsCommand
          NAME               = "stats"
          DESCRIPTION        = "Show content statistics"
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
              parser.banner = "Usage: hwaro tool stats [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            end

            Runner.enable_json_mode! if json_output

            stats = Services::ContentStats.new(content_dir: content_dir)
            begin
              result = stats.run
            rescue ex
              if json_output
                err = Hwaro::HwaroError.new(
                  code: Hwaro::Errors::HWARO_E_CONTENT,
                  message: ex.message || "stats failed",
                )
                puts err.to_error_payload.to_json
                exit(err.exit_code)
              else
                raise ex
              end
            end

            if json_output
              payload = {
                "total"      => result.total,
                "published"  => result.published,
                "drafts"     => result.drafts,
                "word_count" => {
                  "total"   => result.words_total,
                  "average" => result.words_avg,
                  "min"     => result.words_min,
                  "max"     => result.words_max,
                },
                "tags"    => result.tags,
                "monthly" => result.monthly,
              }
              puts payload.to_json
              return
            end

            if result.total == 0
              Logger.heading("stats", content_dir)
              Logger.outcome("counted", "no content found", :info)
              return
            end

            # Context receipt: totals, word counts (published only — matches
            # what `build` ships), then bar-chart sections and one outcome.
            receipt = Logger::Receipt.new("stats", content_dir)
            receipt.row("total", "#{result.total.format} #{result.total == 1 ? "file" : "files"}",
              emphasis: result.drafts > 0 ? "#{result.drafts.format} #{result.drafts == 1 ? "draft" : "drafts"}" : nil)
            receipt.row("words", "#{result.words_total.format} total · #{result.words_avg.format} avg")
            receipt.row("range", "#{result.words_min.format} min · #{result.words_max.format} max")
            receipt.emit

            # Top tags — bars scale against the most-used tag.
            unless result.tags.empty?
              Logger.info ""
              Logger.section("tags", result.tags.size > 15 ? "top 15" : nil)
              top_tags = result.tags.first(15)
              max_count = top_tags.max_of { |_, count| count }
              label_width = top_tags.max_of { |tag, _| tag.size }.clamp(0, 20)
              top_tags.each do |tag, count|
                Logger.info "      #{truncate_label(tag, label_width).ljust(label_width)}  #{count.to_s.rjust(4)}  #{Logger.bar(count, max_count)}"
              end
              if result.tags.size > 15
                Logger.info "      … and #{result.tags.size - 15} more"
              end
            end

            # Monthly publishing frequency.
            unless result.monthly.empty?
              Logger.info ""
              Logger.section("monthly")
              max_count = result.monthly.max_of { |_, count| count }
              result.monthly.each do |month, count|
                Logger.info "      #{month}  #{count.to_s.rjust(4)}  #{Logger.bar(count, max_count)}"
              end
            end

            Logger.info ""
            Logger.outcome("counted",
              "#{result.total.format} #{result.total == 1 ? "file" : "files"} · #{result.published.format} published · #{result.drafts.format} #{result.drafts == 1 ? "draft" : "drafts"}")
          end

          # Cap a bar-chart label to the column width, marking the cut with an
          # ellipsis so rows stay aligned even for very long tag names.
          private def truncate_label(label : String, width : Int32) : String
            return label if label.size <= width
            "#{label[0, width - 1]}…"
          end
        end
      end
    end
  end
end
