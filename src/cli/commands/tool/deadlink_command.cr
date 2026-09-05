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

require "./deadlink_command/scanner"
require "./deadlink_command/internal_resolver"
require "./deadlink_command/external_checker"

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
              Runner.exit_with_error_payload(err) if json_output
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
            project_root = Utils::PathUtils.find_project_root(target_dir)
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

          # Link URLs/paths come from semi-trusted content (e.g. a docs/blog
          # PR) and are printed to the maintainer's terminal in the report.
          # A URL carrying raw ANSI/control bytes (the link regex's `\s` does
          # not exclude ESC) could repaint or spoof the console. Strip control
          # characters before logging so the report can't inject escapes.
          private def sanitize_for_terminal(s : String) : String
            s.gsub { |c| c.control? ? "" : c }
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

          # Memoized per run: the same host used to be resolved synchronously
          # on every occurrence and every redirect hop, stalling all workers
          # on slow DNS. The cache is bounded by the finite host set of one
          # invocation. Resolution happens OUTSIDE the mutex so a slow lookup
          # for one host never serializes the others; a rare duplicate
          # resolution for the same host is benign.
          @private_host_cache = {} of String => Bool
          @private_host_cache_mutex = Mutex.new
        end
      end
    end
  end
end
