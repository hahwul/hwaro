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

            Runner.enable_json_mode! if json_output

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

            Logger.heading("check-links", target_dir) unless json_output

            external_links = internal_only ? [] of Link : find_external_links(target_dir)
            internal_links = external_only ? [] of Link : find_internal_links(target_dir)

            if external_links.empty? && internal_links.empty?
              if json_output
                puts({
                  "dead_internal" => [] of Result,
                  "dead_external" => [] of Result,
                }.to_json)
              else
                Logger.outcome("checked", "no links found", :info)
              end
              return
            end

            # Check external links
            external_results = check_links_concurrently(external_links, timeout, concurrency)
            skipped_external = external_results.select { |r| r.error == "Skipped: private/internal address" }
            dead_external = external_results.select { |r| !(200..299).includes?(r.status) && r.error != "Skipped: private/internal address" }

            # Check internal links. Load taxonomy names from config.toml so
            # URLs like `/tags/` or `/categories/foo/` that Hwaro generates
            # at build time aren't reported as dead (the source-only check
            # has no way to discover these otherwise).
            project_root = find_project_root(target_dir)
            config = load_config(project_root)
            taxonomy_names = config ? config.taxonomies.map(&.name) : [] of String
            base_path = config ? config.base_path : ""
            # Non-default language codes are served under a `/<code>/` prefix
            # (`content/about.ko.md` → `/ko/about/`), so the checker has to
            # strip that segment before resolving — otherwise every link in a
            # multilingual site resolves against `content/ko/…` and is
            # reported dead.
            language_codes = translation_language_codes(config)
            dead_internal = check_internal_links(internal_links, target_dir, taxonomy_names, base_path, language_codes)

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

            Logger.section("scan", "#{external_links.size} external · #{internal_links.size} internal")
            links_noun = total == 1 ? "link" : "links"

            if dead_total == 0 && skipped_external.empty?
              Logger.info "" if Logger.color_enabled?
              Logger.outcome("checked", "#{total} #{links_noun} · all healthy")
            else
              Logger.info "" if dead_total > 0 || !skipped_external.empty?
              skipped_external.each do |result|
                Logger.item(sanitize_for_terminal(result.link.file), glyph: :info)
                detail = "#{sanitize_for_terminal(result.link.url)} — #{sanitize_for_terminal(result.error.to_s)}"
                Logger.item(detail, glyph: :arrow, indent: 4)
              end
              dead_external.each do |result|
                Logger.item(sanitize_for_terminal(result.link.file), glyph: :err)
                detail = "#{sanitize_for_terminal(result.link.url)}  #{result.status}"
                detail += " — #{sanitize_for_terminal(result.error.to_s)}" if result.error
                Logger.item(detail, glyph: :arrow, indent: 4)
              end
              dead_internal.each do |result|
                Logger.item(sanitize_for_terminal(result.link.file), glyph: :err)
                Logger.item("#{sanitize_for_terminal(result.link.url)}  #{sanitize_for_terminal(result.error.to_s)}", glyph: :arrow, indent: 4)
              end
              Logger.info "" if Logger.color_enabled?
              if dead_total == 0
                Logger.outcome("checked", "#{total} #{links_noun} · all healthy")
              else
                Logger.outcome("checked", "#{total} #{links_noun} · #{dead_total} dead", :err)
              end
            end

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
          #
          # Fences are tracked line-by-line, CommonMark-style: a fence opens
          # with 3+ backticks/tildes (up to 3 spaces of indent) and only
          # closes on a fence of the same character at least as long. The old
          # non-greedy /```[\s\S]*?```/ mispaired nested fences — a 4-backtick
          # example wrapping a 3-backtick fence desynchronized every fence
          # after it, resurrecting example links as false positives.
          private def strip_code(content : String) : String
            result = String::Builder.new
            fence_char : Char? = nil
            fence_len = 0

            content.each_line(chomp: false) do |line|
              if m = line.match(/\A {0,3}(`{3,}|~{3,})/)
                marker = m[1]
                if fence_char.nil?
                  fence_char = marker[0]
                  fence_len = marker.size
                  result << '\n'
                  next
                elsif marker[0] == fence_char && marker.size >= fence_len
                  fence_char = nil
                  fence_len = 0
                  result << '\n'
                  next
                end
              end

              if fence_char
                result << '\n'
              else
                result << line.gsub(/`[^`\n]*`/, "")
              end
            end

            result.to_s
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
            link_regex = /(?:!\[[^\]]*?\]|\[[^\]]*?\])\((https?:\/\/(?:\([^\s()]*\)|[^\s()])+)\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = readable_markdown(file) || next
              content.scan(link_regex) do |match|
                links << Link.new(file: file, url: match[1], kind: :external)
              end
              scan_reference_definitions(content) do |url|
                next unless url.starts_with?("http://") || url.starts_with?("https://")
                links << Link.new(file: file, url: url, kind: :external)
              end
            end
            links
          end

          # Read and code-strip one Markdown file, returning nil when the file
          # cannot be scanned. A file containing invalid UTF-8 makes PCRE2
          # raise `ArgumentError` mid-scan, which used to abort the whole run
          # with a bare "Error: Regex match error" and exit 1 — the same code
          # as "dead links found", so CI could not tell the two apart. Skip the
          # file with a warning instead, matching how `tool list` and
          # `tool validate` degrade on the same input.
          private def readable_markdown(file : String) : String?
            strip_code(File.read(file))
          rescue ex : ArgumentError | IO::Error
            Logger.warn "Skipping #{file}: #{ex.message}"
            nil
          end

          # Markdown link/image destination, allowing ONE level of balanced
          # parentheses inside it. Plain `([^\)]+)` stopped at the first `)`,
          # so `[x](/docs/foo_(bar))` was scanned as `/docs/foo_(bar` and
          # reported dead — a false positive on a link the build resolves fine.
          # The alternation branches start with disjoint characters, so there
          # is no backtracking ambiguity.
          LINK_DEST = /((?:[^()]|\([^()]*\))*)/

          # Normalize a Markdown link/image destination to a bare URL.
          #
          # CommonMark allows an optional title after the destination
          # (`[t](/url "title")` / `![a](/img 'title')`); the capture includes
          # that title, so without stripping it the resolved target became e.g.
          # `/posts/b/ "title"` and every titled internal link was falsely
          # reported dead.
          #
          # An angle-bracket destination (`[t](</my page.md> "title")`) is the
          # one form that MAY contain spaces, so the whitespace split has to
          # come after unwrapping it — otherwise the target was the literal
          # `</my`, and even a space-free `</about/>` was reported dead while
          # the build resolved it correctly.
          private def clean_link_target(raw : String) : String
            stripped = raw.strip
            dest =
              if stripped.starts_with?('<') && (close = stripped.index('>'))
                stripped[1...close]
              else
                stripped.split(/\s/, 2).first
              end
            dest.split("#").first.split("?").first.strip
          end

          private def find_internal_links(dir : String) : Array(Link)
            links = [] of Link
            link_re = /(?<!!)\[([^\]]*)\]\(#{LINK_DEST.source}\)/
            image_re = /!\[([^\]]*)\]\(#{LINK_DEST.source}\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = readable_markdown(file) || next

              # Regular links (exclude images by using negative lookbehind)
              content.scan(link_re) do |match|
                url = clean_link_target(match[2])
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: :internal)
              end

              # Image links
              content.scan(image_re) do |match|
                url = clean_link_target(match[2])
                next if skip_internal?(url, allow_fragment: false)
                links << Link.new(file: file, url: url, kind: :image)
              end

              # Reference-style links (`[text][id]` + `[id]: /target/`) and
              # raw HTML anchors/images. Both render as real links, so a page
              # written that way used to get a clean bill of health.
              scan_reference_definitions(content) do |raw|
                url = clean_link_target(raw)
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: :internal)
              end

              content.scan(HTML_LINK_RE) do |match|
                url = clean_link_target(match[2])
                next if skip_internal?(url) || url.includes?("{{") || url.includes?("{%")
                kind = match[1].downcase == "a" ? :internal : :image
                links << Link.new(file: file, url: url, kind: kind)
              end
            end
            links
          end

          # `<a href="…">` / `<img src="…">` written directly in Markdown.
          # Restricted to those two tags so shortcode/template attributes on
          # other elements can't leak in as links.
          HTML_LINK_RE = /<(a|img)\b[^>]*?\s(?:href|src)\s*=\s*["']([^"']*)["']/i

          # A Markdown link reference definition (`[id]: /target/ "title"`).
          #
          # Two guards keep this from inventing links: footnote definitions
          # (`[^1]: …`) are skipped, and the destination must actually look
          # like a URL or path — otherwise the first word of a plain-prose
          # definition body would be resolved as a relative path and reported
          # dead.
          REFERENCE_DEFINITION_RE = /^ {0,3}\[([^\]\n]+)\]:[ \t]*(\S+)/m

          private def scan_reference_definitions(content : String, &)
            content.scan(REFERENCE_DEFINITION_RE) do |match|
              next if match[1].starts_with?('^')
              dest = match[2]
              dest = dest[1..-2] if dest.starts_with?('<') && dest.ends_with?('>')
              next unless dest.starts_with?('/') || dest.starts_with?("./") ||
                          dest.starts_with?("../") || dest.starts_with?("@/") ||
                          dest =~ /\A[a-z][a-z0-9+.\-]*:/i
              yield dest
            end
          end

          # Destinations the filesystem check cannot say anything about:
          # empty, protocol-relative, pure fragments, and anything carrying a
          # URI scheme (`mailto:`, `tel:`, `javascript:`, `https:`, …).
          private def skip_internal?(url : String, allow_fragment : Bool = true) : Bool
            return true if url.empty?
            return true if allow_fragment && url.starts_with?("#")
            return true if url.starts_with?("//")
            !!(url =~ /\A[a-z][a-z0-9+.\-]*:/i)
          end

          private def check_internal_links(links : Array(Link), content_dir : String, taxonomy_names : Array(String) = [] of String, base_path : String = "", language_codes : Array(String) = [] of String) : Array(Result)
            results = [] of Result
            project_root = find_project_root(content_dir)

            links.each do |link|
              decoded_url = URI.decode(link.url)
              resolved_url = decoded_url
              if resolved_url.starts_with?("/") && !base_path.empty?
                if resolved_url == base_path
                  resolved_url = "/"
                elsif resolved_url.starts_with?(base_path + "/")
                  resolved_url = resolved_url[base_path.size..]
                end
              end

              # `/ko/about/` is `content/about.ko.md`; strip the language
              # segment and remember the code so the leaf candidates below
              # can look for the translated source file.
              lang = strip_language_prefix(resolved_url, language_codes)
              if lang
                resolved_url = resolved_url[(lang.size + 1)..]
                resolved_url = "/" if resolved_url.empty?
              end

              base_dir = File.dirname(link.file)
              target = if resolved_url.starts_with?("@/")
                         # Zola-style content-root link (`@/posts/hello.md`).
                         # The build resolves these against the content dir,
                         # so the checker must too — otherwise valid links
                         # like `@/index.md` were reported dead (dogfooding find).
                         File.join(content_dir, resolved_url[2..])
                       elsif resolved_url.starts_with?("/")
                         File.join(content_dir, resolved_url.lstrip("/"))
                       else
                         File.join(base_dir, resolved_url)
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
                       (link.kind != :image && taxonomy_url?(resolved_url, taxonomy_names))

              # Translated sources carry the language code in the filename
              # (`about.ko.md`, `_index.ko.md`), so a `/ko/…` link only
              # resolves once those candidates are probed too.
              if !exists && (code = lang)
                exists = File.exists?("#{target_no_slash}.#{code}.md") ||
                         File.exists?("#{target_no_slash}.#{code}.markdown") ||
                         File.exists?(File.join(target_no_slash, "_index.#{code}.md")) ||
                         File.exists?(File.join(target_no_slash, "index.#{code}.md"))
              end

              # Also accept assets that live in static/ (source) or public/ (after build).
              # This prevents false positives for:
              # - Images and other files in static/images/, static/css/, etc.
              # - Resized/LQIP versions generated by the image pipeline (in public/)
              # - Any other files published via [content.files] or the asset pipeline.
              unless exists
                asset_path = resolved_url.lstrip("/")
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
          # Language codes that get a `/<code>/` URL prefix: every declared
          # language except the default one, which is served at the root.
          private def translation_language_codes(config : Models::Config?) : Array(String)
            return [] of String unless config
            config.languages.keys.reject { |code| code.empty? || code == config.default_language }
          end

          # Returns the leading language segment of an absolute URL when it
          # names a non-default language, else nil.
          private def strip_language_prefix(url : String, codes : Array(String)) : String?
            return if codes.empty?
            return unless url.starts_with?("/")
            segment = url.lstrip("/").split("/").first?
            return unless segment
            codes.includes?(segment) ? segment : nil
          end

          private def taxonomy_url?(url : String, names : Array(String)) : Bool
            return false if names.empty?
            return false unless url.starts_with?("/")
            segments = url.lstrip("/").rstrip("/").split("/")
            return false if segments.empty? || segments.first.empty?
            names.includes?(segments.first)
          end

          private def load_config(project_root : String = ".") : Models::Config?
            config_path = File.join(project_root, "config.toml")
            return unless File.exists?(config_path)

            Dir.cd(project_root) do
              Models::Config.load
            end
          rescue Exception
            nil
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
                    current_uri = URI.parse(link.url)
                    method = "HEAD"
                    redirects_left = 5
                    response_status = -1

                    loop do
                      host = current_uri.host
                      if host && private_host?(host)
                        error_message = "Skipped: private/internal address"
                        response_status = -1
                        break
                      end

                      client = HTTP::Client.new(current_uri)
                      client.connect_timeout = timeout_seconds.seconds
                      client.read_timeout = timeout_seconds.seconds

                      begin
                        headers = HTTP::Headers{"User-Agent" => "hwaro-link-checker/1.0"}
                        response = if method == "HEAD"
                                     client.head(current_uri.request_target, headers: headers)
                                   else
                                     client.get(current_uri.request_target, headers: headers)
                                   end

                        status_code = response.status_code

                        if {301, 302, 307, 308}.includes?(status_code)
                          if redirects_left > 0
                            location = response.headers["Location"]?
                            if location
                              current_uri = current_uri.resolve(location)
                              redirects_left -= 1
                              next
                            else
                              error_message = "Redirect without Location header"
                              response_status = status_code
                              break
                            end
                          else
                            error_message = "Too many redirects"
                            response_status = status_code
                            break
                          end
                        elsif method == "HEAD" && {405, 403, 501}.includes?(status_code)
                          method = "GET"
                          next
                        else
                          response_status = status_code
                          break
                        end
                      ensure
                        client.close
                      end
                    end

                    response_status
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
