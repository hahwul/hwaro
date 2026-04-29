require "json"
require "../models/config"
require "../models/page"
require "../content/processors/markdown"
require "../utils/logger"

module Hwaro
  module Services
    class PlatformConfig
      SUPPORTED_PLATFORMS = ["netlify", "vercel", "cloudflare", "github-pages", "gitlab-ci", "codeberg-pages"]

      @config : Models::Config

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

      private def output_dir : String
        "public"
      end

      private def generate_netlify : String
        lines = [] of String
        lines << "[build]"
        lines << "  command = \"#{build_command}\""
        lines << "  publish = \"#{output_dir}\""
        lines << ""
        lines << "[build.environment]"
        lines << "  # Add environment variables here"
        lines << "  # HWARO_VERSION = \"0.5.0\""

        # Redirects from aliases
        redirects = collect_aliases
        unless redirects.empty?
          lines << ""
          redirects.each do |from, to|
            lines << "[[redirects]]"
            lines << "  from = \"#{from}\""
            lines << "  to = \"#{to}\""
            lines << "  status = 301"
            lines << ""
          end
        end

        # Headers for caching
        lines << "[[headers]]"
        lines << "  for = \"/assets/*\""
        lines << "  [headers.values]"
        lines << "    Cache-Control = \"public, max-age=31536000, immutable\""

        lines.join("\n") + "\n"
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
            "source"  => JSON::Any.new("/assets/(.*)"),
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
        lines << "  bucket = \"./#{output_dir}\""
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
            lines << "# #{from} #{to} 301"
          end
        end

        lines.join("\n") + "\n"
      end

      private def generate_github_pages : String
        lines = [] of String
        lines << "---"
        lines << "name: Hwaro CI/CD"
        lines << ""
        lines << "on:"
        lines << "  push:"
        lines << "    branches: [main]"
        lines << "  pull_request:"
        lines << "    branches: [main]"
        lines << "  workflow_dispatch:"
        lines << ""
        lines << "permissions:"
        lines << "  contents: write"
        lines << ""
        lines << "jobs:"
        lines << "  build:"
        lines << "    runs-on: ubuntu-latest"
        lines << "    if: github.event_name == 'pull_request'"
        lines << "    steps:"
        lines << "      - name: Checkout"
        lines << "        uses: actions/checkout@v6"
        lines << ""
        lines << "      - name: Build Only"
        lines << "        uses: hahwul/hwaro@main"
        lines << "        with:"
        lines << "          build_only: true"
        lines << ""
        lines << "  deploy:"
        lines << "    runs-on: ubuntu-latest"
        lines << "    if: github.event_name == 'push' && github.ref == 'refs/heads/main'"
        lines << "    steps:"
        lines << "      - name: Checkout"
        lines << "        uses: actions/checkout@v6"
        lines << ""
        lines << "      - name: Build and Deploy"
        lines << "        uses: hahwul/hwaro@main"
        lines << "        with:"
        lines << "          token: ${{ secrets.GITHUB_TOKEN }}"
        lines << ""

        lines.join("\n")
      end

      private def generate_gitlab_ci : String
        lines = [] of String
        lines << "image: ghcr.io/hahwul/hwaro:latest"
        lines << ""
        lines << "pages:"
        lines << "  stage: deploy"
        lines << "  script:"
        lines << "    - hwaro build"
        lines << "  artifacts:"
        lines << "    paths:"
        lines << "      - public"
        lines << "  only:"
        lines << "    - main"
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
        lines << "          cd #{output_dir}"
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

      private def scan_content_for_aliases(dir : String, redirects : Array(Tuple(String, String)))
        Dir.each_child(dir) do |entry|
          path = File.join(dir, entry)
          if File.directory?(path)
            scan_content_for_aliases(path, redirects)
          elsif entry.ends_with?(".md")
            extract_aliases_from_file(path, redirects)
          end
        end
      end

      private def extract_aliases_from_file(path : String, redirects : Array(Tuple(String, String)))
        raw_content = File.read(path)
        data = Processor::Markdown.parse(raw_content, path)

        aliases = data[:aliases]
        return if aliases.empty?

        # Build a minimal Page to calculate its URL using the same logic as the build pipeline
        relative_path = path.lchop("content/")
        target_url = calculate_page_url(relative_path, data[:slug], data[:custom_path])

        aliases.each do |alias_path|
          redirects << {alias_path, target_url}
        end
      end

      # Calculate the URL for a page, mirroring the logic in MarkdownHooks#calculate_page_url.
      # Handles slug overrides, custom_path, permalinks, and index pages.
      private def calculate_page_url(relative_path : String, slug : String?, custom_path : String?) : String
        directory_path = Path[relative_path].dirname.to_s
        effective_dir = directory_path

        # Apply permalinks mapping from config
        @config.permalinks.each do |source, target|
          if directory_path == source
            effective_dir = target
            break
          elsif directory_path.starts_with?("#{source}/")
            effective_dir = directory_path.sub(/^#{Regex.escape(source)}\//, "#{target}/")
            break
          end
        end

        if custom_path
          custom = custom_path.lchop("/")
          url = "/#{custom}"
          url += "/" unless url.ends_with?("/")
          return url
        end

        stem = Path[relative_path].stem
        is_index = stem == "_index" || stem == "index"

        if is_index
          if effective_dir == "." || effective_dir.empty?
            return "/"
          else
            return "/#{effective_dir}/"
          end
        end

        leaf = slug || stem

        if effective_dir == "." || effective_dir.empty?
          "/#{leaf}/"
        else
          "/#{effective_dir}/#{leaf}/"
        end
      end
    end
  end
end
