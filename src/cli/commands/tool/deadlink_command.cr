require "http/client"
require "uri"
require "file"
require "option_parser"
require "../../metadata"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class DeadlinkCommand
          # Single source of truth for command metadata
          NAME               = "deadlink"
          DESCRIPTION        = "Check for dead links in content files"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
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

          # Structure to hold link information
          record Link, file : String, url : String
          # Structure to hold check result
          record Result, link : Link, status : Int32, error : String?

          def run(args : Array(String))
            target_dir = "content"
            options = parse_options(args)

            unless Dir.exists?(target_dir)
              Logger.error "Directory not found: #{target_dir}"
              return
            end

            Logger.info "Starting dead link check in '#{target_dir}'..."

            links = find_links(target_dir)

            if links.empty?
              Logger.info "✔ No external links found."
              return
            end

            results = check_links_concurrently(links)
            dead_links = results.select { |r| !(200..299).includes?(r.status) }

            Logger.info "----------------------------------------"
            if dead_links.empty?
              Logger.info "✔ All #{links.size} links are healthy."
            else
              Logger.warn "✘ Found #{dead_links.size} dead links (out of #{links.size} total):"
              dead_links.each do |result|
                Logger.error "[DEAD] #{result.link.file}"
                Logger.error "  └─ URL: #{result.link.url}"
                Logger.error "  └─ Status: #{result.status}#{result.error ? " (Error: #{result.error})" : ""}"
              end
            end
            Logger.info "----------------------------------------"
          end

          private def find_links(dir : String) : Array(Link)
            links = [] of Link
            # Regex to find Markdown links (standard and image) with absolute URLs
            link_regex = /(?:!\[[^\]]*?\]|\[[^\]]*?\])\((https?:\/\/[^\s\)]+)\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = File.read(file)
              content.scan(link_regex) do |match|
                links << Link.new(file: file, url: match[1])
              end
            end
            links
          end

          private def check_links_concurrently(links : Array(Link)) : Array(Result)
            results_channel = Channel(Result).new(links.size)

            links.each do |link|
              spawn do
                status = 0
                error_message = nil
                begin
                  uri = URI.parse(link.url)
                  # Use HEAD request for efficiency
                  response = HTTP::Client.head(uri)
                  status = response.status_code
                rescue ex : Socket::ConnectError
                  status = -1
                  error_message = "Connection failed: #{ex.message}"
                rescue ex : IO::TimeoutError
                  status = -1
                  error_message = "Request timed out: #{ex.message}"
                rescue ex : Socket::Addrinfo::Error
                  status = -1
                  error_message = "DNS resolution failed: #{ex.message}"
                rescue ex
                  status = -1
                  error_message = ex.message
                end
                results_channel.send(Result.new(link: link, status: status, error: error_message))
              end
            end

            # Collect all results
            links.size.times.map { results_channel.receive }.to_a
          end

          private def parse_options(args : Array(String))
            options = {} of String => String
            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool deadlink [options]"
              parser.on("-h", "--help", "Show this help") do
                Logger.info parser.to_s
                exit
              end
            end
            options
          end
        end
      end
    end
  end
end
