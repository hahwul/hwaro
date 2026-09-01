require "json"
require "http/client"
require "socket"
require "uri"
require "uri/punycode"
require "file"
require "option_parser"
require "../../metadata"
require "toml"
require "yaml"
require "../../../models/config"
require "../../../utils/frontmatter_scanner"
require "../../../utils/text_utils"
require "../../../utils/errors"
require "../../../utils/logger"
require "../../../utils/build_output"

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
            FlagInfo.new(short: nil, long: "--ignore-url", description: "Skip links whose URL matches PATTERN (substring; * wildcards; repeatable)", takes_value: true, value_hint: "PATTERN"),
            FlagInfo.new(short: nil, long: "--allow-status", description: "Treat these HTTP status codes as healthy (comma-separated, e.g. 403,429)", takes_value: true, value_hint: "CODES"),
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
            ignore_patterns = [] of Regex
            allowed_statuses = Set(Int32).new

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
              parser.on("--ignore-url PATTERN", "Skip links whose URL matches PATTERN (substring; * wildcards; repeatable)") do |v|
                if v.strip.empty?
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: "--ignore-url expects a non-empty pattern",
                    hint: "Example: --ignore-url twitter.com or --ignore-url 'https://example.com/*'.",
                  )
                end
                ignore_patterns << ignore_pattern_to_regex(v)
              end
              parser.on("--allow-status CODES", "Treat these HTTP status codes as healthy (comma-separated)") do |v|
                segments = v.split(',')
                # All-empty input (`--allow-status ","`) would otherwise be a
                # silent no-op; reject it like any other unusable value.
                if segments.all?(&.strip.empty?)
                  raise Hwaro::HwaroError.new(
                    code: Hwaro::Errors::HWARO_E_USAGE,
                    message: "Invalid --allow-status value: #{v}",
                    hint: "Pass comma-separated HTTP status codes between 100 and 599, e.g. --allow-status 403,429.",
                  )
                end
                segments.each do |code|
                  # A trailing/doubled comma (`--allow-status "403,"`) yields
                  # empty segments; skip them instead of rejecting with a
                  # confusing empty-value message.
                  next if code.strip.empty?
                  parsed = code.strip.to_i?
                  unless parsed && (100..599).includes?(parsed)
                    raise Hwaro::HwaroError.new(
                      code: Hwaro::Errors::HWARO_E_USAGE,
                      message: "Invalid --allow-status value: #{code.strip}",
                      hint: "Pass comma-separated HTTP status codes between 100 and 599, e.g. --allow-status 403,429.",
                    )
                  end
                  allowed_statuses << parsed
                end
              end
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

            # `--ignore-url` drops matching links BEFORE any check runs, so an
            # ignored external host is never contacted at all — the point is
            # silencing a known-flaky or paywalled domain in CI, not merely
            # hiding its failure afterwards.
            ignored_count = 0
            unless ignore_patterns.empty?
              before = external_links.size + internal_links.size
              external_links = external_links.reject { |l| ignore_patterns.any?(&.matches?(l.url)) }
              internal_links = internal_links.reject { |l| ignore_patterns.any?(&.matches?(l.url)) }
              ignored_count = before - external_links.size - internal_links.size
            end

            if external_links.empty? && internal_links.empty?
              if json_output
                # `ignored_count` distinguishes "all healthy" from "an
                # over-broad --ignore-url pattern checked nothing".
                puts({
                  "dead_internal"    => [] of Result,
                  "dead_external"    => [] of Result,
                  "skipped_external" => [] of Result,
                  "ignored_count"    => ignored_count,
                  # Same key on every payload: a consumer reads one schema,
                  # and "nothing to check" has no build-output caveat.
                  "output_hint" => nil,
                }.to_json)
              else
                Logger.outcome("checked", ignored_count > 0 ? "no links to check (#{ignored_count} ignored)" : "no links found", :info)
              end
              return
            end

            # Check external links
            external_results = check_links_concurrently(external_links, timeout, concurrency)
            skipped_external = external_results.select { |r| r.error == "Skipped: private/internal address" }
            dead_external = external_results.select do |r|
              !(200..299).includes?(r.status) &&
                !allowed_statuses.includes?(r.status) &&
                r.error != "Skipped: private/internal address"
            end

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
            generated_routes = generated_routes(config)
            # Follow `[build] output_dir`; "public" only as the fallback. The
            # tree is consulted through the oracle so a serve-only workflow
            # (which since #758 never populates it) is told why its
            # pipeline-emitted assets read as dead, instead of validating
            # against an absent — or permanently stale — tree (#761).
            output_dir = config.try(&.build.output_dir) || "public"
            oracle = Utils::BuildOutput.oracle(
              output_dir,
              root: project_root,
              sources: [target_dir] + %w[config.toml templates static data themes].map { |d| File.join(project_root, d) },
              tool: "check-links",
            )
            dead_internal = check_internal_links(internal_links, target_dir, taxonomy_names, base_path, language_codes, generated_routes, oracle)
            # Say it only where it changes how the result should be read: an
            # unusable tree explains dead internal links, a stale one explains
            # links it just accepted.
            output_hint = oracle.hint if !dead_internal.empty? || oracle.usable?

            total = external_links.size + internal_links.size
            dead_total = dead_external.size + dead_internal.size

            if json_output
              # `skipped_external` names the links the SSRF guard refused to
              # contact (private/localhost/.internal hosts). They used to be
              # silently absent from the payload, so a JSON consumer could
              # not tell "checked and healthy" from "never checked".
              puts({
                "dead_internal"    => dead_internal,
                "dead_external"    => dead_external,
                "skipped_external" => skipped_external,
                "ignored_count"    => ignored_count,
                # Null unless the build tree changed how this result should be
                # read (absent/serve output that could not validate pipeline
                # assets, or stale output that accepted some). The human line
                # is suppressed under --json, and CI is exactly where a run
                # against no build output is easiest to miss.
                "output_hint" => output_hint,
              }.to_json)
              # Exit non-zero so CI can gate on broken links (the JSON payload
              # has already been emitted to stdout for tooling to consume).
              exit(Hwaro::Errors::EXIT_GENERIC) if dead_total > 0
              return
            end

            scan_detail = "#{external_links.size} external · #{internal_links.size} internal"
            scan_detail += " · #{ignored_count} ignored" if ignored_count > 0
            Logger.section("scan", scan_detail)
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

            if hint = output_hint
              Logger.info "" if Logger.color_enabled?
              Logger.item(sanitize_for_terminal(hint), glyph: :info)
            end

            # A dead-links result must fail the process so `check-links` is
            # usable as a CI gate; previously it always exited 0 regardless of
            # how many broken links were reported.
            exit(Hwaro::Errors::EXIT_GENERIC) if dead_total > 0
          end

          # Compile an `--ignore-url` pattern: matched as a SUBSTRING of the
          # link URL as written, with `*` matching any run of characters.
          # Everything else is literal — dots in domains don't need escaping.
          # Matching is case-insensitive: URL hosts are case-insensitive, so
          # `--ignore-url twitter.com` must also silence `https://Twitter.com/…`.
          private def ignore_pattern_to_regex(pattern : String) : Regex
            Regex.new(pattern.split('*').map { |part| Regex.escape(part) }.join(".*"), Regex::Options::IGNORE_CASE)
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
          # Also stripped: HTML comments and indented (4-space/tab) code
          # blocks. Both hold example markup that is not a link — a
          # `<!-- <img src="/old.png"> -->` note and an indented
          # `<a href="/example/">` demo were each reported dead.
          #
          # Indented code is recognized conservatively, per CommonMark: a run
          # only counts as code when it follows a blank line AND no list item
          # is open. Without the list guard a 4-space list-item continuation
          # would be swallowed, which is exactly the failure that made the
          # sibling validator give up on indented blocks entirely.
          private def strip_code(content : String) : String
            result = String::Builder.new
            fence_char : Char? = nil
            fence_len = 0
            in_comment = false
            in_indented_code = false
            in_list = false
            prev_blank = true

            content.each_line(chomp: false) do |line|
              blank = line.strip.empty?

              # HTML comments span lines and can open/close mid-line.
              if in_comment
                if idx = line.index("-->")
                  in_comment = false
                  result << line[(idx + 3)..].gsub(/`[^`\n]*`/, "")
                else
                  result << '\n'
                end
                prev_blank = blank
                next
              end

              if m = line.match(/\A {0,3}(`{3,}|~{3,})/)
                marker = m[1]
                if fence_char.nil?
                  fence_char = marker[0]
                  fence_len = marker.size
                  in_indented_code = false
                  result << '\n'
                  prev_blank = false
                  next
                elsif marker[0] == fence_char && marker.size >= fence_len
                  fence_char = nil
                  fence_len = 0
                  result << '\n'
                  prev_blank = false
                  next
                end
              end

              if fence_char
                result << '\n'
                prev_blank = blank
                next
              end

              # Track list context so a 4-space continuation line is treated as
              # prose, not code.
              if line.matches?(/\A {0,3}(?:[-*+]|\d+[.)])\s/)
                in_list = true
              elsif blank
                # A blank line alone does not close a list; a subsequent
                # unindented non-list line does.
              elsif !line.starts_with?(" ") && !line.starts_with?("\t")
                in_list = false
              end

              indented = line.starts_with?("    ") || line.starts_with?("\t")
              if in_indented_code
                if blank || indented
                  result << '\n'
                  prev_blank = blank
                  next
                end
                in_indented_code = false
              elsif indented && prev_blank && !in_list && !blank
                in_indented_code = true
                result << '\n'
                prev_blank = false
                next
              end

              stripped = line.gsub(/`[^`\n]*`/, "")
              # A comment opened on this line: keep the text before it.
              if idx = stripped.index("<!--")
                if close = stripped.index("-->", idx)
                  stripped = stripped[0...idx] + stripped[(close + 3)..]
                else
                  in_comment = true
                  stripped = stripped[0...idx] + "\n"
                end
              end
              result << stripped
              prev_blank = blank
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

          # Markdown link/image destinations share LINK_DEST +
          # clean_external_target with the internal scan, so titled
          # (`[x](https://url "t")`) and angle-bracket (`[x](<https://url>)`)
          # external destinations are checked too — the old regex required
          # `)` right after the URL and silently skipped both forms.
          # Raw HTML (`<a href="https://…">`, `<img src="https://…">`) is also
          # scanned here: the internal HTML pass drops scheme-carrying URLs
          # via skip_internal?, so without this pass they were never checked.
          private def find_external_links(dir : String) : Array(Link)
            links = [] of Link
            link_regex = /!?\[[^\]]*?\]\(#{LINK_DEST.source}\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = readable_markdown(file) || next
              content.scan(link_regex) do |match|
                url = clean_external_target(match[1])
                next unless external_url?(url)
                links << Link.new(file: file, url: url, kind: :external)
              end
              scan_reference_definitions(content) do |raw|
                url = clean_external_target(raw)
                next unless external_url?(url)
                links << Link.new(file: file, url: url, kind: :external)
              end
              content.scan(HTML_TAG_RE) do |tag|
                tag[2].scan(HTML_ATTR_RE) do |attr|
                  raw = attr[2]? || attr[3]? || attr[4]?
                  next unless raw
                  html_link_targets(attr[1], raw).each do |candidate|
                    url = clean_external_target(candidate)
                    next unless external_url?(url)
                    # Unrendered template syntax — same guard as the internal
                    # HTML pass; contacting the literal braces is never right.
                    next if url.includes?("{{") || url.includes?("{%")
                    links << Link.new(file: file, url: url, kind: :external)
                  end
                end
              end
            end
            links
          end

          private def external_url?(url : String) : Bool
            url.starts_with?("http://") || url.starts_with?("https://")
          end

          # Read and code-strip one Markdown file, returning nil when the file
          # cannot be scanned. A file containing invalid UTF-8 makes PCRE2
          # raise `ArgumentError` mid-scan, which used to abort the whole run
          # with a bare "Error: Regex match error" and exit 1 — the same code
          # as "dead links found", so CI could not tell the two apart. Skip the
          # file with a warning instead, matching how `tool list` and
          # `tool validate` degrade on the same input.
          # Memoized per invocation: `run` scans the same tree twice (once for
          # external links, once for internal), and without this each file was
          # read and code-stripped twice — and an unreadable one warned twice.
          @scanned = {} of String => String?

          private def readable_markdown(file : String) : String?
            @scanned.fetch(file) { @scanned[file] = read_and_strip(file) }
          end

          private def read_and_strip(file : String) : String?
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
            clean_external_target(raw).split("#").first.split("?").first.strip
          end

          # The external half of clean_link_target: strip the optional title
          # and unwrap an angle-bracket destination, but KEEP query string and
          # fragment — they are significant when contacting an external URL.
          private def clean_external_target(raw : String) : String
            stripped = raw.strip
            if stripped.starts_with?('<') && (close = stripped.index('>'))
              stripped[1...close]
            else
              stripped.split(/\s/, 2).first
            end
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

              content.scan(HTML_TAG_RE) do |tag|
                kind = tag[1].downcase == "a" ? :internal : :image
                tag[2].scan(HTML_ATTR_RE) do |attr|
                  raw = attr[2]? || attr[3]? || attr[4]?
                  next unless raw
                  html_link_targets(attr[1], raw).each do |candidate|
                    url = clean_link_target(candidate)
                    next if skip_internal?(url) || url.includes?("{{") || url.includes?("{%")
                    links << Link.new(file: file, url: url, kind: kind)
                  end
                end
              end
            end
            links
          end

          # `<a href>` / `<img src|srcset>` / `<source src|srcset>` written
          # directly in Markdown. `<source>` matters because `<picture>` and
          # `<video>` blocks are the common hand-written HTML in docs content.
          # The value may be unquoted (`href=/x/`), which stops at whitespace
          # or `>`.
          # Matched in two passes — tag, then each attribute inside it — because
          # a single regex consumes the whole tag and so only ever reports the
          # FIRST link attribute: `<img srcset="…" src="…">` lost its `src`.
          HTML_TAG_RE  = /<(a|img|source)\b([^>]*)>/i
          HTML_ATTR_RE = /\b(href|src|srcset)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i

          # One `srcset` entry is `url [descriptor]`, comma-separated.
          private def html_link_targets(attribute : String, value : String) : Array(String)
            return [value] unless attribute.downcase == "srcset"
            value.split(',').compact_map do |candidate|
              url = candidate.strip.split(/\s+/).first?
              url if url && !url.empty?
            end
          end

          # A Markdown link reference definition (`[id]: /target/ "title"`).
          #
          # Three guards keep this from inventing links: footnote definitions
          # (`[^1]: …`) are skipped, the destination must look like a URL or
          # path, and — decisively — the label must actually be USED somewhere
          # in the document. Shape alone is not enough: the ordinary prose line
          #
          #     [Note]: /usr/bin is where the binary lives on most systems
          #
          # has a path-shaped first token and was reported as a dead link.
          # CommonMark only treats such a line as a definition when a matching
          # reference exists, so requiring one removes the whole false-positive
          # class rather than blacklisting shapes.
          REFERENCE_DEFINITION_RE = /^ {0,3}\[([^\]\n]+)\]:[ \t]*(\S+)/m

          # `[text][label]`, `[label][]`, and the shortcut form `[label]` — the
          # last excluding anything followed by `(`, `[` or `:`, which is an
          # inline link, a full reference, or another definition.
          REFERENCE_USE_RES = {
            /\]\[([^\]\n]+)\]/,
            /\[([^\]\n]+)\]\[\]/,
            /\[([^\]\n]+)\](?![\(\[:])/,
          }

          private def referenced_labels(content : String) : Set(String)
            labels = Set(String).new
            REFERENCE_USE_RES.each do |re|
              content.scan(re) { |m| labels << m[1].strip.downcase }
            end
            labels
          end

          private def scan_reference_definitions(content : String, &)
            used = referenced_labels(content)
            content.scan(REFERENCE_DEFINITION_RE) do |match|
              label = match[1]
              next if label.starts_with?('^')
              next unless used.includes?(label.strip.downcase)
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

          private def check_internal_links(links : Array(Link), content_dir : String, taxonomy_names : Array(String) = [] of String, base_path : String = "", language_codes : Array(String) = [] of String, generated_routes : GeneratedRoutes = GeneratedRoutes.new, oracle : Utils::BuildOutput::Oracle = Utils::BuildOutput.oracle("public", tool: "check-links")) : Array(Result)
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

              base_dir = File.dirname(link.file)

              # Resolve the URL exactly as written FIRST. A leading segment
              # that happens to match a language code may be a real section
              # (`content/ko/posts/`), and that section outranks any
              # translation reading — stripping unconditionally reported such
              # links dead even though the build publishes them.
              exists = resolves?(resolved_url, link, content_dir, base_dir, project_root, taxonomy_names, oracle) ||
                       generated_routes.matches?(resolved_url) ||
                       feed_route?(resolved_url, generated_routes, content_dir, base_dir, language_codes) ||
                       paginated_route?(resolved_url, link, content_dir, base_dir, taxonomy_names)

              # Only when the literal path fails do we read the URL as a
              # translation route (`/ko/about/` ← `content/about.ko.md`), and
              # then ONLY language-qualified evidence counts. Accepting the
              # default-language source here would pass `/ko/x/` for a site
              # that never translated `x` — a link the build emits nothing for.
              if !exists && (code = translatable_language_prefix(resolved_url, language_codes))
                stripped = resolved_url[(code.size + 1)..]
                stripped = "/" if stripped.empty?
                exists = translated_source?(stripped, code, link, content_dir, base_dir, taxonomy_names)
              end

              unless exists
                kind_label = link.kind == :image ? "Image not found" : "Internal link target not found"
                results << Result.new(link: link, status: -1, error: kind_label)
              end
            rescue ex : ArgumentError
              # A destination whose percent-encoding decodes to a byte no path
              # may contain (`/a%00b` → a real NUL) makes every `File.exists?`
              # probe in `resolves?` raise straight out of libc. Degrade PER
              # LINK — mirroring the per-file degradation `read_and_strip`
              # already does for invalid UTF-8 — so one hostile destination
              # cannot abort the whole run, hide the genuinely dead links in
              # the other files, or leave `--json` writing nothing at all to
              # stdout. The link itself is reported dead, which is exactly what
              # it is: the build cannot resolve it either.
              results << Result.new(link: link, status: -1, error: "Invalid link target: #{ex.message}")
            end
            results
          end

          # Routes the BUILD writes that have no source file to check against:
          # the sitemap, robots.txt, llms.txt, the search index and the feeds.
          #
          # Without this the checker only accepted them once `public/` existed,
          # so a `check-links` run in CI *before* `hwaro build` reported a
          # site's own `/rss.xml` and `/sitemap.xml` links dead — the exact
          # order a lint-then-build pipeline uses.
          struct GeneratedRoutes
            # Exact absolute paths (`/sitemap.xml`).
            getter paths : Set(String)
            # The feed filename, when feeds are enabled. Feeds are ALSO
            # emitted per section and per language (`/posts/rss.xml`,
            # `/ko/rss.xml`), so those are resolved by `feed_route?`, which
            # still requires the prefix to name a real section — matching the
            # bare basename anywhere would have declared `/nowhere/rss.xml`
            # live, hiding exactly the dead link this command exists to find.
            getter feed_filename : String?

            def initialize(@paths : Set(String) = Set(String).new, @feed_filename : String? = nil)
            end

            def matches?(url : String) : Bool
              url.starts_with?("/") && paths.includes?(url)
            end
          end

          private def generated_routes(config : Models::Config?) : GeneratedRoutes
            paths = Set(String).new
            # The build always synthesizes a 404 page.
            paths << "/404.html"
            return GeneratedRoutes.new(paths) unless config

            add_route = ->(filename : String) do
              name = File.basename(filename)
              paths << "/#{name}" unless name.empty?
            end

            add_route.call(config.sitemap.filename) if config.sitemap.enabled
            add_route.call(config.robots.filename) if config.robots.enabled
            add_route.call(config.llms.filename) if config.llms.enabled
            add_route.call(config.llms.full_filename) if config.llms.enabled && config.llms.full_enabled
            add_route.call(config.search.filename) if config.search.enabled

            feed_filename = nil
            if config.feeds.enabled
              name = config.feeds.filename.empty? ? default_feed_filename(config.feeds.type) : File.basename(config.feeds.filename)
              unless name.empty?
                paths << "/#{name}"
                feed_filename = name
              end
            end

            GeneratedRoutes.new(paths, feed_filename)
          end

          # `/posts/rss.xml` / `/ko/rss.xml` / `/ko/posts/rss.xml` — a feed the
          # build emits beside a section or under a language prefix. The root
          # feed is already an exact path, so this only has to vouch for the
          # prefixed forms, and only when the prefix resolves to a section.
          private def feed_route?(url : String, routes : GeneratedRoutes, content_dir : String, base_dir : String, language_codes : Array(String)) : Bool
            name = routes.feed_filename
            return false unless name
            return false unless url.starts_with?("/")
            return false unless File.basename(url) == name

            prefix = url[0, url.size - name.size].rstrip("/")
            return true if prefix.empty?

            segments = prefix.lstrip("/").split("/")
            if (code = segments.first?) && language_codes.includes?(code)
              segments = segments[1..]
              return true if segments.empty?
              prefix = "/#{segments.join("/")}"
            end

            !section_index_path(prefix, content_dir, base_dir).nil?
          end

          # Mirrors `Seo::Feeds.safe_feed_filename` for an unset filename.
          private def default_feed_filename(feed_type : String) : String
            feed_type.downcase == "atom" ? "atom.xml" : "rss.xml"
          end

          # `/posts/page/2/` — a paginated listing route. It exists only in the
          # output, so accept it when the URL minus its `/<paginate_path>/<n>/`
          # tail resolves to a section that actually paginates. The `/page/`
          # segment is trusted only for a real section, so an ordinary dead
          # `/foo/page/2/` still reports.
          private def paginated_route?(url : String, link : Link, content_dir : String, base_dir : String, taxonomy_names : Array(String)) : Bool
            return false if link.kind == :image
            match = url.match(/\A(.*)\/([^\/]+)\/(\d+)\/?\z/)
            return false unless match
            prefix = match[1]
            segment = match[2]
            prefix = "/" if prefix.empty?

            # Taxonomy term listings paginate too (`/tags/crystal/page/2/`).
            return true if segment == "page" && taxonomy_url?(prefix, taxonomy_names)

            index_path = section_index_path(prefix, content_dir, base_dir)
            return false unless index_path
            paginate_path, per_page = section_pagination(index_path)
            return false unless per_page
            return false unless segment == paginate_path

            number = match[3].to_i?
            return false unless number && number >= 1

            # Bound the page number by how many pages could possibly exist.
            # Accepting any N declared `/posts/page/99/` live on a two-page
            # section. The count is a deliberate OVER-estimate (every
            # descendant, drafts included), so the bound can never report a
            # link the build does publish.
            descendants = section_page_count(File.dirname(index_path))
            return true if descendants == 0
            number <= (descendants + per_page - 1) // per_page
          end

          # Upper bound on the pages a section can paginate: every Markdown
          # descendant that is not itself a section index.
          private def section_page_count(dir : String) : Int32
            count = 0
            Dir.glob(File.join(dir, "**", "*.{md,markdown}")) do |path|
              next if File.basename(path).starts_with?("_index.")
              count += 1
            end
            count
          end

          # Path of the `_index` file backing a section URL, if any.
          private def section_index_path(url : String, content_dir : String, base_dir : String) : String?
            base = content_target(url, content_dir, base_dir).rstrip("/")
            {"_index.md", "_index.markdown"}.each do |name|
              candidate = File.join(base, name)
              return candidate if File.exists?(candidate)
            end
            nil
          end

          # `{paginate_path, per_page}` for a section `_index` file. `per_page`
          # is nil unless the section declares a positive `paginate_by`, which
          # is what makes it produce `/page/N/` routes at all.
          private def section_pagination(index_path : String) : {String, Int32?}
            content = Utils::TextUtils.strip_bom(File.read(index_path))

            if match = content.match(Utils::FrontmatterScanner::TOML_FRONTMATTER_RE)
              data = TOML.parse(match[1])
              per_page = data["paginate_by"]?.try(&.raw).as?(Int64)
              path = data["paginate_path"]?.try(&.as_s?) || "page"
              return {path, positive_page_size(per_page)}
            elsif match = content.match(Utils::FrontmatterScanner::YAML_FRONTMATTER_RE)
              if h = YAML.parse(match[1]).as_h?
                per_page = h[YAML::Any.new("paginate_by")]?.try(&.as_i64?)
                path = h[YAML::Any.new("paginate_path")]?.try(&.as_s?) || "page"
                return {path, positive_page_size(per_page)}
              end
            elsif content.starts_with?('{') && (end_idx = Utils::FrontmatterScanner.find_json_end(content))
              if h = JSON.parse(content.byte_slice(0, end_idx)).as_h?
                per_page = h["paginate_by"]?.try(&.as_i64?)
                path = h["paginate_path"]?.try(&.as_s?) || "page"
                return {path, positive_page_size(per_page)}
              end
            end

            {"page", nil}
          rescue
            {"page", nil}
          end

          private def positive_page_size(value : Int64?) : Int32?
            return unless value && value > 0
            value.clamp(1_i64, Int32::MAX.to_i64).to_i32
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
          # names a non-default language the build can actually route, else
          # nil. The build matches filename suffixes against DECLARED codes
          # (ReadContent#extract_language_from_filename), so every declared
          # non-default code — including hyphenated ones like `pt-BR` —
          # produces `/<code>/…` routes.
          private def translatable_language_prefix(url : String, codes : Array(String)) : String?
            return if codes.empty?
            return unless url.starts_with?("/")
            segment = url.lstrip("/").split("/").first?
            return unless segment
            return unless codes.includes?(segment)
            segment
          end

          # Does `url` resolve to a source file, taxonomy route, or shipped
          # asset, read literally? This is the language-agnostic resolution the
          # checker has always performed.
          private def resolves?(url : String, link : Link, content_dir : String, base_dir : String,
                                project_root : String, taxonomy_names : Array(String),
                                oracle : Utils::BuildOutput::Oracle) : Bool
            target = content_target(url, content_dir, base_dir)
            # Most internal URLs are written with a trailing slash (`/about/`,
            # `/posts/hello/`) — strip it before computing the leaf-file
            # candidate so `target_no_slash + ".md"` resolves to
            # `content/about.md` instead of the broken `content/about/.md`.
            # The directory candidates work either way.
            target_no_slash = target.rstrip("/")

            return true if File.exists?(target) ||
                           File.exists?(target_no_slash + ".md") ||
                           File.exists?(target_no_slash + ".markdown") ||
                           File.exists?(File.join(target_no_slash, "_index.md")) ||
                           File.exists?(File.join(target_no_slash, "_index.markdown")) ||
                           File.exists?(File.join(target_no_slash, "index.md")) ||
                           File.exists?(File.join(target_no_slash, "index.markdown")) ||
                           (link.kind != :image && taxonomy_url?(url, taxonomy_names))

            # Also accept assets that live in static/ (source) or the build
            # output (after build): images under static/images/, resized/LQIP
            # variants the image pipeline emits, and anything published via
            # [content.files] or the asset pipeline. The output probe doubles
            # as the oracle for generated routes on an already-built site, and
            # follows `[build] output_dir` so a site that builds elsewhere is
            # not reported as one big pile of broken links — but only while
            # that tree is trustworthy: absent, empty and `hwaro serve` output
            # all answer false, and the run reports why (#761).
            asset_path = url.lstrip("/")
            File.exists?(File.join(project_root, "static", asset_path)) ||
              oracle.exists?(asset_path)
          end

          # Language-qualified resolution for a `/<code>/…` URL whose literal
          # path did not resolve. Deliberately narrow: only a `.<code>` source
          # or a taxonomy route counts, never the default-language file.
          private def translated_source?(url : String, code : String, link : Link,
                                         content_dir : String, base_dir : String,
                                         taxonomy_names : Array(String)) : Bool
            target_no_slash = content_target(url, content_dir, base_dir).rstrip("/")

            File.exists?("#{target_no_slash}.#{code}.md") ||
              File.exists?("#{target_no_slash}.#{code}.markdown") ||
              File.exists?(File.join(target_no_slash, "_index.#{code}.md")) ||
              File.exists?(File.join(target_no_slash, "_index.#{code}.markdown")) ||
              File.exists?(File.join(target_no_slash, "index.#{code}.md")) ||
              File.exists?(File.join(target_no_slash, "index.#{code}.markdown")) ||
              (link.kind != :image && taxonomy_url?(url, taxonomy_names))
          end

          # Map a link destination onto a path under the content directory.
          private def content_target(url : String, content_dir : String, base_dir : String) : String
            if url.starts_with?("@/")
              # Zola-style content-root link (`@/posts/hello.md`). The build
              # resolves these against the content dir, so the checker must too.
              File.join(content_dir, url[2..])
            elsif url.starts_with?("/")
              File.join(content_dir, url.lstrip("/"))
            else
              File.join(base_dir, url)
            end
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

          # Identical external URLs are checked ONCE and the outcome fanned
          # back out to every occurrence — 50 pages linking the same site used
          # to fire 50 simultaneous requests and collect 429 false positives.
          # The worker/channel accounting stays exact: one outcome per unique
          # URL from the pool, then one reported Result per occurrence (each
          # with its own file), in the caller's link order.
          private def check_links_concurrently(links : Array(Link), timeout_seconds : Int32, max_concurrency : Int32) : Array(Result)
            unique_urls = [] of String
            seen = Set(String).new
            links.each do |link|
              unique_urls << link.url if seen.add?(link.url)
            end

            outcomes = check_urls_concurrently(unique_urls, timeout_seconds, max_concurrency)

            links.map do |link|
              status, error_message = outcomes[link.url]
              Result.new(link: link, status: status, error: error_message)
            end
          end

          private def check_urls_concurrently(urls : Array(String), timeout_seconds : Int32, max_concurrency : Int32) : Hash(String, {Int32, String?})
            results_channel = Channel({String, Int32, String?}).new(urls.size)
            work_channel = Channel(String?).new(max_concurrency)

            # Spawn bounded worker pool.
            #
            # Exactly one result per dequeued URL — the same send-guarantee the
            # build's pools carry (see Core::Build::Parallel#process_parallel).
            # A raise here does not kill the process (Crystal's `Fiber#run`
            # prints `Unhandled exception in spawn` and carries on); it kills
            # this WORKER, which is worse: the collector below blocks on
            # `urls.size` receives with no timeout, so one lost result hangs
            # `hwaro tool check-links` forever. `check_external_url` rescues
            # its own network errors today — this makes surviving a raise a
            # property of the pool rather than of one callee.
            max_concurrency.times do
              spawn do
                while url = work_channel.receive?
                  status, error_message = begin
                    check_external_url(url, timeout_seconds)
                  rescue ex
                    # Pure construction — nothing here can raise — so the send
                    # below always runs, exactly once per dequeued URL.
                    {-1, ex.message || ex.class.name}
                  end
                  results_channel.send({url, status, error_message})
                end
              end
            end

            # Feed URLs to workers
            urls.each { |url| work_channel.send(url) }
            max_concurrency.times { work_channel.send(nil) }

            # Collect all results
            outcomes = {} of String => {Int32, String?}
            urls.size.times do
              url, status, error_message = results_channel.receive
              outcomes[url] = {status, error_message}
            end
            outcomes
          end

          # Check one external URL, following redirects. Returns
          # {status, error}. Redirect FAILURES (loop, missing Location,
          # exhausted time budget) report the -1 sentinel, never the redirect
          # code itself, so `--allow-status 301` only matches links whose
          # TERMINAL response is 301 — a broken redirect used to be classified
          # healthy by it.
          private def check_external_url(url : String, timeout_seconds : Int32) : {Int32, String?}
            error_message : String? = nil
            status = begin
              current_uri = URI.parse(url)
              method = "HEAD"
              redirects_left = 5
              response_status = -1
              # Total time budget for the whole redirect chain: each hop can
              # take up to the per-request timeout (HEAD may retry as GET),
              # so without this a slow chain multiplied the configured
              # --timeout by up to 12×. 3× leaves room for a slow-but-healthy
              # chain of a few hops while still bounding the worst case.
              # Int64 math: an absurd-but-accepted --timeout must not
              # overflow Int32 here and flip every link to "dead".
              deadline = Time.instant + (timeout_seconds.to_i64 * 3).seconds

              loop do
                host = current_uri.host
                # Non-ASCII (IDN) hosts are punycoded for DNS/connection;
                # the original URL is kept for reporting.
                connect_host = host ? ascii_host(host) : nil
                if connect_host && private_host?(connect_host)
                  error_message = "Skipped: private/internal address"
                  response_status = -1
                  break
                end

                request_uri = current_uri
                if host && connect_host && connect_host != host
                  request_uri = current_uri.dup
                  request_uri.host = connect_host
                end

                client = HTTP::Client.new(request_uri)
                client.connect_timeout = timeout_seconds.seconds
                client.read_timeout = timeout_seconds.seconds

                begin
                  headers = HTTP::Headers{"User-Agent" => "hwaro-link-checker/1.0"}
                  response = if method == "HEAD"
                               client.head(request_uri.request_target, headers: headers)
                             else
                               client.get(request_uri.request_target, headers: headers)
                             end

                  status_code = response.status_code

                  if {301, 302, 303, 307, 308}.includes?(status_code)
                    if redirects_left > 0
                      location = response.headers["Location"]?
                      if location
                        if Time.instant > deadline
                          error_message = "Request timed out (#{timeout_seconds}s): redirect chain exceeded the time budget"
                          response_status = -1
                          break
                        end
                        current_uri = current_uri.resolve(location)
                        # RFC 9110: 303 See Other is followed with GET.
                        method = "GET" if status_code == 303
                        redirects_left -= 1
                        next
                      else
                        error_message = "Redirect without Location header (#{status_code})"
                        response_status = -1
                        break
                      end
                    else
                      error_message = "Too many redirects (last status #{status_code})"
                      response_status = -1
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
            {status, error_message}
          end

          # RFC 3490 conversion for a host with non-ASCII labels
          # (`例え.jp` → `xn--r8jz45g.jp`) so DNS resolution and the
          # connection use the registrable form — such links used to fail
          # DNS and be reported dead.
          private def ascii_host(host : String) : String
            return host if host.ascii_only?
            URI::Punycode.to_ascii(host)
          rescue ArgumentError
            host
          end

          # Memoized per run: the same host used to be resolved synchronously
          # on every occurrence and every redirect hop, stalling all workers
          # on slow DNS. The cache is bounded by the finite host set of one
          # invocation. Resolution happens OUTSIDE the mutex so a slow lookup
          # for one host never serializes the others; a rare duplicate
          # resolution for the same host is benign.
          @private_host_cache = {} of String => Bool
          @private_host_cache_mutex = Mutex.new

          # Check if a hostname resolves to a private/internal IP address (SSRF protection).
          private def private_host?(host : String) : Bool
            @private_host_cache_mutex.synchronize do
              if @private_host_cache.has_key?(host)
                return @private_host_cache[host]
              end
            end
            result = resolve_private_host?(host)
            @private_host_cache_mutex.synchronize { @private_host_cache[host] = result }
            result
          end

          private def resolve_private_host?(host : String) : Bool
            return true if host == "localhost" || host.ends_with?(".local") || host.ends_with?(".internal")

            begin
              addrs = Socket::Addrinfo.resolve(host, 80, type: Socket::Type::STREAM)
              addrs.any? { |addr| private_ip_address?(addr.ip_address) }
            rescue Socket::Error
              false
            end
          end

          # Structured classification via Socket::IPAddress predicates — the
          # old string-prefix checks missed IPv4-mapped IPv6 loopback
          # (`::ffff:127.0.0.1`) and the fe81–febf link-local range. An
          # IPv4-mapped address is unmapped first because the stdlib
          # predicates only classify the mapped form as loopback, not as
          # private/link-local.
          private def private_ip_address?(ip : Socket::IPAddress) : Bool
            if mapped = ipv4_mapped_address(ip)
              return private_ip_address?(mapped)
            end
            ip.loopback? || ip.private? || ip.link_local? || ip.unspecified?
          end

          private def ipv4_mapped_address(ip : Socket::IPAddress) : Socket::IPAddress?
            return unless ip.family.inet6?
            address = ip.address
            return unless address.starts_with?("::ffff:") && address.includes?('.')
            Socket::IPAddress.new(address.lchop("::ffff:"), 0)
          rescue Socket::Error | ArgumentError
            nil
          end
        end
      end
    end
  end
end
