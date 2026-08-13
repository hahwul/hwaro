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

      # A segment that OPENS with `:name` — the shape an author writes when
      # they mean a token, whether or not the name is spelled correctly. This
      # is what keeps `/:tokne/` a reportable typo instead of a directory
      # literally named `:tokne`. The name must start with a letter or `_` so
      # an ordinary directory target that happens to contain a colon before a
      # digit (`2024:2025`) stays a plain remap.
      TOKEN_ANYWHERE = /\A:[A-Za-z_][A-Za-z0-9_]*/

      # A KNOWN token buried inside a larger segment (`post-:slug`). Matched
      # anywhere because such a segment is not expandable — see
      # validate_pattern! — and both callers below have to see it in order to
      # reject it.
      #
      # Restricted to VALID_TOKENS, and closed with `\b`, because a colon is
      # perfectly legal inside a URL path segment: a plain directory remap
      # like `"notes" = "/wiki/pros:cons/"` (or `/docs/faq:slugs/`) contains
      # no hwaro token at all, and matching any `:identifier` here made the
      # compound-segment check fire on it and abort the build with a config
      # error on config that published fine.
      EMBEDDED_VALID_TOKEN = Regex.new(":(?:#{VALID_TOKENS.join("|")})\\b")

      # The only shape `expand_pattern` can actually substitute: a segment
      # that is nothing but one token.
      WHOLE_SEGMENT_TOKEN = /\A:[A-Za-z_][A-Za-z0-9_]*\z/

      # True when this `/`-separated segment is asking to be a token: it either
      # opens with `:name`, or embeds a token hwaro knows.
      private def token_segment?(segment : String) : Bool
        segment.matches?(TOKEN_ANYWHERE) || segment.matches?(EMBEDDED_VALID_TOKEN)
      end

      # True when the `[permalinks]` target contains a `:token`, i.e. it is a
      # Hugo-style pattern rather than a directory remap.
      def pattern?(target : String) : Bool
        target.split('/').any? { |segment| token_segment?(segment) }
      end

      # Validate every `:token` in a pattern against VALID_TOKENS, and require
      # each one to be a whole `/`-separated segment. Raises a classified
      # config error so `hwaro build` exits with the stable config exit code
      # instead of silently emitting literal `:tokne` path segments.
      def validate_pattern!(rule_key : String, target : String) : Nil
        target.split('/').each do |segment|
          next unless token_segment?(segment)

          # `expand_pattern` substitutes whole segments only, so a token
          # embedded in a larger segment (`/:year/post-:slug/`) used to be
          # copied through verbatim: the build exited 0 having created a
          # directory literally named `post-:slug`, which is illegal on NTFS
          # and unescaped in every URL pointing at it. The whole-segment
          # sibling (`/:year-:month/`) was already rejected; this closes the
          # remaining half of the same mistake.
          unless segment.matches?(WHOLE_SEGMENT_TOKEN)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: "Path segment '#{segment}' in [permalinks] rule \"#{rule_key}\" (pattern '#{target}') mixes a token with other text.",
              hint: "Tokens must be whole path segments: write '/:year/:slug/', not '/:year/post-:slug/'. Valid tokens are #{VALID_TOKENS.map { |t| ":#{t}" }.join(", ")}.",
            )
          end

          token = segment.lchop(':')
          next if VALID_TOKENS.includes?(token)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Unknown token ':#{token}' in [permalinks] rule \"#{rule_key}\" (pattern '#{target}').",
            hint: "Valid tokens are #{VALID_TOKENS.map { |t| ":#{t}" }.join(", ")}. Tokens must be whole path segments.",
          )
        end
      end

      DATE_TOKEN_HINT = "Add a date to the page's front matter, set an explicit `path`, or remove date tokens from the pattern."

      # Compute the canonical site-relative URL for a content file.
      #
      # Precedence: explicit `path` front matter (custom_path) wins outright;
      # otherwise the language prefix for non-default languages is emitted
      # BEFORE the pattern/remap output (`/ko/2026/03/05/…`), then the first
      # matching `[permalinks]` rule applies (pattern expansion for leaf
      # pages, directory remap otherwise), and the result is normalized to a
      # leading- and trailing-slash directory URL.
      #
      # A date-token pattern on a dateless page raises HWARO_E_CONTENT.
      # Callers that can't yet know whether the page will publish (the parse
      # fan-out runs before cascades and draft/expiry filtering) use
      # `resolve_url_lenient` and defer the error to after filtering.
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
        url, error = resolve_url_lenient(relative_path, config,
          slug: slug, custom_path: custom_path, language: language, date: date, title: title)
        if error
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONTENT,
            message: error,
            hint: DATE_TOKEN_HINT,
          )
        end
        url
      end

      # Like `resolve_url`, but a date-token pattern on a dateless page
      # falls back to the default directory URL and REPORTS the problem in
      # the second tuple slot instead of raising — so a draft or headless
      # page the build is about to discard can't abort the whole build over
      # a URL it never publishes.
      def resolve_url_lenient(
        relative_path : String,
        config : Models::Config?,
        *,
        slug : String?,
        custom_path : String?,
        language : String?,
        date : Time?,
        title : String,
      ) : {String, String?}
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
          return {url, nil}
        end

        error = nil
        rule = match_permalink_rule(config, directory_path, is_index)

        if rule && pattern?(rule[:target])
          path = expand_pattern(
            rule[:key], rule[:target], relative_path, directory_path, clean_stem,
            slug: slug, date: date, title: title,
          )
          if path
            return {path.empty? ? "#{lang_prefix}/" : "#{lang_prefix}/#{path}/", nil}
          end
          # Date token, no date: report and fall back to the un-remapped
          # directory URL (the pattern target has no directory to remap to).
          error = "#{relative_path} matches [permalinks] rule \"#{rule[:key]}\" (pattern '#{rule[:target]}') which requires a date, but the page has none."
          rule = nil
        end

        effective_dir = rule ? remap_directory(rule[:target], rule[:rest]) : directory_path

        url = if is_index
                if effective_dir == "." || effective_dir.empty?
                  lang_prefix.empty? ? "/" : "#{lang_prefix}/"
                else
                  "#{lang_prefix}/#{bundle_dir(effective_dir, clean_stem, slug)}/"
                end
              else
                leaf = slug || clean_stem
                if effective_dir == "." || effective_dir.empty?
                  "#{lang_prefix}/#{leaf}/"
                else
                  "#{lang_prefix}/#{effective_dir}/#{leaf}/"
                end
              end
        {url, error}
      end

      # A leaf bundle (`<dir>/index.md`) is a single page whose URL segment is
      # its directory name, so a front-matter `slug` has to rename that
      # segment — otherwise `slug` (documented as "Custom URL slug") silently
      # stops working the moment a page is converted to bundle layout, which
      # is exactly what `hwaro new --bundle` and multilingual siblings produce.
      #
      # Section indexes (`_index.md`) are deliberately excluded: their
      # directory name is also the prefix every child page derives its own URL
      # from, and children resolve independently from their own path — renaming
      # it here would move the section listing away from its own children.
      private def bundle_dir(effective_dir : String, clean_stem : String, slug : String?) : String
        return effective_dir unless clean_stem == "index"
        return effective_dir if slug.nil? || slug.empty?

        parent = Path[effective_dir].dirname
        parent == "." || parent.empty? ? slug : "#{parent}/#{slug}"
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
      # (the pre-resolver remap logic never matched them), so no legacy config
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
      # any deeper path (the original directory-remap semantics).
      private def remap_directory(target : String, rest : String) : String
        return target if rest.empty?
        target.empty? ? rest : "#{target}/#{rest}"
      end

      # Expand a token pattern into a slash-joined URL path (no surrounding
      # slashes), or nil when the pattern needs a date the page doesn't have
      # (the caller owns whether that's an error). An empty `:section`
      # (root-level page) collapses instead of emitting a `//` segment.
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
      ) : String?
        segments = [] of String

        pattern.split('/').each do |segment|
          next if segment.empty?

          unless segment.starts_with?(':')
            segments << segment
            next
          end

          case token = segment.lchop(':')
          when "year", "month", "day"
            page_date = date || return
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
