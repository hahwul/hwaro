# Remote scaffold class for fetching scaffolds from GitHub repositories
#
# Supports two source formats:
#   - github:owner/repo[/path]     (GitHub shorthand, optional subpath)
#   - https://github.com/owner/repo[/tree/branch/path]  (Full GitHub URL)
#
# Fetches config.toml, templates/, static/, and content/ from the repository (or subpath).
# Content files keep only front matter (metadata) so users can see the structure.

require "http/client"
require "json"
require "uri"
require "./base"
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

        def initialize(source : String)
          owner, repo, subpath = self.class.parse_source(source)
          label = subpath.empty? ? "#{owner}/#{repo}" : "#{owner}/#{repo}/#{subpath}"
          @description_text = "Remote scaffold from #{label}"
          @config_data = ""
          @content_data = {} of String => String
          @template_data = {} of String => String
          @static_data = {} of String => String
          @shortcode_data = {} of String => String
          fetch!(owner, repo, subpath)
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

        def config_content(skip_taxonomies : Bool = false) : String
          @config_data
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
          if source.starts_with?("github:") || source.starts_with?("git:")
            raw = source.sub(/^(?:github|git):/, "")
            parts = raw.split("/")
            if parts.size < 2 || parts[0].empty? || parts[1].empty?
              raise ArgumentError.new("Invalid GitHub shorthand: #{source}. Expected format: github:owner/repo[/path]")
            end
            subpath = parts.size > 2 ? parts[2..].join("/") : ""
            {parts[0], parts[1], subpath}
          else
            uri = URI.parse(source)
            unless uri.host.try { |h| h == "github.com" || h.ends_with?(".github.com") }
              raise ArgumentError.new("Only GitHub URLs are supported. Got: #{source}")
            end
            path_parts = (uri.path || "/").strip("/").split("/")
            if path_parts.size < 2 || path_parts[0].empty? || path_parts[1].empty?
              raise ArgumentError.new("Invalid GitHub URL: #{source}. Expected format: https://github.com/owner/repo")
            end
            owner = path_parts[0]
            repo = path_parts[1].sub(/\.git$/, "")
            # Handle /tree/branch/subpath or /blob/branch/subpath patterns
            subpath = if path_parts.size > 3 && (path_parts[2] == "tree" || path_parts[2] == "blob")
                        path_parts[4..].join("/")
                      elsif path_parts.size > 2
                        # Direct path: https://github.com/owner/repo/subpath
                        path_parts[2..].join("/")
                      else
                        ""
                      end
            {owner, repo, subpath}
          end
        end

        private def fetch!(owner : String, repo : String, subpath : String = "")
          label = subpath.empty? ? "#{owner}/#{repo}" : "#{owner}/#{repo}/#{subpath}"
          Logger.info "Fetching remote scaffold from #{label}..."

          default_branch = fetch_default_branch(owner, repo)
          Logger.info "Using branch: #{default_branch}"

          tree = fetch_tree(owner, repo, default_branch)
          prefix = subpath.empty? ? "" : "#{subpath}/"

          # Collect files to download
          targets = [] of {category: Symbol, key: String, full_path: String, display: String}

          tree.each do |entry|
            full_path = entry["path"].as_s
            next unless entry["type"].as_s == "blob"

            unless prefix.empty?
              next unless full_path.starts_with?(prefix)
            end

            path = prefix.empty? ? full_path : full_path.sub(prefix, "")

            if path == "config.toml"
              targets << {category: :config, key: "", full_path: full_path, display: path}
            elsif path.starts_with?("content/") && path.ends_with?(".md")
              key = Utils::PathUtils.sanitize_path(path.sub("content/", ""))
              next if key.empty?
              targets << {category: :content, key: key, full_path: full_path, display: path}
            elsif path.starts_with?("templates/shortcodes/")
              key = Utils::PathUtils.sanitize_path(path.sub("templates/", ""))
              next if key.empty?
              targets << {category: :shortcode, key: key, full_path: full_path, display: path}
            elsif path.starts_with?("templates/")
              key = Utils::PathUtils.sanitize_path(path.sub("templates/", ""))
              next if key.empty?
              targets << {category: :template, key: key, full_path: full_path, display: path}
            elsif path.starts_with?("static/")
              key = Utils::PathUtils.sanitize_path(path.sub("static/", ""))
              next if key.empty?
              targets << {category: :static, key: key, full_path: full_path, display: path}
            end
          end

          if targets.empty?
            Logger.warn "No scaffold files found in #{label}."
            Logger.warn "Expected: config.toml, templates/, or static/ directories."
            return
          end

          # Download files in parallel using fibers
          channel = Channel({category: Symbol, key: String, display: String, body: String}).new(targets.size)

          targets.each do |target|
            spawn do
              begin
                body = fetch_file(owner, repo, default_branch, target[:full_path])
                channel.send({category: target[:category], key: target[:key], display: target[:display], body: body})
              rescue ex
                Logger.warn "Failed to fetch #{target[:display]}: #{ex.message}"
                channel.send({category: target[:category], key: target[:key], display: target[:display], body: ""})
              end
            end
          end

          targets.size.times do
            result = channel.receive
            case result[:category]
            when :config
              @config_data = result[:body]
            when :content
              @content_data[result[:key]] = extract_front_matter(result[:body])
            when :shortcode
              @shortcode_data[result[:key]] = result[:body]
            when :template
              @template_data[result[:key]] = result[:body]
            when :static
              @static_data[result[:key]] = result[:body]
            end
            Logger.action :fetch, result[:display]
          end

          Logger.info "Fetched #{targets.size} files from remote scaffold."

          warn_dangerous_config(@config_data, label) unless @config_data.empty?
        end

        # Warn the user if a remote scaffold's config.toml contains settings
        # that can execute arbitrary commands (build hooks, deploy commands).
        private def warn_dangerous_config(config_data : String, label : String)
          dangerous = [] of String

          if config_data.matches?(/hooks\s*\.\s*pre\s*=/m) || config_data.matches?(/hooks\s*\.\s*post\s*=/m)
            dangerous << "build hooks (hooks.pre / hooks.post)"
          end

          if config_data.matches?(/command\s*=/m)
            dangerous << "deploy commands (command)"
          end

          return if dangerous.empty?

          Logger.warn "Security warning: remote scaffold '#{label}' contains config that can execute shell commands:"
          dangerous.each { |d| Logger.warn "  - #{d}" }
          Logger.warn "Review config.toml carefully before running 'hwaro build' or 'hwaro deploy'."
        end

        # Extract front matter from markdown content, discarding the body.
        # Keeps the +++ delimited TOML front matter block and adds a placeholder.
        private def extract_front_matter(content : String) : String
          lines = content.lines
          return content if lines.empty?

          # Detect front matter delimiter (+++ for TOML, --- for YAML)
          delimiter = lines[0].strip
          return content unless delimiter == "+++" || delimiter == "---"

          # Find the closing delimiter
          close_index = nil
          lines.each_with_index do |line, i|
            next if i == 0
            if line.strip == delimiter
              close_index = i
              break
            end
          end

          return content unless close_index

          front_matter = lines[0..close_index].join("\n")
          "#{front_matter}\n"
        end

        private def fetch_default_branch(owner : String, repo : String) : String
          response = github_api_get("/repos/#{owner}/#{repo}")

          unless response.status_code == 200
            case response.status_code
            when 404
              raise "Repository not found: #{owner}/#{repo}"
            when 403
              raise "GitHub API rate limit exceeded. Try again later."
            else
              raise "Failed to fetch repository info: HTTP #{response.status_code}"
            end
          end

          data = JSON.parse(response.body)
          data["default_branch"].as_s
        end

        private def fetch_tree(owner : String, repo : String, branch : String) : Array(JSON::Any)
          response = github_api_get("/repos/#{owner}/#{repo}/git/trees/#{branch}?recursive=1")

          unless response.status_code == 200
            raise "Failed to fetch repository tree: HTTP #{response.status_code}"
          end

          data = JSON.parse(response.body)
          data["tree"].as_a
        end

        private def fetch_file(owner : String, repo : String, branch : String, path : String) : String
          uri = URI.parse("https://raw.githubusercontent.com/#{owner}/#{repo}/#{branch}/#{path}")
          tls = OpenSSL::SSL::Context::Client.new
          client = HTTP::Client.new(uri.host.not_nil!, uri.port || 443, tls: tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds

          begin
            response = client.get(uri.request_target, headers: HTTP::Headers{
              "User-Agent" => "Hwaro",
            })

            unless response.status_code == 200
              Logger.warn "Failed to fetch #{path}: HTTP #{response.status_code}"
              return ""
            end

            response.body
          ensure
            client.close
          end
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
          ensure
            client.close
          end
        end
      end
    end
  end
end
