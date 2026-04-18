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

          # Flags defined here are used both for OptionParser and completion generation
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
            filter : String? = nil
            json_output = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool list <all|drafts|published> [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| content_dir = v }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
              parser.unknown_args do |unknown|
                filter = unknown.first? if unknown.any?
              end
            end

            Logger.quiet = true if json_output

            unless filter
              if json_output
                puts({status: "error", error: {message: "Missing filter argument. Use 'all', 'drafts', or 'published'"}}.to_json)
                exit(1)
              end
              Logger.error "Missing filter argument. Use 'all', 'drafts', or 'published'"
              Logger.info ""
              Logger.info "Usage: hwaro tool list <all|drafts|published> [options]"
              Logger.info ""
              Logger.info "Filters:"
              Logger.info "  all        List all content files"
              Logger.info "  drafts     List only draft content files"
              Logger.info "  published  List only published content files"
              Logger.info ""
              Logger.info "Examples:"
              Logger.info "  hwaro tool list all"
              Logger.info "  hwaro tool list drafts"
              Logger.info "  hwaro tool list published --content-dir=posts"
              exit(1)
            end

            lister = Services::ContentLister.new(content_dir)

            content_filter = case filter.as(String).downcase
                             when "all"
                               Services::ContentFilter::All
                             when "drafts", "draft"
                               Services::ContentFilter::Drafts
                             when "published", "pub"
                               Services::ContentFilter::Published
                             else
                               if json_output
                                 puts({status: "error", error: {message: "Unknown filter: #{filter}"}}.to_json)
                                 exit(1)
                               end
                               Logger.error "Unknown filter: #{filter}"
                               Logger.info "Use 'all', 'drafts', or 'published'"
                               exit(1)
                             end

            if json_output
              contents = lister.list_content(content_filter)
              puts contents.to_json
            else
              lister.display(content_filter)
            end
          end
        end
      end
    end
  end
end
