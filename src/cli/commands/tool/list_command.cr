# List command for listing content files by status
#
# This command lists content files based on their publication status.
# Usage:
#   hwaro tool list all       - List all content files
#   hwaro tool list drafts    - List only draft content files
#   hwaro tool list published - List only published content files

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
            FlagInfo.new(short: "-c", long: "--content-dir", description: "Content directory (default: content)", takes_value: true, value_hint: "DIR"),
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

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool list <all|drafts|published> [options]"
              parser.on("-c DIR", "--content-dir DIR", "Content directory (default: content)") { |dir| content_dir = dir }
              parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
              parser.unknown_args do |unknown|
                filter = unknown.first? if unknown.any?
              end
            end

            unless filter
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

            case filter.not_nil!.downcase
            when "all"
              lister.display(Services::ContentFilter::All)
            when "drafts", "draft"
              lister.display(Services::ContentFilter::Drafts)
            when "published", "pub"
              lister.display(Services::ContentFilter::Published)
            else
              Logger.error "Unknown filter: #{filter}"
              Logger.info "Use 'all', 'drafts', or 'published'"
              exit(1)
            end
          end
        end
      end
    end
  end
end
