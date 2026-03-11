require "json"
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

          # Structure to hold link information
          record Link, file : String, url : String, kind : Symbol = :external do
            include JSON::Serializable

            @[JSON::Field(converter: Hwaro::CLI::Commands::Tool::DeadlinkCommand::SymbolConverter)]
            getter kind : Symbol
          end

          # Structure to hold check result
          record Result, link : Link, status : Int32, error : String? do
            include JSON::Serializable
          end

          module SymbolConverter
            def self.to_json(value : Symbol, json : JSON::Builder)
              json.string(value.to_s)
            end

            def self.from_json(pull : JSON::PullParser) : Symbol
              pull.read_string.to_s
            end
          end

          def run(args : Array(String))
            target_dir = "content"
            json_output = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool deadlink [options]"
              parser.on("-j", "--json", "Output result as JSON") { json_output = true }
              parser.on("-h", "--help", "Show this help") do
                Logger.info parser.to_s
                exit
              end
            end

            unless Dir.exists?(target_dir)
              Logger.error "Directory not found: #{target_dir}"
              return
            end

            Logger.info "Starting dead link check in '#{target_dir}'..." unless json_output

            external_links = find_external_links(target_dir)
            internal_links = find_internal_links(target_dir)

            if external_links.empty? && internal_links.empty?
              if json_output
                puts({
                  "dead_links"      => [] of Result,
                  "total_links"     => 0,
                  "external_links"  => 0,
                  "internal_links"  => 0,
                  "dead_link_count" => 0,
                }.to_json)
              else
                Logger.info "✔ No links found."
              end
              return
            end

            # Check external links
            external_results = check_links_concurrently(external_links)
            dead_external = external_results.select { |r| !(200..299).includes?(r.status) }

            # Check internal links
            dead_internal = check_internal_links(internal_links, target_dir)

            total = external_links.size + internal_links.size
            dead_total = dead_external.size + dead_internal.size

            if json_output
              puts({
                "dead_links"      => dead_external + dead_internal,
                "total_links"     => total,
                "external_links"  => external_links.size,
                "internal_links"  => internal_links.size,
                "dead_link_count" => dead_total,
              }.to_json)
              return
            end

            Logger.info "----------------------------------------"
            if dead_total == 0
              Logger.info "✔ All #{total} links are healthy (#{external_links.size} external, #{internal_links.size} internal)."
            else
              Logger.warn "✘ Found #{dead_total} dead links (out of #{total} total):"
              dead_external.each do |result|
                Logger.error "[DEAD] #{result.link.file}"
                Logger.error "  └─ URL: #{result.link.url}"
                Logger.error "  └─ Status: #{result.status}#{result.error ? " (Error: #{result.error})" : ""}"
              end
              dead_internal.each do |result|
                Logger.error "[DEAD] #{result.link.file}"
                Logger.error "  └─ URL: #{result.link.url} (internal)"
                Logger.error "  └─ #{result.error}"
              end
            end
            Logger.info "----------------------------------------"
          end

          private def find_external_links(dir : String) : Array(Link)
            links = [] of Link
            link_regex = /(?:!\[[^\]]*?\]|\[[^\]]*?\])\((https?:\/\/[^\s\)]+)\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = File.read(file)
              content.scan(link_regex) do |match|
                links << Link.new(file: file, url: match[1], kind: :external)
              end
            end
            links
          end

          private def find_internal_links(dir : String) : Array(Link)
            links = [] of Link
            # Match standard markdown links [text](url) — skip external and mailto
            link_regex = /\[([^\]]*)\]\(([^\)]+)\)/
            # Match image links ![alt](url) — skip external
            img_regex = /!\[([^\]]*)\]\(([^\)]+)\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = File.read(file)

              # Regular links (exclude images by using negative lookbehind)
              content.scan(/(?<!!)\[([^\]]*)\]\(([^\)]+)\)/) do |match|
                url = match[2].split("#").first.split("?").first.strip
                next if url.empty? || url.starts_with?("http://") || url.starts_with?("https://") || url.starts_with?("mailto:") || url.starts_with?("#")
                links << Link.new(file: file, url: url, kind: :internal)
              end

              # Image links
              content.scan(/!\[([^\]]*)\]\(([^\)]+)\)/) do |match|
                url = match[2].split("#").first.split("?").first.strip
                next if url.empty? || url.starts_with?("http://") || url.starts_with?("https://")
                links << Link.new(file: file, url: url, kind: :image)
              end
            end
            links
          end

          private def check_internal_links(links : Array(Link), content_dir : String) : Array(Result)
            results = [] of Result
            links.each do |link|
              base_dir = File.dirname(link.file)
              target = if link.url.starts_with?("/")
                         File.join(content_dir, link.url.lstrip("/"))
                       else
                         File.join(base_dir, link.url)
                       end

              exists = File.exists?(target) ||
                       File.exists?(target + ".md") ||
                       File.exists?(File.join(target, "_index.md")) ||
                       File.exists?(File.join(target, "index.md"))

              unless exists
                kind_label = link.kind == :image ? "Image not found" : "Internal link target not found"
                results << Result.new(link: link, status: -1, error: kind_label)
              end
            end
            results
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
        end
      end
    end
  end
end
