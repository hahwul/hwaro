# Remote scaffold class for fetching scaffolds from GitHub repositories
#
# Supports two source formats:
#   - github:owner/repo[/path]     (GitHub shorthand, optional subpath)
#   - https://github.com/owner/repo[/tree/branch/path]  (Full GitHub URL)
#
# Fetches config.toml, templates/, and static/ from the repository (or subpath).
# Content files are excluded to let users create their own content.

require "http/client"
require "json"
require "uri"
require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Remote < Base
        @config_data : String
        @template_data : Hash(String, String)
        @static_data : Hash(String, String)
        @shortcode_data : Hash(String, String)
        @description_text : String

        def initialize(source : String)
          owner, repo, subpath = self.class.parse_source(source)
          label = subpath.empty? ? "#{owner}/#{repo}" : "#{owner}/#{repo}/#{subpath}"
          @description_text = "Remote scaffold from #{label}"
          @config_data = ""
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
          {} of String => String
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
            unless uri.host.try(&.includes?("github.com"))
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
          file_count = 0

          tree.each do |entry|
            full_path = entry["path"].as_s
            next unless entry["type"].as_s == "blob"

            # When subpath is set, only consider files under that prefix
            unless prefix.empty?
              next unless full_path.starts_with?(prefix)
            end

            # Strip the subpath prefix to get the scaffold-relative path
            path = prefix.empty? ? full_path : full_path.sub(prefix, "")

            # Skip content directory
            next if path.starts_with?("content/")

            if path == "config.toml"
              @config_data = fetch_file(owner, repo, default_branch, full_path)
              Logger.action :fetch, path
              file_count += 1
            elsif path.starts_with?("templates/shortcodes/")
              relative = path.sub("templates/", "")
              @shortcode_data[relative] = fetch_file(owner, repo, default_branch, full_path)
              Logger.action :fetch, path
              file_count += 1
            elsif path.starts_with?("templates/")
              relative = path.sub("templates/", "")
              @template_data[relative] = fetch_file(owner, repo, default_branch, full_path)
              Logger.action :fetch, path
              file_count += 1
            elsif path.starts_with?("static/")
              relative = path.sub("static/", "")
              @static_data[relative] = fetch_file(owner, repo, default_branch, full_path)
              Logger.action :fetch, path
              file_count += 1
            end
          end

          if file_count == 0
            Logger.warn "No scaffold files found in #{label}."
            Logger.warn "Expected: config.toml, templates/, or static/ directories."
          else
            Logger.info "Fetched #{file_count} files from remote scaffold."
          end
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

          response = client.get(uri.request_target, headers: HTTP::Headers{
            "User-Agent" => "Hwaro",
          })

          unless response.status_code == 200
            Logger.warn "Failed to fetch #{path}: HTTP #{response.status_code}"
            return ""
          end

          response.body
        end

        private def github_api_get(path : String) : HTTP::Client::Response
          tls = OpenSSL::SSL::Context::Client.new
          client = HTTP::Client.new("api.github.com", 443, tls: tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds

          client.get(path, headers: HTTP::Headers{
            "User-Agent" => "Hwaro",
            "Accept"     => "application/vnd.github.v3+json",
          })
        end
      end
    end
  end
end
