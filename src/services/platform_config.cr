require "json"
require "../hwaro"
require "../models/config"
require "../models/page"
require "../content/processors/markdown"
require "../utils/frontmatter_writer"
require "../utils/logger"
require "./github_actions_workflow"

module Hwaro
  module Services
    class PlatformConfig
      SUPPORTED_PLATFORMS = ["netlify", "vercel", "cloudflare", "github-pages", "gitlab-ci", "codeberg-pages"]

      @config : Models::Config

      @output_dir : String? = nil

      def initialize(@config : Models::Config)
      end

      def generate(platform : String) : String
        case platform
        when "netlify"
          generate_netlify
        when "vercel"
          generate_vercel
        when "cloudflare"
          generate_cloudflare
        when "github-pages"
          generate_github_pages
        when "gitlab-ci"
          generate_gitlab_ci
        when "codeberg-pages"
          generate_codeberg_pages
        else
          raise "Unsupported platform: #{platform}. Supported: #{SUPPORTED_PLATFORMS.join(", ")}"
        end
      end

      def output_filename(platform : String) : String
        case platform
        when "netlify"        then "netlify.toml"
        when "vercel"         then "vercel.json"
        when "cloudflare"     then "wrangler.toml"
        when "github-pages"   then ".github/workflows/deploy.yml"
        when "gitlab-ci"      then ".gitlab-ci.yml"
        when "codeberg-pages" then ".forgejo/workflows/deploy.yml"
        else                       raise "Unsupported platform: #{platform}"
        end
      end

      private def build_command : String
        "hwaro build"
      end

      # Directory the build writes to. Follows `[build] output_dir` so every
      # generated platform config publishes the tree `hwaro build` actually
      # produced — a hardcoded "public" made a site with a customized
      # output_dir deploy an empty (or stale) directory, with no error
      # anywhere: the build succeeded and the host published nothing.
      # `Config.load` rejects an empty or project-escaping value, but passes
      # `./public`, `public/` and absolute paths through verbatim. Normalize
      # here so every emitted key gets one clean relative spelling
      # (cloudflare's `bucket = "./#{dir}"` produced `././public`, gitlab's
      # default check missed `./public`); an absolute path is not expressible
      # in any hosted-build config (netlify `publish`, gitlab `artifacts.paths`
      # must be project-relative), so it is reported and the conventional
      # `public` used — the host would otherwise publish nothing, silently.
      private def output_dir : String
        @output_dir ||= begin
          raw = @config.build.output_dir
          if raw.nil?
            "public"
          elsif Path[raw].absolute?
            Logger.warn "[build] output_dir #{raw.inspect} is an absolute path; platform configs need a project-relative directory. Using \"public\" — set a relative output_dir so the host publishes what hwaro built."
            "public"
          else
            normalized = Path[raw].normalize.to_s.lchop("./").rstrip('/')
            normalized.empty? || normalized == "." ? "public" : normalized
          end
        end
      end

      # Render a value as a shell word, leaving ordinary directory names bare
      # so the default workflow is unchanged. `[build] output_dir` is trusted
      # config, but it may legitimately contain a space — unquoted, that would
      # split into two `cd` arguments.
      private def shell_word(value : String) : String
        return value if value.matches?(/\A[A-Za-z0-9._\/-]+\z/)
        "'" + value.gsub("'", "'\\''") + "'"
      end

      # Escape a value for a TOML basic string. Front-matter aliases are
      # arbitrary user input; an unescaped quote/backslash — or a raw control
      # character such as a newline — would produce an unparseable
      # netlify.toml. Control characters are ESCAPED rather than the alias
      # skipped (the cloudflare generator skips because `_redirects` has no
      # escape syntax; TOML does, so the user's redirect is preserved).
      private def toml_escape(s : String) : String
        String.build do |io|
          s.each_char do |char|
            case char
            when '\\' then io << "\\\\"
            when '"'  then io << "\\\""
            when '\n' then io << "\\n"
            when '\t' then io << "\\t"
            when '\r' then io << "\\r"
            when '\b' then io << "\\b"
            when '\f' then io << "\\f"
            else
              if char.control?
                # TOML `\u` takes exactly four hex digits; codepoints above
                # U+FFFF (e.g. Cf tag characters) need the 8-digit `\U` form.
                if char.ord > 0xFFFF
                  io << "\\U" << char.ord.to_s(16).upcase.rjust(8, '0')
                else
                  io << "\\u" << char.ord.to_s(16).upcase.rjust(4, '0')
                end
              else
                io << char
              end
            end
          end
        end
      end

      private def generate_netlify : String
        lines = [] of String
        lines << "[build]"
        lines << "  command = \"#{build_command}\""
        lines << "  publish = \"#{toml_escape(output_dir)}\""
        lines << ""
        lines << "[build.environment]"
        lines << "  # Add environment variables here"
        lines << "  # HWARO_VERSION = \"#{Hwaro::VERSION}\""

        # Redirects from aliases
        redirects = collect_aliases
        unless redirects.empty?
          lines << ""
          redirects.each do |from, to|
            lines << "[[redirects]]"
            lines << "  from = \"#{toml_escape(from)}\""
            lines << "  to = \"#{toml_escape(to)}\""
            lines << "  status = 301"
            lines << "  force = true"
            lines << ""
          end
        end

        # Headers for caching. Target the configured asset output dir rather
        # than a hardcoded /assets/ so a customized [assets] output_dir is honored.
        lines << "[[headers]]"
        lines << "  for = \"#{with_base_path("/#{assets_url_dir}/*")}\""
        lines << "  [headers.values]"
        lines << "    Cache-Control = \"public, max-age=31536000, immutable\""

        lines.join("\n") + "\n"
      end

      # Prefix a site-internal path with the configured `base_path` so generated
      # redirects/headers resolve under a subpath deployment, matching the
      # build's own redirect HTML. Normalizes to a leading slash first because
      # Config#with_base_path only prefixes root-relative paths (aliases may be
      # authored without one). A no-op when base_path is empty.
      private def with_base_path(path : String) : String
        normalized = path.starts_with?("/") ? path : "/#{path}"
        @config.with_base_path(normalized)
      end

      # URL path segment where the asset pipeline emits fingerprinted files,
      # derived from config (default "assets") so cache rules follow the
      # configured [assets] output_dir.
      private def assets_url_dir : String
        dir = @config.assets.output_dir.strip("/")
        dir.empty? ? "assets" : dir
      end

      private def generate_vercel : String
        config_hash = {} of String => JSON::Any

        # Redirects from aliases
        redirects = collect_aliases
        unless redirects.empty?
          redirect_entries = redirects.map do |from, to|
            JSON::Any.new({
              "source"      => JSON::Any.new(from),
              "destination" => JSON::Any.new(to),
              "statusCode"  => JSON::Any.new(301_i64),
            })
          end
          config_hash["redirects"] = JSON::Any.new(redirect_entries)
        end

        # Headers for caching
        header_entries = [
          JSON::Any.new({
            "source"  => JSON::Any.new(with_base_path("/#{assets_url_dir}/(.*)")),
            "headers" => JSON::Any.new([
              JSON::Any.new({
                "key"   => JSON::Any.new("Cache-Control"),
                "value" => JSON::Any.new("public, max-age=31536000, immutable"),
              }),
            ]),
          }),
        ]
        config_hash["headers"] = JSON::Any.new(header_entries)

        result = {
          "buildCommand"    => JSON::Any.new(build_command),
          "outputDirectory" => JSON::Any.new(output_dir),
        }

        config_hash.each { |k, v| result[k] = v }

        JSON::Any.new(result).to_pretty_json + "\n"
      end

      private def generate_cloudflare : String
        project_name = @config.title.downcase.gsub(/[^a-z0-9\-]/, "-").gsub(/-+/, "-").strip("-")
        project_name = "my-site" if project_name.empty?

        lines = [] of String
        lines << "name = \"#{project_name}\""
        lines << "compatibility_date = \"#{Time.utc.to_s("%Y-%m-%d")}\""
        lines << ""
        lines << "[site]"
        lines << "  bucket = \"./#{toml_escape(output_dir)}\""
        lines << ""
        lines << "# Build configuration (for Cloudflare Pages dashboard)"
        lines << "# Build command: #{build_command}"
        lines << "# Build output directory: /#{output_dir}"

        # Redirects via _redirects file note
        redirects = collect_aliases
        unless redirects.empty?
          lines << ""
          lines << "# Redirects: Create a `#{output_dir}/_redirects` file with:"
          redirects.each do |from, to|
            # _redirects is space-delimited; an alias with whitespace or a quote
            # would silently corrupt the rule, so skip malformed entries.
            next if from.matches?(/\s|"/) || to.matches?(/\s|"/)
            lines << "# #{from} #{to} 301"
          end
        end

        lines.join("\n") + "\n"
      end

      private def generate_github_pages : String
        GithubActionsWorkflow.content
      end

      private def generate_gitlab_ci : String
        lines = [] of String
        lines << "image:"
        lines << "  name: ghcr.io/hahwul/hwaro:latest"
        lines << "  entrypoint: [\"\"]"
        lines << ""
        lines << "pages:"
        lines << "  stage: deploy"
        lines << "  script:"
        lines << "    - hwaro build"
        # GitLab Pages defaults to publishing `public/`; `pages.publish`
        # (GitLab 16.1+) points it elsewhere. Emitted only for a customized
        # `[build] output_dir` so the default pipeline stays compatible with
        # older GitLab instances.
        lines << "  publish: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(output_dir)}" unless output_dir == "public"
        lines << "  artifacts:"
        lines << "    paths:"
        lines << "      - #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(output_dir)}"
        lines << "  rules:"
        lines << "    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH"
        lines << ""

        lines.join("\n")
      end

      # Forgejo Actions workflow that builds the site and force-pushes the
      # generated `public/` directory to the configured pages branch.
      #
      # Codeberg Pages publishes:
      #   - Project site: a branch named `pages` in any repo →
      #     https://USER.codeberg.page/REPO/  (default of this workflow).
      #   - User/org site: the *default* branch of a repo named `pages` →
      #     https://USER.codeberg.page/. Override `PAGES_BRANCH` to e.g.
      #     `main` to target a user site without forking the workflow.
      #
      # Each run starts with a fresh `git init`, so commit history on the
      # pages branch is intentionally not preserved — the branch is treated
      # as a publish-only artifact. Auth uses the token-form remote URL so
      # no SSH keys need to be preconfigured on the runner; the token must
      # be supplied via the `CODEBERG_TOKEN` repository secret.
      private def generate_codeberg_pages : String
        lines = [] of String
        lines << "---"
        lines << "name: Hwaro Deploy"
        lines << ""
        lines << "on:"
        lines << "  push:"
        lines << "    branches: [main]"
        lines << "  workflow_dispatch:"
        lines << ""
        lines << "jobs:"
        lines << "  deploy:"
        lines << "    runs-on: docker"
        lines << "    container:"
        lines << "      image: ghcr.io/hahwul/hwaro:latest"
        lines << "    env:"
        lines << "      # Project site: \"pages\" (default). User/org site (repo named"
        lines << "      # \"pages\"): override to your default branch, e.g. \"main\"."
        lines << "      PAGES_BRANCH: pages"
        lines << "    steps:"
        lines << "      - name: Checkout"
        lines << "        uses: actions/checkout@v4"
        lines << ""
        lines << "      - name: Build site"
        lines << "        run: #{build_command}"
        lines << ""
        lines << "      - name: Deploy to Codeberg Pages"
        lines << "        env:"
        lines << "          CODEBERG_TOKEN: ${{ secrets.CODEBERG_TOKEN }}"
        lines << "        run: |"
        lines << "          cd #{shell_word(output_dir)}"
        lines << "          git init -b \"$PAGES_BRANCH\""
        lines << "          git config user.name  \"${{ github.actor }}\""
        lines << "          git config user.email \"${{ github.actor }}@noreply.codeberg.org\""
        lines << "          git add -A"
        lines << "          git commit -m \"Deploy: $(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
        lines << "          git push --force \\"
        lines << "            \"https://${{ github.actor }}:$CODEBERG_TOKEN@codeberg.org/${{ github.repository }}.git\" \\"
        lines << "            \"$PAGES_BRANCH\""
        lines << ""

        lines.join("\n")
      end

      # Collect alias -> target URL pairs by parsing content files using
      # the existing Markdown frontmatter parser and URL calculation logic.
      private def collect_aliases : Array(Tuple(String, String))
        redirects = [] of Tuple(String, String)

        content_dir = "content"
        return redirects unless Dir.exists?(content_dir)

        scan_content_for_aliases(content_dir, redirects)
        redirects
      end

      # Page extensions mirror Core::Build::Phases::ReadContent::PAGE_EXTENSIONS
      # so alias generation sees exactly the pages the build publishes.
      PAGE_EXTENSIONS = {".md", ".markdown"}

      private def scan_content_for_aliases(dir : String, redirects : Array(Tuple(String, String)))
        # An unreadable subdirectory (Dir.each_child raises on entry) skips
        # that subtree with a warning instead of aborting the whole run.
        children = begin
          Dir.children(dir)
        rescue ex : File::Error
          Logger.warn "Skipping unreadable directory during alias scan: #{dir} (#{ex.message})"
          return
        end
        children.each do |entry|
          path = File.join(dir, entry)
          # `follow_symlinks: false` keeps a symlinked directory (including a
          # cycle like `ln -s . content/loop`) from being recursed into —
          # following one used to recurse until ELOOP aborted the whole
          # command. Symlinked FILES still work: they fall through to the
          # extension branch and File.read follows the link as usual.
          info = File.info?(path, follow_symlinks: false)
          next unless info
          if info.directory?
            scan_content_for_aliases(path, redirects)
          elsif PAGE_EXTENSIONS.includes?(Path[entry].extension.downcase)
            extract_aliases_from_file(path, redirects)
          end
        end
      end

      # Mirror of ReadContent#extract_language_from_filename: the suffix
      # between the last two dots is matched against DECLARED language codes
      # (plus the default), so declared keys like `zh-tw`/`pt-BR` route the
      # same way here as in the build.
      private def extract_language_from_filename(basename : String) : String?
        return unless @config.multilingual?

        ext = Path[basename].extension.downcase
        return unless PAGE_EXTENSIONS.includes?(ext)
        return unless basename.size > ext.size

        stem = basename[0, basename.size - ext.size]
        idx = stem.rindex('.')
        return unless idx && idx > 0
        lang_code = stem[(idx + 1)..]
        return if lang_code.empty?
        return lang_code if @config.languages.has_key?(lang_code) || lang_code == @config.default_language

        nil
      end

      private def extract_aliases_from_file(path : String, redirects : Array(Tuple(String, String)))
        raw_content = File.read(path)
        data = Processor::Markdown.parse(raw_content, path)
        # Mirror the build's publish filter: drafts, headless pages, and
        # outside-window (future/expired) content write no output and must
        # not fail platform generation over a date-token permalink they
        # never ship (build uses resolve_url_lenient + raise only on
        # surviving render=true pages).
        return if data[:draft]
        return unless data[:render]
        now = Time.utc
        if exp = data[:expires]
          return if exp <= now
        end
        if date = data[:date]
          return if date > now
        end

        aliases = data[:aliases]
        return if aliases.empty?

        # Build a minimal Page to calculate its URL using the same logic as the build pipeline
        relative_path = path.lchop("content/")
        basename = Path[path].basename
        language = extract_language_from_filename(basename)
        target_url = calculate_page_url(relative_path, data[:slug], data[:custom_path], language, data[:date], data[:title])
        return unless target_url

        aliases.each do |alias_path|
          # Carry base_path so generated redirects match the build's own
          # redirect HTML (`url=/myrepo/moved/`) on subpath deploys. Ensure a
          # leading slash first since with_base_path only prefixes root-relative
          # paths; a no-op when base_path is empty (domain-root deploy).
          from = with_base_path(alias_path)
          to = with_base_path(target_url)
          redirects << {from, to}
        end
      rescue ex : ArgumentError | Hwaro::HwaroError | IO::Error
        # One bad content file (invalid UTF-8 → ArgumentError from PCRE2,
        # malformed frontmatter → HwaroError, unreadable file → IO::Error)
        # must not abort ALL platform config generation — degrade per file,
        # matching how check-links skips unreadable Markdown.
        Logger.warn "Skipping #{path} while collecting aliases: #{ex.message}"
      end

      # Calculate the URL for a page through the same shared resolver as the
      # build pipeline (Utils::PermalinkResolver) so generated platform
      # redirects always match the built site's canonical URLs. Handles slug
      # overrides, custom_path, permalinks (remaps and token patterns), and
      # index pages. Returns nil when a date-token pattern can't resolve
      # (caller skips aliases for that file).
      private def calculate_page_url(relative_path : String, slug : String?, custom_path : String?, language : String? = nil, date : Time? = nil, title : String = "") : String?
        url, error = Utils::PermalinkResolver.resolve_url_lenient(
          relative_path,
          @config,
          slug: slug,
          custom_path: custom_path,
          language: language,
          date: date,
          title: title,
          version: @config.versions.for_path(relative_path),
        )
        return if error
        url
      end
    end
  end
end
