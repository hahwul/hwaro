# Remote scaffold class for fetching scaffolds from GitHub repositories
#
# Supports two source formats:
#   - github:owner/repo[/path]     (GitHub shorthand, optional subpath)
#   - https://github.com/owner/repo[/tree/branch/path]  (Full GitHub URL)
#
# Fetches config.toml, content/, templates/, static/, data/, i18n/ and
# archetypes/ from the repository (or subpath). Content files keep only
# front matter (metadata) so users can see the structure.

require "http/client"
require "json"
require "socket"
require "toml"
require "uri"
require "./base"
require "../../utils/errors"
require "../../utils/path_utils"

module Hwaro
  module Services
    module Scaffolds
      class Remote < Base
        @config_data : String
        @content_data : Hash(String, String)
        @template_data : Hash(String, String)
        @static_data : Hash(String, String)
        @shortcode_data : Hash(String, String)
        @description_text : String
        # Files outside the four built-in categories, keyed by their path
        # relative to the project root (`data/…`, `i18n/…`).
        @extra_data = {} of String => String
        @archetype_data = {} of String => String

        # Downloads in flight at once. Unbounded fan-out (one fiber per
        # file) ran a large scaffold out of file descriptors, and every
        # failed request used to become an empty file.
        FETCH_CONCURRENCY = 8

        # Content files the build reads as pages (`ReadContent::PAGE_EXTENSIONS`).
        CONTENT_EXTENSIONS = {".md", ".markdown"}

        # Root-level directories copied verbatim alongside the four
        # built-in categories. `data/` feeds sidebars/menus and `i18n/`
        # the translations, so a scaffold that relies on them built
        # without errors but rendered empty navigation.
        EXTRA_DIRS = {"data/", "i18n/"}

        # A parsed remote source. `branch` is nil unless the URL named one
        # (`/tree/<branch>/…`); the repository's default branch is used then.
        record Source, owner : String, repo : String, subpath : String, branch : String? = nil do
          def label : String
            subpath.empty? ? "#{owner}/#{repo}" : "#{owner}/#{repo}/#{subpath}"
          end
        end

        def initialize(source : String)
          parsed = self.class.parse(source)
          @description_text = "Remote scaffold from #{parsed.label}"
          @config_data = ""
          @content_data = {} of String => String
          @template_data = {} of String => String
          @static_data = {} of String => String
          @shortcode_data = {} of String => String
          fetch!(parsed)
        end

        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Simple
        end

        def description : String
          @description_text
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          @content_data
        end

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          @template_data
        end

        def static_files : Hash(String, String)
          @static_data
        end

        def shortcode_files : Hash(String, String)
          @shortcode_data
        end

        # Remote scaffolds mirror the upstream repo verbatim; we don't
        # inject a built-in `default.md` because the remote might deliberately
        # not use archetypes. Its own `archetypes/` is carried over.
        def archetype_files : Hash(String, String)
          @archetype_data
        end

        def extra_files : Hash(String, String)
          @extra_data
        end

        # Remote content is already reduced to front matter; skipping it
        # leaves content/ empty, as it always has.
        protected def skeleton_page_paths : Array(String)
          [] of String
        end

        def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          @config_data
        end

        # If the remote provided a config.toml, use it as-is (even for --minimal-config).
        # If not (remote can be templates-only), fall back to the built-in minimal generator.
        def minimal_config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          if @config_data.strip.empty?
            super
          else
            @config_data
          end
        end

        # Check if a scaffold source string represents a remote scaffold
        def self.remote?(source : String) : Bool
          source.starts_with?("github:") ||
            source.starts_with?("git:") ||
            source.starts_with?("https://") ||
            source.starts_with?("http://")
        end

        # Parse a remote source string into {owner, repo, subpath}
        def self.parse_source(source : String) : {String, String, String}
          parsed = parse(source)
          {parsed.owner, parsed.repo, parsed.subpath}
        end

        # Parse a remote source string, keeping the branch a
        # `/tree/<branch>/…` URL names.
        def self.parse(source : String) : Source
          # `git://github.com/owner/repo` is a protocol URL, not the `git:owner/repo`
          # shorthand — route it to the URL parser below, which handles it correctly.
          if source.starts_with?("github:") || (source.starts_with?("git:") && !source.starts_with?("git://"))
            raw = source.sub(/^(?:github|git):/, "")
            parts = raw.split("/")
            if parts.size < 2 || parts[0].empty? || parts[1].empty?
              raise ArgumentError.new("Invalid GitHub shorthand: #{source}. Expected format: github:owner/repo[/path]")
            end
            # Empty segments (a trailing or doubled slash) would otherwise
            # make the subpath prefix `docs//`, which matches nothing.
            Source.new(parts[0], strip_git_suffix(parts[1]), parts[2..].reject(&.empty?).join("/"))
          else
            uri = URI.parse(source)
            unless uri.host.try { |h| h = h.downcase; h == "github.com" || h.ends_with?(".github.com") }
              raise ArgumentError.new("Only GitHub URLs are supported. Got: #{source}")
            end
            # Segments are decoded: the browser's `/tree/main/my%20site` names
            # the `my site` directory the tree listing reports.
            path_parts = (uri.path || "/").split("/").reject(&.empty?).map { |seg| URI.decode(seg) }
            if path_parts.size < 2
              raise ArgumentError.new("Invalid GitHub URL: #{source}. Expected format: https://github.com/owner/repo")
            end
            owner = path_parts[0]
            repo = strip_git_suffix(path_parts[1])
            # Handle /tree/branch/subpath or /blob/branch/subpath patterns
            if path_parts.size > 3 && (path_parts[2] == "tree" || path_parts[2] == "blob")
              Source.new(owner, repo, path_parts[4..].join("/"), path_parts[3])
            else
              # Direct path: https://github.com/owner/repo/subpath
              Source.new(owner, repo, path_parts[2..].join("/"))
            end
          end
        end

        private def self.strip_git_suffix(repo : String) : String
          stripped = repo.rchop(".git")
          stripped.empty? ? repo : stripped
        end

        # Every `{branch, subpath}` split of a `/tree/<a>/<b>/<c>` URL, the
        # shortest branch first: GitHub branch names may contain `/`
        # (`feature/x`), and the URL alone cannot say where the branch ends.
        def self.ref_candidates(branch : String, subpath : String) : Array({String, String})
          segments = subpath.split('/').reject(&.empty?)
          (0..segments.size).map do |i|
            {([branch] + segments[0, i]).join("/"), segments[i..].join("/")}
          end
        end

        # Map a repository path (relative to the scaffold root) to the
        # category it is installed under, or nil to skip it.
        def self.classify(path : String) : {Symbol, String}?
          return {:config, ""} if path == "config.toml"

          category, rel = if path.starts_with?("content/")
                            return unless CONTENT_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
                            {:content, path.lchop("content/")}
                          elsif path.starts_with?("templates/shortcodes/")
                            {:shortcode, path.lchop("templates/")}
                          elsif path.starts_with?("templates/")
                            {:template, path.lchop("templates/")}
                          elsif path.starts_with?("static/")
                            {:static, path.lchop("static/")}
                          elsif path.starts_with?("archetypes/")
                            {:archetype, path.lchop("archetypes/")}
                          elsif EXTRA_DIRS.any? { |dir| path.starts_with?(dir) }
                            # Kept root-relative: `data/menu.yml` stays `data/menu.yml`.
                            {:extra, path}
                          else
                            return
                          end

          key = Utils::PathUtils.sanitize_path(rel)
          return if key.empty?
          category == :extra && !EXTRA_DIRS.any? { |dir| key.starts_with?(dir) } ? nil : {category, key}
        end

        private def fetch!(source : Source)
          owner, repo = source.owner, source.repo
          label = source.label
          Logger.info "Fetching remote scaffold from #{label}..."

          branch, subpath, tree = resolve_tree(source)
          Logger.info "Using branch: #{branch}"

          prefix = subpath.empty? ? "" : "#{subpath}/"

          # Collect files to download
          targets = [] of {category: Symbol, key: String, full_path: String, display: String}

          tree.each do |entry|
            full_path = entry["path"]?.try(&.as_s?)
            next unless full_path
            next unless entry["type"]?.try(&.as_s?) == "blob"

            unless prefix.empty?
              next unless full_path.starts_with?(prefix)
            end

            path = full_path.lchop(prefix)
            if classified = self.class.classify(path)
              category, key = classified
              targets << {category: category, key: key, full_path: full_path, display: path}
            end
          end

          if targets.empty?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "No scaffold files found in #{label}.",
              hint: "Remote scaffolds must contain a config.toml, templates/, static/, or content/ directory.",
            )
          end

          # Download through a bounded pool of fibers. A failed download is
          # never written as an empty file — a half-fetched scaffold that
          # exits 0 looks like a broken theme, not a network problem — and
          # nothing has touched the target directory yet, so the whole run
          # fails instead.
          queue = Channel({category: Symbol, key: String, full_path: String, display: String}).new(targets.size)
          targets.each { |target| queue.send(target) }
          queue.close

          results = Channel({category: Symbol, key: String, display: String, body: String?, error: String?}).new(targets.size)
          Math.min(FETCH_CONCURRENCY, targets.size).times do
            spawn do
              while target = queue.receive?
                body = nil
                error = nil
                # One retry: a transient reset should not sink the scaffold.
                2.times do
                  body = fetch_file(owner, repo, branch, target[:full_path])
                  error = nil
                  break
                rescue ex
                  error = ex.message || ex.class.name
                end
                results.send({category: target[:category], key: target[:key], display: target[:display], body: body, error: error})
              end
            end
          end

          failed = [] of String
          targets.size.times do
            result = results.receive
            body = result[:body]
            if body.nil?
              failed << "#{result[:display]} (#{result[:error]})"
              next
            end
            case result[:category]
            when :config
              @config_data = body
            when :content
              @content_data[result[:key]] = extract_front_matter(body)
            when :shortcode
              @shortcode_data[result[:key]] = body
            when :template
              @template_data[result[:key]] = body
            when :static
              @static_data[result[:key]] = body
            when :archetype
              @archetype_data[result[:key]] = body
            when :extra
              @extra_data[result[:key]] = body
            end
            Logger.action :fetch, result[:display]
          end

          unless failed.empty?
            shown = failed.sort.first(5).join(", ")
            more = failed.size > 5 ? " (and #{failed.size - 5} more)" : ""
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_NETWORK,
              message: "Failed to fetch #{failed.size} of #{targets.size} file(s) from #{label}: #{shown}#{more}",
              hint: "Nothing was written. Check your network connection (and GITHUB_TOKEN for a private repository), then try again.",
            )
          end

          Logger.info "Fetched #{targets.size} files from remote scaffold."

          warn_dangerous_config(@config_data, label) unless @config_data.empty?
        end

        # The branch, subpath and recursive tree to scaffold from. A branch
        # named in the URL is honoured (it used to be dropped in favour of the
        # default branch); since branch names may contain `/`, each split of
        # the URL path is tried until GitHub knows the ref.
        private def resolve_tree(source : Source) : {String, String, Array(JSON::Any)}
          owner, repo = source.owner, source.repo
          if named = source.branch
            self.class.ref_candidates(named, source.subpath).each do |candidate, subpath|
              if tree = fetch_tree(owner, repo, candidate, missing_ok: true)
                return {candidate, subpath, tree}
              end
            end
            # GitHub answers 404 for a missing or private repository too;
            # the repo lookup raises the right "not found / is it public?"
            # error before blaming the branch.
            fetch_default_branch(owner, repo)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_NETWORK,
              message: "Branch '#{named}' not found in #{owner}/#{repo}",
              hint: "Check the branch name in the URL, or drop /tree/<branch>/ to use the default branch.",
            )
          end

          branch = fetch_default_branch(owner, repo)
          tree = fetch_tree(owner, repo, branch) || raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_NETWORK,
            message: "Failed to fetch repository tree for #{owner}/#{repo}@#{branch}",
          )
          {branch, source.subpath, tree}
        end

        # Settings in a remote config.toml that run shell commands:
        # `[build.hooks] pre`/`post` and every deploy target's `command`.
        # Read from the parsed document — a text match on `hooks.pre =`
        # missed the `[build.hooks]` table form the loader actually reads.
        def self.dangerous_settings(config_data : String) : Array(String)
          dangerous = [] of String
          begin
            doc = TOML.parse(config_data)
          rescue
            # Unparseable: the build will reject it anyway, but fall back to
            # a textual scan so a hostile file cannot dodge the warning by
            # being slightly malformed.
            dangerous << "build hooks (hooks.pre / hooks.post)" if config_data.matches?(/\b(?:pre|post)\s*=/m) && config_data.includes?("hooks")
            dangerous << "deploy commands (command)" if config_data.matches?(/\bcommand\s*=/m)
            return dangerous
          end

          hooks = doc["build"]?.try(&.as_h?).try(&.["hooks"]?).try(&.as_h?)
          if hooks && (hooks.has_key?("pre") || hooks.has_key?("post"))
            dangerous << "build hooks (hooks.pre / hooks.post)"
          end

          targets = doc["deployment"]?.try(&.as_h?).try(&.["targets"]?).try(&.as_a?)
          if targets && targets.any? { |t| t.as_h?.try(&.has_key?("command")) }
            dangerous << "deploy commands (command)"
          end
          dangerous
        end

        # Warn the user if a remote scaffold's config.toml contains settings
        # that can execute arbitrary commands (build hooks, deploy commands).
        private def warn_dangerous_config(config_data : String, label : String)
          dangerous = self.class.dangerous_settings(config_data)
          return if dangerous.empty?

          Logger.warn "Security warning: remote scaffold '#{label}' contains config that can execute shell commands:"
          dangerous.each { |d| Logger.warn "  - #{d}" }
          Logger.warn "Review config.toml carefully before running 'hwaro build' or 'hwaro deploy'."
        end

        private def fetch_default_branch(owner : String, repo : String) : String
          response = github_api_get("/repos/#{owner}/#{repo}")

          unless response.status_code == 200
            case response.status_code
            when 404
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_NETWORK,
                message: "Remote scaffold not found: #{owner}/#{repo}",
                hint: "Check the repository name and that it is public.",
              )
            when 403
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_NETWORK,
                message: "GitHub API rate limit exceeded while fetching #{owner}/#{repo}",
                hint: "Try again later or set GITHUB_TOKEN for higher limits.",
              )
            else
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_NETWORK,
                message: "Failed to fetch repository info for #{owner}/#{repo}: HTTP #{response.status_code}",
              )
            end
          end

          data = JSON.parse(response.body)
          data["default_branch"]?.try(&.as_s?) || raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_NETWORK,
            message: "GitHub repo info for #{owner}/#{repo} is missing 'default_branch'",
          )
        end

        # The recursive tree at `branch`, or nil when `missing_ok` and GitHub
        # does not know the ref (404/422) — `resolve_tree` probes several
        # splits of a `/tree/<branch>/…` URL that way.
        private def fetch_tree(owner : String, repo : String, branch : String, missing_ok : Bool = false) : Array(JSON::Any)?
          response = github_api_get("/repos/#{owner}/#{repo}/git/trees/#{encode_path(branch)}?recursive=1")

          return if missing_ok && (response.status_code == 404 || response.status_code == 422)
          unless response.status_code == 200
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_NETWORK,
              message: "Failed to fetch repository tree for #{owner}/#{repo}@#{branch}: HTTP #{response.status_code}",
            )
          end

          data = JSON.parse(response.body)
          # GitHub sets `truncated` when the recursive tree exceeds its size
          # limit and returns a PARTIAL listing — warn so silently-dropped
          # scaffold files don't read as a clean checkout.
          if data["truncated"]?.try(&.as_bool?)
            Logger.warn "GitHub truncated the recursive tree for #{owner}/#{repo}@#{branch}; the scaffold may be incomplete (large repository)."
          end
          data["tree"]?.try(&.as_a?) || raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_NETWORK,
            message: "GitHub tree response for #{owner}/#{repo}@#{branch} is missing 'tree'",
          )
        end

        # Raises on anything but a 200 so the caller can retry and, failing
        # that, abort the scaffold instead of writing an empty file.
        private def fetch_file(owner : String, repo : String, branch : String, path : String) : String
          tls = OpenSSL::SSL::Context::Client.new
          client = HTTP::Client.new("raw.githubusercontent.com", 443, tls: tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds

          # Percent-encode per segment: a raw `#`, `?` or space in a file
          # name truncated the request to a different (or no) file.
          target = "/#{encode_path(owner)}/#{encode_path(repo)}/#{encode_path(branch)}/#{encode_path(path)}"
          headers = HTTP::Headers{"User-Agent" => "Hwaro"}
          # The token that let the API list a private repository's tree has
          # to reach the raw host too, or every file comes back 404.
          if token = ENV["GITHUB_TOKEN"]?
            headers["Authorization"] = "Bearer #{token}"
          end

          begin
            response = client.get(target, headers: headers)
            raise "HTTP #{response.status_code}" unless response.status_code == 200
            response.body
          ensure
            client.close
          end
        end

        private def encode_path(path : String) : String
          path.split('/').join('/') { |segment| URI.encode_path_segment(segment) }
        end

        private def github_api_get(path : String) : HTTP::Client::Response
          tls = OpenSSL::SSL::Context::Client.new
          client = HTTP::Client.new("api.github.com", 443, tls: tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds

          headers = HTTP::Headers{
            "User-Agent" => "Hwaro",
            "Accept"     => "application/vnd.github.v3+json",
          }
          if token = ENV["GITHUB_TOKEN"]?
            headers["Authorization"] = "Bearer #{token}"
          end

          begin
            client.get(path, headers: headers)
          rescue ex : Socket::Error | IO::Error | OpenSSL::SSL::Error
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_NETWORK,
              message: "Failed to reach GitHub API (#{path}): #{ex.message}",
              hint: "Check your network connection and try again.",
            )
          ensure
            client.close
          end
        end
      end
    end
  end
end
