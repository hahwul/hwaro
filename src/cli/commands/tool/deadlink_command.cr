require "json"
require "http/client"
require "socket"
require "uri"
require "file"
require "option_parser"
require "../../metadata"
require "../../../models/config"
require "../../../utils/errors"
require "../../../utils/logger"

module Hwaro
  module CLI
    module Commands
      module Tool
        class DeadlinkCommand
          # Single source of truth for command metadata
          NAME               = "check-links"
          DESCRIPTION        = "Check for dead links in content files"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          # Flags defined here are used both for OptionParser and completion generation
          FLAGS = [
            CONTENT_DIR_FLAG,
            FlagInfo.new(short: nil, long: "--timeout", description: "HTTP request timeout in seconds (default: 10)", takes_value: true, value_hint: "SECONDS"),
            FlagInfo.new(short: nil, long: "--concurrency", description: "Max concurrent requests (default: 8)", takes_value: true, value_hint: "N"),
            FlagInfo.new(short: nil, long: "--external-only", description: "Check external links only"),
            FlagInfo.new(short: nil, long: "--internal-only", description: "Check internal links only"),
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

          DEFAULT_TIMEOUT     = 10
          DEFAULT_CONCURRENCY =  8

          def run(args : Array(String))
            target_dir = "content"
            json_output = false
            timeout = DEFAULT_TIMEOUT
            concurrency = DEFAULT_CONCURRENCY
            external_only = false
            internal_only = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool check-links [options]"
              CLI.register_flag(parser, CONTENT_DIR_FLAG) { |v| target_dir = v }
              parser.on("--timeout SECONDS", "HTTP request timeout in seconds (default: #{DEFAULT_TIMEOUT})") do |v|
                parsed = v.to_i?
                unless parsed && parsed > 0
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: "Invalid --timeout value: #{v}",
                    hint: "Pass a positive integer number of seconds, e.g. --timeout 10.",
                  )
                end
                timeout = parsed
              end
              parser.on("--concurrency N", "Max concurrent requests (default: #{DEFAULT_CONCURRENCY})") do |v|
                parsed = v.to_i?
                unless parsed && parsed > 0
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: "Invalid --concurrency value: #{v}",
                    hint: "Pass a positive integer, e.g. --concurrency 8.",
                  )
                end
                concurrency = parsed.clamp(1, 128)
              end
              parser.on("--external-only", "Check external links only") { external_only = true }
              parser.on("--internal-only", "Check internal links only") { internal_only = true }
              CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
              CLI.register_flag(parser, HELP_FLAG) { |_| Logger.info parser.to_s; exit }
            end

            Logger.quiet = true if json_output
            Runner.json_mode = true if json_output

            if external_only && internal_only
              Logger.warn "--external-only and --internal-only cancel each other out; checking all links"
              external_only = false
              internal_only = false
            end

            unless Dir.exists?(target_dir)
              err = Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Directory not found: #{target_dir}",
              )
              if json_output
                puts err.to_error_payload.to_json
                exit(err.exit_code)
              end
              Logger.error "Error [#{err.code}]: #{err.message}"
              exit(err.exit_code)
            end

            Logger.info "Starting dead link check in '#{target_dir}'..." unless json_output

            external_links = internal_only ? [] of Link : find_external_links(target_dir)
            internal_links = external_only ? [] of Link : find_internal_links(target_dir)

            if external_links.empty? && internal_links.empty?
              if json_output
                puts({
                  "dead_internal" => [] of Result,
                  "dead_external" => [] of Result,
                }.to_json)
              else
                Logger.info "✔ No links found."
              end
              return
            end

            # Check external links
            external_results = check_links_concurrently(external_links, timeout, concurrency)
            dead_external = external_results.select { |r| !(200..299).includes?(r.status) }

            # Check internal links. Load taxonomy names from config.toml so
            # URLs like `/tags/` or `/categories/foo/` that Hwaro generates
            # at build time aren't reported as dead (the source-only check
            # has no way to discover these otherwise).
            project_root = find_project_root(target_dir)
            dead_internal = check_internal_links(internal_links, target_dir, load_taxonomy_names(project_root))

            total = external_links.size + internal_links.size
            dead_total = dead_external.size + dead_internal.size

            if json_output
              puts({
                "dead_internal" => dead_internal,
                "dead_external" => dead_external,
              }.to_json)
              # Exit non-zero so CI can gate on broken links (the JSON payload
              # has already been emitted to stdout for tooling to consume).
              exit(Hwaro::Errors::EXIT_GENERIC) if dead_total > 0
              return
            end

            Logger.info "----------------------------------------"
            if dead_total == 0
              Logger.info "✔ All #{total} links are healthy (#{external_links.size} external, #{internal_links.size} internal)."
            else
              Logger.warn "✘ Found #{dead_total} dead links (out of #{total} total):"
              dead_external.each do |result|
                Logger.error "[DEAD] #{sanitize_for_terminal(result.link.file)}"
                Logger.error "  └─ URL: #{sanitize_for_terminal(result.link.url)}"
                Logger.error "  └─ Status: #{result.status}#{result.error ? " (Error: #{sanitize_for_terminal(result.error.to_s)})" : ""}"
              end
              dead_internal.each do |result|
                Logger.error "[DEAD] #{sanitize_for_terminal(result.link.file)}"
                Logger.error "  └─ URL: #{sanitize_for_terminal(result.link.url)} (internal)"
                Logger.error "  └─ #{sanitize_for_terminal(result.error.to_s)}"
              end
            end
            Logger.info "----------------------------------------"

            # A dead-links result must fail the process so `check-links` is
            # usable as a CI gate; previously it always exited 0 regardless of
            # how many broken links were reported.
            exit(Hwaro::Errors::EXIT_GENERIC) if dead_total > 0
          end

          # Markdown links inside fenced code blocks or inline code spans are
          # documentation examples (e.g. a `![Diagram](/images/diagram.png)`
          # snippet demonstrating image syntax), not real links. Strip them
          # before scanning so `check-links` doesn't report false-positive dead
          # links — mirrors the code-stripping the scaffold link-integrity spec
          # already performs.
          private def strip_code(content : String) : String
            content
              .gsub(/```[\s\S]*?```/, "")
              .gsub(/`[^`\n]*`/, "")
          end

          # Link URLs/paths come from semi-trusted content (e.g. a docs/blog
          # PR) and are printed to the maintainer's terminal in the report.
          # A URL carrying raw ANSI/control bytes (the link regex's `\s` does
          # not exclude ESC) could repaint or spoof the console. Strip control
          # characters before logging so the report can't inject escapes.
          private def sanitize_for_terminal(s : String) : String
            s.gsub { |c| c.control? ? "" : c }
          end

          private def find_external_links(dir : String) : Array(Link)
            links = [] of Link
            link_regex = /(?:!\[[^\]]*?\]|\[[^\]]*?\])\((https?:\/\/[^\s\)]+)\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = strip_code(File.read(file))
              content.scan(link_regex) do |match|
                links << Link.new(file: file, url: match[1], kind: :external)
              end
            end
            links
          end

          # Normalize a Markdown link/image destination to a bare URL.
          # CommonMark allows an optional title after the destination
          # (`[t](/url "title")` / `![a](/img 'title')`); the capturing regex
          # `([^\)]+)` includes that title, so without stripping it the resolved
          # target became e.g. `/posts/b/ "title"` and every titled internal link
          # was falsely reported dead. A non-`<…>` destination cannot contain a
          # space (CommonMark ends it at the first whitespace), so taking the
          # first whitespace-delimited token yields the real destination.
          private def clean_link_target(raw : String) : String
            dest = raw.strip.split(/\s/, 2).first
            dest.split("#").first.split("?").first.strip
          end

          private def find_internal_links(dir : String) : Array(Link)
            links = [] of Link

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = strip_code(File.read(file))

              # Regular links (exclude images by using negative lookbehind)
              content.scan(/(?<!!)\[([^\]]*)\]\(([^\)]+)\)/) do |match|
                url = clean_link_target(match[2])
                next if url.empty? || url.starts_with?("http://") || url.starts_with?("https://") || url.starts_with?("mailto:") || url.starts_with?("#")
                links << Link.new(file: file, url: url, kind: :internal)
              end

              # Image links
              content.scan(/!\[([^\]]*)\]\(([^\)]+)\)/) do |match|
                url = clean_link_target(match[2])
                next if url.empty? || url.starts_with?("http://") || url.starts_with?("https://")
                links << Link.new(file: file, url: url, kind: :image)
              end
            end
            links
          end

          private def check_internal_links(links : Array(Link), content_dir : String, taxonomy_names : Array(String) = [] of String) : Array(Result)
            results = [] of Result
            project_root = find_project_root(content_dir)

            links.each do |link|
              base_dir = File.dirname(link.file)
              target = if link.url.starts_with?("@/")
                         # Zola-style content-root link (`@/posts/hello.md`).
                         # The build resolves these against the content dir,
                         # so the checker must too — otherwise valid links
                         # like `@/index.md` were reported dead (dogfooding find).
                         File.join(content_dir, link.url[2..])
                       elsif link.url.starts_with?("/")
                         File.join(content_dir, link.url.lstrip("/"))
                       else
                         File.join(base_dir, link.url)
                       end

              # Most internal URLs are written with a trailing slash
              # (`/about/`, `/posts/hello/`) — strip it before computing
              # the leaf-file candidate so `target_no_slash + ".md"`
              # resolves to `content/about.md` instead of the broken
              # `content/about/.md` the old code produced. The directory
              # candidates (`_index.md` / `index.md`) work either way.
              target_no_slash = target.rstrip("/")

              exists = File.exists?(target) ||
                       File.exists?(target_no_slash + ".md") ||
                       File.exists?(target_no_slash + ".markdown") ||
                       File.exists?(File.join(target_no_slash, "_index.md")) ||
                       File.exists?(File.join(target_no_slash, "index.md")) ||
                       (link.kind != :image && taxonomy_url?(link.url, taxonomy_names))

              # Also accept assets that live in static/ (source) or public/ (after build).
              # This prevents false positives for:
              # - Images and other files in static/images/, static/css/, etc.
              # - Resized/LQIP versions generated by the image pipeline (in public/)
              # - Any other files published via [content.files] or the asset pipeline.
              unless exists
                asset_path = link.url.lstrip("/")
                static_candidate = File.join(project_root, "static", asset_path)
                public_candidate = File.join(project_root, "public", asset_path)
                exists = File.exists?(static_candidate) || File.exists?(public_candidate)
              end

              unless exists
                kind_label = link.kind == :image ? "Image not found" : "Internal link target not found"
                results << Result.new(link: link, status: -1, error: kind_label)
              end
            end
            results
          end

          # Resolve the project root from the given content directory.
          # Supports running with -i content, -i ., or from inside a subdirectory.
          private def find_project_root(content_dir : String) : String
            # Common case: target_dir is "content" or ends with /content
            if File.basename(content_dir) == "content"
              parent = File.dirname(content_dir)
              return parent.empty? || parent == "." ? "." : parent
            end

            # If there's a "content" sibling, use the current directory as root
            if Dir.exists?(File.join(content_dir, "content")) || Dir.exists?(File.join(content_dir, "../content"))
              # content_dir might already be the project root
              return content_dir
            end

            content_dir
          end

          # Taxonomy listing and term pages (`/tags/`, `/categories/foo/`) are
          # generated by Hwaro at build time, so they have no source file to
          # check against. Match the URL's leading segment against the site's
          # declared taxonomy names and accept it when it lines up.
          private def taxonomy_url?(url : String, names : Array(String)) : Bool
            return false if names.empty?
            return false unless url.starts_with?("/")
            segments = url.lstrip("/").rstrip("/").split("/")
            return false if segments.empty? || segments.first.empty?
            names.includes?(segments.first)
          end

          # Load taxonomy names from config.toml when present. A missing or
          # malformed config is not fatal here — the check falls back to
          # behaving as if no taxonomies were declared, which preserves the
          # old strict behavior for projects that haven't configured any.
          private def load_taxonomy_names(project_root : String = ".") : Array(String)
            config_path = File.join(project_root, "config.toml")
            return [] of String unless File.exists?(config_path)

            # Temporarily chdir so Models::Config.load finds the right file
            Dir.cd(project_root) do
              config = Models::Config.load
              return config.taxonomies.map(&.name)
            end
          rescue Exception
            [] of String
          end

          private def check_links_concurrently(links : Array(Link), timeout_seconds : Int32, max_concurrency : Int32) : Array(Result)
            results_channel = Channel(Result).new(links.size)
            work_channel = Channel(Link?).new(max_concurrency)

            # Spawn bounded worker pool
            max_concurrency.times do
              spawn do
                while link = work_channel.receive?
                  error_message : String? = nil
                  status = begin
                    uri = URI.parse(link.url)
                    host = uri.host
                    if host && private_host?(host)
                      error_message = "Skipped: private/internal address"
                      results_channel.send(Result.new(link: link, status: -1, error: error_message))
                      next
                    end
                    client = HTTP::Client.new(uri)
                    client.connect_timeout = timeout_seconds.seconds
                    client.read_timeout = timeout_seconds.seconds
                    response = client.head(uri.request_target)
                    response.status_code
                  rescue ex : Socket::ConnectError
                    error_message = "Connection failed: #{ex.message}"
                    -1
                  rescue IO::TimeoutError
                    error_message = "Request timed out (#{timeout_seconds}s)"
                    -1
                  rescue ex : Socket::Addrinfo::Error
                    error_message = "DNS resolution failed: #{ex.message}"
                    -1
                  rescue ex
                    error_message = ex.message
                    -1
                  end
                  results_channel.send(Result.new(link: link, status: status, error: error_message))
                end
              end
            end

            # Feed links to workers
            links.each { |link| work_channel.send(link) }
            max_concurrency.times { work_channel.send(nil) }

            # Collect all results
            Array.new(links.size) { results_channel.receive }
          end

          # Check if a hostname resolves to a private/internal IP address (SSRF protection).
          private def private_host?(host : String) : Bool
            return true if host == "localhost" || host.ends_with?(".local") || host.ends_with?(".internal")

            begin
              addrs = Socket::Addrinfo.resolve(host, 80, type: Socket::Type::STREAM)
              addrs.any? do |addr|
                ip = addr.ip_address.address
                ip.starts_with?("127.") ||
                  ip.starts_with?("10.") ||
                  ip.starts_with?("192.168.") ||
                  ip.starts_with?("169.254.") ||
                  ip == "0.0.0.0" ||
                  ip == "::1" ||
                  ip == "::" ||
                  ip.starts_with?("fc") || ip.starts_with?("fd") || # IPv6 ULA
                  ip.starts_with?("fe80") ||                        # IPv6 link-local
                  private_172?(ip)
              end
            rescue Socket::Error
              false
            end
          end

          private def private_172?(ip : String) : Bool
            return false unless ip.starts_with?("172.")
            parts = ip.split(".")
            return false if parts.size < 2
            second = parts[1].to_i? || return false
            second >= 16 && second <= 31
          end
        end
      end
    end
  end
end
