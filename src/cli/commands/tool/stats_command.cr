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

            Logger.quiet = true if json_output

            stats = Services::ContentStats.new(content_dir: content_dir)
            begin
              result = stats.run
            rescue ex
              if json_output
                puts({status: "error", error: {message: ex.message || "stats failed"}}.to_json)
                exit(1)
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

            Logger.info "Content statistics for '#{content_dir}':"
            Logger.info ""

            if result.total == 0
              Logger.info "  No content found."
              return
            end

            # Overview
            Logger.info "  Overview:"
            Logger.info "    Total:     #{result.total}"
            Logger.info "    Published: #{result.published}"
            Logger.info "    Drafts:    #{result.drafts}"
            Logger.info ""

            # Word counts
            Logger.info "  Word Count:"
            Logger.info "    Total:   #{result.words_total}"
            Logger.info "    Average: #{result.words_avg}"
            Logger.info "    Min:     #{result.words_min}"
            Logger.info "    Max:     #{result.words_max}"
            Logger.info ""

            # Top tags
            unless result.tags.empty?
              Logger.info "  Tags (top 15):"
              result.tags.first(15).each do |tag, count|
                bar = "█" * [count, 30].min
                Logger.info "    #{tag.ljust(20)} #{count.to_s.rjust(3)} #{bar}"
              end
              if result.tags.size > 15
                Logger.info "    ... and #{result.tags.size - 15} more"
              end
              Logger.info ""
            end

            # Monthly frequency
            unless result.monthly.empty?
              Logger.info "  Monthly Publishing:"
              result.monthly.each do |month, count|
                bar = "█" * [count, 30].min
                Logger.info "    #{month} #{count.to_s.rjust(3)} #{bar}"
              end
              Logger.info ""
            end
          end
        end
      end
    end
  end
end
