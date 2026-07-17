# Shared canonical URL computation for content pages.
#
# Resolves a page's site-relative URL from its content path plus the
# `[permalinks]` rules in config. Two rule styles are supported:
#
# - Plain values (`"old/posts" = "posts"`) remap a directory prefix and
#   keep the rest of the path (the original behavior).
# - Token patterns (`"posts" = "/:year/:month/:slug/"`) rebuild the whole
#   URL for leaf pages under the matched directory (Hugo parity). Index
#   pages (`_index`/bundle `index`) skip pattern rules and keep the
#   remap-only behavior.
#
# Both the ParseContent phase (`calculate_page_url`) and the PlatformConfig
# alias generation call through here so canonical URLs can never drift
# between the build pipeline and generated platform redirects.

require "../models/config"
require "./errors"
require "./text_utils"

module Hwaro
  module Utils
    module PermalinkResolver
      extend self

      # Tokens accepted inside a `[permalinks]` pattern value. Each token
      # must be a whole `/`-separated segment (e.g. `/:year/:slug/`).
      VALID_TOKENS = %w[year month day slug title section filename]

      # True when the `[permalinks]` target contains a `:token` segment,
      # i.e. it is a Hugo-style pattern rather than a directory remap.
      def pattern?(target : String) : Bool
        target.split('/').any?(&.starts_with?(':'))
      end

      # Validate every `:token` segment of a pattern against VALID_TOKENS.
      # Raises a classified config error so `hwaro build` exits with the
      # stable config exit code instead of silently emitting literal
      # `:tokne` path segments.
      def validate_pattern!(rule_key : String, target : String) : Nil
        target.split('/').each do |segment|
          next unless segment.starts_with?(':')
          token = segment.lchop(':')
          next if VALID_TOKENS.includes?(token)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Unknown token ':#{token}' in [permalinks] rule \"#{rule_key}\" (pattern '#{target}').",
            hint: "Valid tokens are #{VALID_TOKENS.map { |t| ":#{t}" }.join(", ")}. Tokens must be whole path segments.",
          )
        end
      end

      # Compute the canonical site-relative URL for a content file.
      #
      # Precedence: explicit `path` front matter (custom_path) wins outright;
      # otherwise the language prefix for non-default languages is emitted
      # BEFORE the pattern/remap output (`/ko/2026/03/05/…`), then the first
      # matching `[permalinks]` rule applies (pattern expansion for leaf
      # pages, directory remap otherwise), and the result is normalized to a
      # leading- and trailing-slash directory URL.
      def resolve_url(
        relative_path : String,
        config : Models::Config?,
        *,
        slug : String?,
        custom_path : String?,
        language : String?,
        date : Time?,
        title : String,
      ) : String
        stem = Path[relative_path].stem

        # Remove language suffix from stem (e.g. "hello-world.ko" -> "hello-world")
        clean_stem = if language
                       stem.chomp(".#{language}")
                     else
                       stem
                     end

        is_index = clean_stem == "_index" || clean_stem == "index"
        directory_path = Path[relative_path].dirname.to_s

        # For multilingual sites, include language prefix for non-default languages
        lang_prefix = if language && config && language != config.default_language
                        "/#{language}"
                      else
                        ""
                      end

        if custom_path
          url = "#{lang_prefix}/#{custom_path.lchop("/")}"
          url += "/" unless url.ends_with?("/")
          return url
        end

        rule = match_permalink_rule(config, directory_path, is_index)

        if rule && pattern?(rule[:target])
          path = expand_pattern(
            rule[:key], rule[:target], relative_path, directory_path, clean_stem,
            slug: slug, date: date, title: title,
          )
          return path.empty? ? "#{lang_prefix}/" : "#{lang_prefix}/#{path}/"
        end

        effective_dir = rule ? remap_directory(rule[:target], rule[:rest]) : directory_path

        if is_index
          if effective_dir == "." || effective_dir.empty?
            lang_prefix.empty? ? "/" : "#{lang_prefix}/"
          else
            "#{lang_prefix}/#{effective_dir}/"
          end
        else
          leaf = slug || clean_stem
          if effective_dir == "." || effective_dir.empty?
            "#{lang_prefix}/#{leaf}/"
          else
            "#{lang_prefix}/#{effective_dir}/#{leaf}/"
          end
        end
      end

      # First `[permalinks]` rule whose source matches `directory_path`
      # exactly or as a parent prefix. Pattern rules apply to leaf pages
      # only: for index pages they are skipped and scanning continues, so a
      # later plain remap can still take effect (Hugo parity — section
      # indexes keep their directory URL under a date pattern).
      #
      # An empty source (`""` or `"/"` in config.toml) acts as a catch-all
      # for PATTERN rules only — it matches every page, including root-level
      # ones. Empty-source plain remaps stay inert as they always have been
      # (`resolve_permalink_dir` never matched them), so no legacy config
      # changes meaning.
      private def match_permalink_rule(config : Models::Config?, directory_path : String, is_index : Bool)
        return unless config

        config.permalinks.each do |source, target|
          rest = if source.empty?
                   next unless pattern?(target)
                   directory_path == "." ? "" : directory_path
                 elsif directory_path == source
                   ""
                 elsif directory_path.starts_with?("#{source}/")
                   directory_path[(source.size + 1)..]
                 else
                   next
                 end
          next if is_index && pattern?(target)
          return {key: source, target: target, rest: rest}
        end
        nil
      end

      # Replace the matched source prefix with the remap target, preserving
      # any deeper path (mirrors Config#resolve_permalink_dir semantics).
      private def remap_directory(target : String, rest : String) : String
        return target if rest.empty?
        target.empty? ? rest : "#{target}/#{rest}"
      end

      # Expand a token pattern into a slash-joined URL path (no surrounding
      # slashes). An empty `:section` (root-level page) collapses instead of
      # emitting a `//` segment.
      private def expand_pattern(
        rule_key : String,
        pattern : String,
        relative_path : String,
        directory_path : String,
        clean_stem : String,
        *,
        slug : String?,
        date : Time?,
        title : String,
      ) : String
        segments = [] of String

        pattern.split('/').each do |segment|
          next if segment.empty?

          unless segment.starts_with?(':')
            segments << segment
            next
          end

          case token = segment.lchop(':')
          when "year", "month", "day"
            page_date = date || raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "#{relative_path} matches [permalinks] rule \"#{rule_key}\" (pattern '#{pattern}') which requires a date, but the page has none.",
              hint: "Add a date to the page's front matter, set an explicit `path`, or remove date tokens from the pattern.",
            )
            segments << case token
            when "year"  then page_date.to_s("%Y")
            when "month" then page_date.to_s("%m")
            else              page_date.to_s("%d")
            end
          when "slug"
            segments << (slug || clean_stem)
          when "title"
            slugified = TextUtils.slugify(title)
            segments << (slugified.empty? ? (slug || clean_stem) : slugified)
          when "section"
            section = directory_path == "." ? "" : directory_path
            segments << section unless section.empty?
          when "filename"
            segments << clean_stem
          else
            # load_permalinks validates patterns up front; reaching this
            # branch means the rule bypassed validation (e.g. set in code).
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: "Unknown token ':#{token}' in [permalinks] rule \"#{rule_key}\" (pattern '#{pattern}').",
              hint: "Valid tokens are #{VALID_TOKENS.map { |t| ":#{t}" }.join(", ")}.",
            )
          end
        end

        segments.join('/')
      end
    end
  end
end
