# Markdown processor for converting Markdown to HTML
#
# This processor handles:
# - TOML, YAML, and JSON front matter parsing
# - Markdown to HTML conversion using Markd
# - Table of Contents generation with header IDs
# - Syntax highlighting support via HighlightingRenderer

require "markd"
require "yaml"
require "toml"
require "json"
require "xml"
require "html"
require "digest/md5"
require "./base"
require "./table_parser"
require "./syntax_highlighter"
require "./markdown_extensions"
require "../../models/toc"
require "../../utils/errors"
require "../../utils/frontmatter_scanner"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Processors
      # Markdown processor implementation
      class Markdown < Base
        # Regex for matching h1-h6 tags with IDs to insert anchor links
        ANCHOR_LINK_REGEX = /<(h[1-6])([^>]*id="([^"]+)"[^>]*)>(.*?)<\/\1>/m

        # Regex for post_process_html — lightweight replacements for XML.parse_html
        # Matches <h1>…</h1> through <h6>…</h6>, capturing tag name, level digit, attributes, and inner HTML
        HEADING_TAG_REGEX = /<(h([1-6]))(\s[^>]*)?>(.+?)<\/h\2>/mi
        # Matches <img ...> tags that do NOT already have a loading= attribute
        # Quote-aware attribute scan: a `>` inside a quoted attribute value
        # (legal HTML5, e.g. alt="Home > Docs") must not be treated as the tag
        # end, or the lazy-load rewrite corrupts the raw <img> into broken markup.
        IMG_LAZY_REGEX = /<img(?![^>]*\bloading\s*=)((?:[^>"']|"[^"]*"|'[^']*')*?)\s*\/?>/i
        # Extracts id="value" from an attribute string
        ID_ATTR_REGEX = /\bid\s*=\s*["']([^"']+)["']/
        # Strips HTML tags to get plain text
        HTML_TAG_STRIP_REGEX = /<[^>]+>/

        # Regex for TOML front matter
        TOML_FRONT_MATTER_REGEX = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m

        # Regex for YAML front matter
        YAML_FRONT_MATTER_REGEX = /\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m

        # JSON front matter is delimited by balanced braces. The file must begin
        # with `{` (no leading whitespace) and the first balanced `{...}` is the
        # front matter; the remainder is the markdown body.
        # See `Utils::FrontmatterScanner.find_json_end` for the brace scanner.

        # Known front-matter keys (shared between TOML, YAML, and JSON parsers).
        # Using a Set for O(1) lookup instead of Array#includes? O(n).
        KNOWN_FRONT_MATTER_KEYS = Set{
          "title", "description", "image", "draft", "template", "in_sitemap",
          "toc", "date", "updated", "render", "slug", "path", "aliases", "tags",
          "transparent", "generate_feeds", "paginate", "pagination_enabled",
          "sort_by", "reverse", "authors", "in_search_index", "insert_anchor_links",
          "page_template", "paginate_path", "redirect_to", "weight", "categories",
          "series", "series_weight", "expires", "paginate_by", "taxonomies",
          "cascade", "menus", "menu",
        }

        # Warn about unknown front-matter keys that look like typos of known keys.
        # Uses Levenshtein distance ≤ 2 to detect likely misspellings while ignoring
        # intentional custom fields (which tend to differ significantly from known keys).
        # Suggests the *closest* known key, not merely the first within the threshold —
        # otherwise `tag` (a typo of `tags`, distance 1) would resolve to whichever
        # distance-2 key happens to appear earlier in the set (e.g. `toc`).
        private def warn_typo_keys(unknown_keys : Array(String), file_path : String)
          return if file_path.empty?
          unknown_keys.each do |key|
            best : String? = nil
            best_distance = Int32::MAX
            KNOWN_FRONT_MATTER_KEYS.each do |known|
              dist = levenshtein(key, known)
              if dist < best_distance
                best_distance = dist
                best = known
              end
            end
            if (suggestion = best) && best_distance > 0 && best_distance <= 2
              Logger.warn "#{file_path}: unknown front-matter key '#{key}' — did you mean '#{suggestion}'?"
            end
          end
        end

        # Minimal Levenshtein distance (edit distance) for short strings.
        private def levenshtein(a : String, b : String) : Int32
          return b.size if a.empty?
          return a.size if b.empty?
          m = a.size
          n = b.size
          prev = Array(Int32).new(n + 1) { |i| i }
          curr = Array(Int32).new(n + 1, 0)
          m.times do |i|
            curr[0] = i + 1
            n.times do |j|
              cost = a[i] == b[j] ? 0 : 1
              curr[j + 1] = {curr[j] + 1, prev[j + 1] + 1, prev[j] + cost}.min
            end
            prev, curr = curr, prev
          end
          prev[n]
        end

        def name : String
          "markdown"
        end

        def extensions : Array(String)
          [".md", ".markdown"]
        end

        def priority : Int32
          100 # High priority as primary content processor
        end

        def process(content : String, context : ProcessorContext) : ProcessorResult
          html, _toc = render(content)
          ProcessorResult.new(content: html)
        rescue ex
          ProcessorResult.error("Markdown processing failed: #{ex.message}")
        end

        # Renders Markdown to HTML and generates a Table of Contents
        # Returns {html_content, toc_headers}
        # @param highlight - whether to enable syntax highlighting for code blocks
        # @param safe - if true, raw HTML will not be passed through (replaced by comments)
        # @param lazy_loading - if true, adds loading="lazy" to img tags
        # @param emoji - if true, converts emoji shortcodes to emoji characters
        def render(content : String, highlight : Bool = true, safe : Bool = false, lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil) : Tuple(String, Array(Models::TocHeader))
          # Tables are converted FIRST: cell bodies render through
          # InlineMarkdown, which HTML-escapes — so the HTML-injecting
          # extension passes (strikethrough/footnote refs/math) must not have
          # touched cell text yet, or their tags get escaped into visible
          # literal markup. The footnote-ref and math passes still reach the
          # generated <td> text afterwards, so refs and `$…$` inside cells
          # keep working. The math flag keeps `$~~x~~$` formula internals in
          # cells out of InlineMarkdown's strikethrough/emphasis passes.
          # `flags` also threads the F10 opt-in inline markup (ins/mark/sub/
          # sup) into cell rendering, alongside the existing math flag.
          processed = TableParser.process(
            content,
            flags: markdown_config ? MarkdownExtensions.inline_flags(markdown_config) : InlineMarkdown::Flags.new)

          # Pre-process markdown extensions (task lists, footnotes, etc.)
          if md_cfg = markdown_config
            processed = MarkdownExtensions.preprocess(processed, md_cfg)
          end

          # Use SyntaxHighlighter for rendering with highlighting support.
          # Tables were already converted above — skip the redundant re-scan.
          html = SyntaxHighlighter.render(processed, highlight, safe, tables_preprocessed: true)

          # Post-process markdown extensions (footnotes section, mermaid)
          if md_cfg = markdown_config
            html = MarkdownExtensions.postprocess(html, md_cfg)
          end

          has_headers = html.includes?("<h")
          has_images = lazy_loading && html.includes?("<img")

          # Optimization: If no headers and no images (or lazy loading disabled), don't parse XML
          unless has_headers || has_images
            result_html = emoji ? apply_emoji(html) : html
            return {result_html, [] of Models::TocHeader}
          end

          result_html, toc = post_process_html(html, has_headers, has_images)
          result_html = apply_emoji(result_html) if emoji
          {result_html, toc}
        rescue ex : XML::Error
          Logger.debug "Markdown post-process: XML error, returning raw html: #{ex.message}"
          {(html || ""), [] of Models::TocHeader}
        end

        # Returns parsed metadata and content
        def parse(raw_content : String, file_path : String = "")
          markdown_content = raw_content

          # Try TOML (+++), YAML (---), then JSON ({...}) front matter
          if match = raw_content.match(TOML_FRONT_MATTER_REGEX)
            result = extract_from_toml(match[1], file_path)
            markdown_content = match[2]
          elsif match = raw_content.match(YAML_FRONT_MATTER_REGEX)
            result = extract_from_yaml(match[1], file_path)
            markdown_content = match[2]
          elsif raw_content.starts_with?('{')
            # A leading `{` signals JSON frontmatter intent. If the scanner can
            # locate a balanced object we parse it; if not, the file is almost
            # certainly a truncated/mistyped JSON header — surface it as a
            # content error rather than silently treating it as body text.
            if end_idx = Utils::FrontmatterScanner.find_json_end(raw_content)
              # find_json_end returns a BYTE offset; slice on bytes so multibyte
              # (CJK/emoji/accented) JSON frontmatter isn't split mid-codepoint.
              result = extract_from_json(raw_content.byte_slice(0, end_idx), file_path)
              body = raw_content.byte_slice(end_idx)
              markdown_content = body.lchop("\r\n").lchop("\n")
            elsif !file_path.empty?
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_CONTENT,
                message: "Invalid JSON frontmatter in #{file_path}: unbalanced braces",
                hint: "The file starts with `{` so hwaro treated it as JSON frontmatter. Close the object with a matching `}` or remove the leading `{`.",
              )
            end
          end

          if result
            {
              title:               result[:title],
              description:         result[:description],
              image:               result[:image],
              content:             markdown_content,
              draft:               result[:draft],
              template:            result[:template],
              in_sitemap:          result[:in_sitemap],
              toc:                 result[:toc],
              date:                result[:date],
              updated:             result[:updated],
              render:              result[:render],
              slug:                result[:slug],
              custom_path:         result[:custom_path],
              aliases:             result[:aliases],
              tags:                result[:tags],
              taxonomies:          result[:taxonomies],
              front_matter_keys:   result[:front_matter_keys],
              transparent:         result[:transparent],
              generate_feeds:      result[:generate_feeds],
              paginate:            result[:paginate],
              pagination_enabled:  result[:pagination_enabled],
              sort_by:             result[:sort_by],
              reverse:             result[:reverse],
              authors:             result[:authors],
              extra:               result[:extra],
              in_search_index:     result[:in_search_index],
              insert_anchor_links: result[:insert_anchor_links],
              page_template:       result[:page_template],
              paginate_path:       result[:paginate_path],
              redirect_to:         result[:redirect_to],
              weight:              result[:weight],
              series:              result[:series],
              series_weight:       result[:series_weight],
              expires:             result[:expires],
              cascade:             result[:cascade],
              menus:               result[:menus],
            }
          else
            # No front matter found — return defaults
            {
              title:               "Untitled",
              description:         nil.as(String?),
              image:               nil.as(String?),
              content:             markdown_content,
              draft:               false,
              template:            nil.as(String?),
              in_sitemap:          true,
              toc:                 false,
              date:                nil.as(Time?),
              updated:             nil.as(Time?),
              render:              true,
              slug:                nil.as(String?),
              custom_path:         nil.as(String?),
              aliases:             [] of String,
              tags:                [] of String,
              taxonomies:          {} of String => Array(String),
              front_matter_keys:   [] of String,
              transparent:         false,
              generate_feeds:      false,
              paginate:            nil.as(Int32?),
              pagination_enabled:  nil.as(Bool?),
              sort_by:             nil.as(String?),
              reverse:             nil.as(Bool?),
              authors:             [] of String,
              extra:               {} of String => Models::ExtraValue,
              in_search_index:     true,
              insert_anchor_links: false,
              page_template:       nil.as(String?),
              paginate_path:       "page",
              redirect_to:         nil.as(String?),
              weight:              0,
              series:              nil.as(String?),
              series_weight:       0,
              expires:             nil.as(Time?),
              cascade:             {} of String => Models::ExtraValue,
              menus:               {} of String => Models::MenuRegistration,
            }
          end
        end

        # Extract front matter fields from TOML content
        private def extract_from_toml(raw : String, file_path : String)
          toml_fm = begin
            TOML.parse(raw)
          rescue ex
            # Top-level frontmatter parse failure — surface as HWARO_E_CONTENT
            # so `hwaro build --json` emits a structured error with exit 5.
            # When called without a file_path (library use), preserve the
            # previous graceful-nil behaviour.
            if file_path.empty?
              Logger.warn "Invalid TOML: #{ex.message}"
              return
            end
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "Invalid TOML frontmatter in #{file_path}: #{ex.message}",
              hint: "Check TOML frontmatter between `+++` fences",
            )
          end

          date = parse_toml_time(toml_fm["date"]?)
          updated = parse_toml_time(toml_fm["updated"]?)
          expires = parse_toml_time(toml_fm["expires"]?)

          extra = {} of String => Models::ExtraValue
          unknown_keys = [] of String
          toml_fm.each do |key, value|
            next if KNOWN_FRONT_MATTER_KEYS.includes?(key)
            if key == "extra" && (inner = value.as_h?)
              inner.each do |inner_key, inner_value|
                extra[inner_key] = extract_extra_value(inner_value)
              end
              next
            end
            unknown_keys << key
            extra[key] = extract_extra_value(value)
          end
          warn_typo_keys(unknown_keys, file_path)

          front_matter_keys = toml_fm.keys
          taxonomies = extract_taxonomies(toml_fm, front_matter_keys)
          tags = fm_string_array(toml_fm, "tags")
          tags = taxonomies["tags"]? || tags if tags.empty?
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(toml_fm, date, updated, extra, front_matter_keys, taxonomies, tags, file_path)
          result.merge({expires: expires})
        rescue ex : Hwaro::HwaroError
          raise ex
        rescue ex
          Logger.warn "Invalid TOML in #{file_path}: #{ex.message}" unless file_path.empty?
          nil
        end

        # Extract front matter fields from YAML content
        private def extract_from_yaml(raw : String, file_path : String)
          yaml_fm = begin
            YAML.parse(raw)
          rescue ex
            # Top-level frontmatter parse failure — surface as HWARO_E_CONTENT
            # so `hwaro build --json` emits a structured error with exit 5.
            # When called without a file_path (library use), preserve the
            # previous graceful-nil behaviour.
            if file_path.empty?
              Logger.warn "Invalid YAML: #{ex.message}"
              return
            end
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "Invalid YAML frontmatter in #{file_path}: #{ex.message}",
              hint: "Check YAML frontmatter between `---` fences",
            )
          end
          return unless yaml_fm.as_h?

          date = parse_yaml_time(yaml_fm["date"]?)
          updated = parse_yaml_time(yaml_fm["updated"]?)
          expires = parse_yaml_time(yaml_fm["expires"]?)

          extra = {} of String => Models::ExtraValue
          unknown_keys = [] of String
          if fm_hash = yaml_fm.as_h?
            fm_hash.each do |key_any, value|
              key = key_any.as_s?
              next unless key
              next if KNOWN_FRONT_MATTER_KEYS.includes?(key)
              if key == "extra" && (inner = value.as_h?)
                inner.each do |inner_key_any, inner_value|
                  inner_key = inner_key_any.as_s?
                  next unless inner_key
                  extra[inner_key] = extract_extra_value(inner_value)
                end
                next
              end
              unknown_keys << key
              extra[key] = extract_extra_value(value)
            end
          end
          warn_typo_keys(unknown_keys, file_path)

          front_matter_keys = yaml_fm.as_h?.try(&.keys).try { |ks| ks.compact_map(&.as_s?) } || [] of String
          taxonomies = extract_taxonomies(yaml_fm, front_matter_keys)
          tags = fm_string_array(yaml_fm, "tags")
          tags = taxonomies["tags"]? || tags if tags.empty?
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(yaml_fm, date, updated, extra, front_matter_keys, taxonomies, tags, file_path)
          result.merge({expires: expires})
        rescue ex : Hwaro::HwaroError
          raise ex
        rescue ex
          Logger.warn "Invalid YAML in #{file_path}: #{ex.message}" unless file_path.empty?
          nil
        end

        # Extract front matter fields from JSON content
        private def extract_from_json(raw : String, file_path : String)
          json_fm = begin
            JSON.parse(raw)
          rescue ex
            if file_path.empty?
              Logger.warn "Invalid JSON: #{ex.message}"
              return
            end
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "Invalid JSON frontmatter in #{file_path}: #{ex.message}",
              hint: "Check JSON frontmatter object at start of file",
            )
          end
          fm_hash = json_fm.as_h?
          return unless fm_hash

          date = parse_time(json_fm["date"]?.try(&.as_s?))
          updated = parse_time(json_fm["updated"]?.try(&.as_s?))
          expires = parse_time(json_fm["expires"]?.try(&.as_s?))

          extra = {} of String => Models::ExtraValue
          unknown_keys = [] of String
          fm_hash.each do |key, value|
            next if KNOWN_FRONT_MATTER_KEYS.includes?(key)
            if key == "extra" && (inner = value.as_h?)
              inner.each do |inner_key, inner_value|
                extra[inner_key] = extract_extra_value(inner_value)
              end
              next
            end
            unknown_keys << key
            extra[key] = extract_extra_value(value)
          end
          warn_typo_keys(unknown_keys, file_path)

          front_matter_keys = fm_hash.keys
          taxonomies = extract_taxonomies(json_fm, front_matter_keys)
          tags = fm_string_array(json_fm, "tags")
          tags = taxonomies["tags"]? || tags if tags.empty?
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(json_fm, date, updated, extra, front_matter_keys, taxonomies, tags, file_path)
          result.merge({expires: expires})
        rescue ex : Hwaro::HwaroError
          raise ex
        rescue ex
          Logger.warn "Invalid JSON in #{file_path}: #{ex.message}" unless file_path.empty?
          nil
        end

        # Shared helper: extract a Bool from a front matter value, returning the
        # given default when the key is absent or not a boolean.
        private def fm_bool(fm : TOML::Table | YAML::Any | JSON::Any, key : String, default : Bool) : Bool
          val = fm[key]?
          return default unless val
          bool_val = val.as_bool?
          bool_val.nil? ? default : bool_val
        end

        # Shared helper: extract a nilable Bool from a front matter value.
        private def fm_bool?(fm : TOML::Table | YAML::Any | JSON::Any, key : String) : Bool?
          fm[key]?.try(&.as_bool?)
        end

        # Shared helper: extract a nilable Int32 from a front matter value.
        private def fm_int?(fm : TOML::Table | YAML::Any | JSON::Any, key : String) : Int32?
          fm[key]?.try(&.as_i?)
        end

        # Shared helper: extract a String with a default from a front matter value.
        private def fm_string(fm : TOML::Table | YAML::Any | JSON::Any, key : String, default : String) : String
          fm[key]?.try(&.as_s?) || default
        end

        # Shared helper: extract a string array from a front matter value.
        # Uses compact_map(&.as_s?) instead of map(&.as_s) to safely skip
        # non-string elements rather than raising at runtime.
        private def fm_string_array(fm : TOML::Table | YAML::Any | JSON::Any, key : String) : Array(String)
          fm[key]?.try(&.as_a?.try { |a| a.compact_map(&.as_s?) }) || [] of String
        end

        # Build the front matter result NamedTuple from any front matter source.
        # This eliminates duplication between extract_from_toml, extract_from_yaml,
        # and extract_from_json.
        private def build_front_matter_result(
          fm : TOML::Table | YAML::Any | JSON::Any,
          date : Time?,
          updated : Time?,
          extra : Hash(String, Models::ExtraValue),
          front_matter_keys : Array(String),
          taxonomies : Hash(String, Array(String)),
          tags : Array(String),
          file_path : String = "",
        )
          # Authors may arrive via the top-level `authors` key or a Zola-style
          # `[taxonomies]` table — mirror the tags fallback at the call sites.
          authors = fm_string_array(fm, "authors")
          authors = taxonomies["authors"]? || authors if authors.empty?

          # Section [cascade] table — defaults inherited by descendant pages.
          cascade = {} of String => Models::ExtraValue
          if cascade_value = fm["cascade"]?
            if extracted = extract_extra_value(cascade_value).as?(Hash(String, Models::ExtraValue))
              cascade = extracted
            elsif !file_path.empty?
              Logger.warn "#{file_path}: `cascade` must be a table ([cascade] in TOML) — ignored."
            end
          end
          {
            title:          fm["title"]?.try(&.as_s?) || "Untitled",
            description:    fm["description"]?.try(&.as_s?),
            image:          fm["image"]?.try(&.as_s?),
            draft:          fm_bool(fm, "draft", false),
            template:       fm["template"]?.try(&.as_s?),
            in_sitemap:     fm_bool(fm, "in_sitemap", true),
            toc:            fm_bool(fm, "toc", false),
            date:           date,
            updated:        updated,
            render:         fm_bool(fm, "render", true),
            slug:           fm["slug"]?.try(&.as_s?),
            custom_path:    fm["path"]?.try(&.as_s?),
            aliases:        fm_string_array(fm, "aliases"),
            transparent:    fm_bool(fm, "transparent", false),
            generate_feeds: fm_bool(fm, "generate_feeds", false),
            # `paginate_by` is Zola's spelling (also exposed on `paginator` in
            # templates); accept it as an alias so migrated sites paginate
            # instead of silently rendering one unbounded page.
            paginate:            fm_int?(fm, "paginate") || fm_int?(fm, "paginate_by"),
            pagination_enabled:  fm_bool?(fm, "pagination_enabled"),
            sort_by:             fm["sort_by"]?.try(&.as_s?),
            reverse:             fm_bool?(fm, "reverse"),
            authors:             authors,
            extra:               extra,
            in_search_index:     fm_bool(fm, "in_search_index", true),
            insert_anchor_links: fm_bool(fm, "insert_anchor_links", false),
            page_template:       fm["page_template"]?.try(&.as_s?),
            paginate_path:       fm_string(fm, "paginate_path", "page"),
            redirect_to:         fm["redirect_to"]?.try(&.as_s?),
            weight:              fm_int?(fm, "weight") || 0,
            series:              fm["series"]?.try(&.as_s?),
            series_weight:       fm_int?(fm, "series_weight") || 0,
            expires:             nil.as(Time?),
            front_matter_keys:   front_matter_keys,
            taxonomies:          taxonomies,
            tags:                tags,
            cascade:             cascade,
            menus:               extract_menus(fm),
          }
        end

        # Recursively convert a front-matter value to `Models::ExtraValue`.
        # Preserves nested tables/maps as `Hash(String, ExtraValue)` so
        # `[extra.author] name = "x"` round-trips to `{{ page.extra.author.name }}`.
        # Arrays of all-strings stay as `Array(String)` so existing
        # `page.extra["x"]?.as?(Array(String))` consumers keep working.
        private def extract_extra_value(value : TOML::Any) : Models::ExtraValue
          if h = value.as_h?
            out = {} of String => Models::ExtraValue
            h.each { |k, v| out[k] = extract_extra_value(v) }
            out
          elsif arr = value.as_a?
            extract_extra_array(arr)
          elsif str = value.as_s?
            str
          elsif (bool_val = value.as_bool?) != nil
            bool_val.as(Bool)
          elsif int = value.as_i?
            int.to_i64
          elsif float = value.as_f?
            float
          else
            value.to_s
          end
        end

        private def extract_extra_value(value : YAML::Any) : Models::ExtraValue
          if h = value.as_h?
            out = {} of String => Models::ExtraValue
            h.each do |k_any, v|
              key = k_any.as_s? || k_any.to_s
              out[key] = extract_extra_value(v)
            end
            out
          elsif arr = value.as_a?
            extract_extra_array(arr)
          elsif str = value.as_s?
            str
          elsif (bool_val = value.as_bool?) != nil
            bool_val.as(Bool)
          elsif int = value.as_i64?
            int
          elsif float = value.as_f?
            float
          else
            value.to_s
          end
        end

        private def extract_extra_value(value : JSON::Any) : Models::ExtraValue
          if h = value.as_h?
            out = {} of String => Models::ExtraValue
            h.each { |k, v| out[k] = extract_extra_value(v) }
            out
          elsif arr = value.as_a?
            extract_extra_array(arr)
          elsif str = value.as_s?
            str
          elsif (bool_val = value.as_bool?) != nil
            bool_val.as(Bool)
          elsif int = value.as_i64?
            int
          elsif float = value.as_f?
            float
          else
            value.to_s
          end
        end

        # If every element is a plain string, preserve the `Array(String)` type
        # so downstream `.as?(Array(String))` calls (e.g. `jsonld.cr`) keep
        # matching. Mixed arrays widen to `Array(ExtraValue)`.
        private def extract_extra_array(arr : Array(TOML::Any) | Array(YAML::Any) | Array(JSON::Any)) : Array(String) | Array(Models::ExtraValue)
          if arr.all? { |v| !v.as_s?.nil? }
            arr.compact_map(&.as_s?)
          else
            arr.map { |v| extract_extra_value(v).as(Models::ExtraValue) }
          end
        end

        # Render with anchor links inserted into headings
        def render_with_anchors(content : String, highlight : Bool = true, safe : Bool = false, anchor_style : String = "heading", lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil) : Tuple(String, Array(Models::TocHeader))
          html, toc = render(content, highlight, safe, lazy_loading, emoji, markdown_config)
          html_with_anchors = insert_anchor_links_to_html(html, anchor_style)
          {html_with_anchors, toc}
        end

        # Insert anchor links into headings
        # Note: This modifies the HTML string directly since XML node manipulation is limited
        private def insert_anchor_links_to_html(html : String, style : String = "heading") : String
          return html unless html.includes?("<h")

          result = html

          # Match h1-h6 tags with id attributes and insert anchor links
          result = result.gsub(ANCHOR_LINK_REGEX) do |_|
            tag = $1
            attrs = $2
            id = $3
            content = $4

            anchor = %(<a class="anchor" href="##{id}" aria-hidden="true">🔗</a>)

            new_content = case style
                          when "before"
                            "#{anchor} #{content}"
                          when "after"
                            "#{content} #{anchor}"
                          else
                            content
                          end

            "<#{tag}#{attrs}>#{new_content}</#{tag}>"
          end

          result
        end

        # Lightweight regex-based post-processing.
        # Replaces the previous XML.parse_html approach which constructed a full
        # DOM tree for every page — very expensive for large sites.
        private def post_process_html(html : String, generate_toc : Bool, process_images : Bool) : Tuple(String, Array(Models::TocHeader))
          result = html

          # 1. Lazy-load images: add loading="lazy" to <img> tags missing it
          if process_images
            result = result.gsub(IMG_LAZY_REGEX) do |_|
              attrs = $1
              # Insert loading="lazy" before the closing /> or >
              "<img loading=\"lazy\"#{attrs} />"
            end
          end

          # 2. Extract TOC headers and inject missing id attributes
          roots = [] of Models::TocHeader

          if generate_toc
            stack = [] of Models::TocHeader
            used_ids = Set(String).new
            id_counters = Hash(String, Int32).new(0)

            result = result.gsub(HEADING_TAG_REGEX) do |match|
              tag_name = $1     # e.g. "h2"
              level = $2.to_i   # e.g. 2
              attrs = $3? || "" # existing attributes (may be empty)
              inner_html = $4   # inner content (may contain inline HTML)

              # Extract plain text for TOC title (inline char-level strip avoids regex + alloc)
              title = String.build(inner_html.bytesize) do |io|
                in_tag = false
                inner_html.each_char do |c|
                  if c == '<'
                    in_tag = true
                  elsif c == '>'
                    in_tag = false
                  elsif !in_tag
                    io << c
                  end
                end
              end.strip

              # Use existing id or generate one
              existing_id = if id_match = attrs.match(ID_ATTR_REGEX)
                              id_match[1]
                            end

              # The heading text reaches us entity-escaped (`&` → `&amp;` by
              # Markd); unescape before slugifying so "Tom & Jerry" gets the
              # id "tom-jerry", not "tom-amp-jerry". The TOC title keeps the
              # escaped form — both consumers (generate_toc_html and Crinja
              # with autoescape off) interpolate it into HTML verbatim.
              slug = Utils::TextUtils.slugify(HTML.unescape(title))
              id = existing_id || (slug.empty? ? "heading" : slug)

              # Ensure uniqueness using counter map for O(1) suffix lookup
              if used_ids.includes?(id)
                base_id = id
                id_counters[base_id] += 1
                id = "#{base_id}-#{id_counters[base_id]}"
                # Handle the rare case where the suffixed id also exists
                while used_ids.includes?(id)
                  id_counters[base_id] += 1
                  id = "#{base_id}-#{id_counters[base_id]}"
                end
              end
              used_ids << id

              permalink = "##{id}"

              toc_item = Models::TocHeader.new(
                level: level,
                id: id,
                title: title,
                permalink: permalink
              )

              # Build tree structure
              while stack.present? && stack.last.level >= level
                stack.pop
              end

              if stack.empty?
                roots << toc_item
              else
                stack.last.children << toc_item
              end
              stack.push(toc_item)

              # Rebuild the tag. When the heading already had an id and the
              # dedup loop didn't touch it, the original markup is returned
              # verbatim. Otherwise we rewrite — either replacing a duplicated
              # existing id with its suffixed form, or injecting a fresh id.
              if existing_id
                if id == existing_id
                  match
                else
                  new_attrs = attrs.sub(ID_ATTR_REGEX, %(id="#{id}"))
                  "<#{tag_name}#{new_attrs}>#{inner_html}</#{tag_name}>"
                end
              else
                "<#{tag_name}#{attrs} id=\"#{id}\">#{inner_html}</#{tag_name}>"
              end
            end
          end

          {result, roots}
        end

        # Apply emoji shortcode conversion to HTML, skipping <code> and <pre> blocks.
        #
        # Scans by BYTE offset rather than char index. The tag/fence markers
        # ('<', '>', '<code', '<pre', '</code>', '</pre>') and the ':' shortcode
        # delimiters are all ASCII, so byte offsets land exactly on the same
        # boundaries even for UTF-8 text. Char-indexed scanning (`html[pos]`,
        # `html.index(_, pos)`) is O(n) per access on any string containing a
        # multibyte codepoint, which turned this loop into O(n^2) — a single
        # accented/CJK character on a long page caused a ~1500x slowdown.
        private def apply_emoji(html : String) : String
          return html unless html.includes?(":")

          result = String::Builder.new(html.bytesize)
          bytes = html.to_slice
          len = bytes.size
          pos = 0
          lt = '<'.ord.to_u8

          while pos < len
            # Check for <code or <pre tags (bounded check avoids O(n) substring)
            if bytes[pos] == lt && pos + 1 < len
              is_code = pos + 5 <= len && bytes[pos, 5] == "<code".to_slice
              is_pre = !is_code && pos + 4 <= len && bytes[pos, 4] == "<pre".to_slice
              if is_code || is_pre
                close_tag = is_code ? "</code>" : "</pre>"
                end_pos = html.byte_index(close_tag, pos)
                if end_pos
                  block_end = end_pos + close_tag.bytesize
                  result.write(bytes[pos, block_end - pos])
                  pos = block_end
                  next
                end
              end
            end

            if bytes[pos] == lt
              # Inside a tag, don't transform
              tag_end = html.byte_index('>', pos)
              if tag_end
                result.write(bytes[pos, tag_end - pos + 1])
                pos = tag_end + 1
              else
                result.write_byte(bytes[pos])
                pos += 1
              end
            else
              # Text content — apply emoji conversion. Boundaries sit on ASCII
              # '<' marks, so byte_slice never splits a multibyte codepoint.
              next_tag = html.byte_index('<', pos + 1)
              chunk_end = next_tag || len
              result << Emoji.emojize(html.byte_slice(pos, chunk_end - pos))
              pos = chunk_end
            end
          end

          result.to_s
        end

        # Parse a TOML value that may be a native Time or a String
        private def parse_toml_time(val : TOML::Any?) : Time?
          return unless val
          raw = val.raw
          if raw.is_a?(Time)
            raw
          else
            parse_time(val.as_s?)
          end
        end

        # Parse a YAML value that may be a native Time or a String. An UNQUOTED
        # YAML date (`date: 2024-03-15`) resolves to a native Time node, so the
        # old `.as_s?` returned nil and silently dropped the date — breaking
        # sorting/feeds/sitemap. Mirrors parse_toml_time and content_lister.cr.
        private def parse_yaml_time(val : YAML::Any?) : Time?
          return unless val
          if t = val.as_time?
            t
          else
            parse_time(val.as_s?)
          end
        end

        private def parse_time(time_str : String?) : Time?
          return unless time_str
          str = time_str.strip
          return if str.empty?

          # Select format based on string pattern to avoid exception-based control flow
          fmt = if str.includes?('T')
                  # Could be RFC 3339 (with timezone) or plain ISO
                  if str.includes?('+') || str.includes?('Z') || str.matches?(/T.+-\d{2}:\d{2}$/) || str.matches?(/\d{2}-\d{2}$/)
                    begin
                      return Time.parse_rfc3339(str)
                    rescue Time::Format::Error | ArgumentError
                      "%Y-%m-%dT%H:%M:%S"
                    end
                  else
                    "%Y-%m-%dT%H:%M:%S"
                  end
                elsif str.size > 10
                  "%Y-%m-%d %H:%M:%S"
                else
                  "%Y-%m-%d"
                end

          begin
            Time.parse(str, fmt, Time::Location.local)
          rescue Time::Format::Error | ArgumentError
            # Time::Format::Error  → string doesn't match the format at all.
            # ArgumentError        → format matches but the value is out of
            #   range (e.g. "2024-13-45", "2024-02-30"). Both mean "no usable
            #   date" — return nil so the rest of the front matter survives
            #   instead of letting the exception unwind the whole parse.
            nil
          end
        end

        # Extract named-menu front-matter registrations. Accepts the plural
        # `menus` key (wins if both are present) or the singular alias
        # `menu`, in three shapes:
        #   - bare string:    `menus = "main"`
        #   - array of names: `menus = ["main", "footer"]`
        #   - table form:     `[menus.main]` with name/weight/parent/identifier
        # All fields in the table form are optional — the menu builder falls
        # back to the page's own title/weight/no-parent/name-as-identifier.
        private def extract_menus(fm : TOML::Table | YAML::Any | JSON::Any) : Hash(String, Models::MenuRegistration)
          registrations = {} of String => Models::MenuRegistration
          value = fm["menus"]? || fm["menu"]?
          return registrations unless value

          if name = value.as_s?
            registrations[name] = Models::MenuRegistration.new
            return registrations
          end

          if arr = value.as_a?
            arr.compact_map(&.as_s?).each do |menu_name|
              registrations[menu_name] = Models::MenuRegistration.new
            end
            return registrations
          end

          # Table form. TOML/JSON hashes keep String keys; YAML hashes are
          # keyed by YAML::Any (mirrors `extract_taxonomies` below).
          case value
          when TOML::Any, JSON::Any
            value.as_h?.try &.each do |menu_name, entry|
              registrations[menu_name] = menu_registration_from(entry)
            end
          when YAML::Any
            value.as_h?.try &.each do |menu_name_any, entry|
              next unless menu_name = menu_name_any.as_s?
              registrations[menu_name] = menu_registration_from(entry)
            end
          end

          registrations
        end

        # Builds a single `MenuRegistration` from one table-form `[menus.<name>]`
        # entry. Guards with `as_h?` first because `TOML::Any#[]?` /
        # `YAML::Any#[]?` / `JSON::Any#[]?` raise (rather than returning nil)
        # when the underlying value isn't a Hash — so a malformed
        # `menus.main = "oops"` degrades to all-defaults instead of crashing
        # the page parse.
        private def menu_registration_from(entry : TOML::Any | YAML::Any | JSON::Any) : Models::MenuRegistration
          return Models::MenuRegistration.new unless entry.as_h?

          Models::MenuRegistration.new(
            name: entry["name"]?.try(&.as_s?),
            weight: entry["weight"]?.try(&.as_i?),
            parent: entry["parent"]?.try(&.as_s?),
            identifier: entry["identifier"]?.try(&.as_s?),
          )
        end

        # Array-typed front matter keys that are NOT taxonomies.
        # These are excluded from automatic taxonomy extraction.
        NON_TAXONOMY_ARRAY_KEYS = Set{"tags", "aliases", "authors"}

        private def extract_taxonomies(front_matter : TOML::Table | YAML::Any | JSON::Any, keys : Array(String)) : Hash(String, Array(String))
          taxonomies = {} of String => Array(String)

          # Iterate all keys: TOML::Table yields {String, TOML::Any},
          # YAML::Any#as_h yields {YAML::Any, YAML::Any}. Unify via keys list.
          keys.each do |key|
            next if NON_TAXONOMY_ARRAY_KEYS.includes?(key)
            if arr = front_matter[key]?.try(&.as_a?)
              values = arr.compact_map(&.as_s?)
              taxonomies[key] = values
            end
          end

          # Zola compat: terms may also live under a `[taxonomies]` table
          # (`[taxonomies]` / `taxonomies:` followed by `tech = ["crystal"]`).
          # These used to fall through to `extra` silently. Nested entries
          # overwrite a same-named top-level array key here, but the call
          # sites re-assert explicit top-level `tags` afterwards, so for
          # `tags` the dedicated key still wins overall.
          if table = front_matter["taxonomies"]?
            case table
            when TOML::Any, JSON::Any
              table.as_h?.try &.each do |k, v|
                if arr = v.as_a?
                  taxonomies[k] = arr.compact_map(&.as_s?)
                end
              end
            when YAML::Any
              table.as_h?.try &.each do |k, v|
                next unless key_str = k.as_s?
                if arr = v.as_a?
                  taxonomies[key_str] = arr.compact_map(&.as_s?)
                end
              end
            end
          end

          taxonomies
        end
      end

      # Register the markdown processor by default
      Registry.register(Markdown.new)
    end
  end
end

# Backward compatibility module alias
module Hwaro
  module Processor
    module Markdown
      extend self

      # Create shared instance for module-level access
      @@instance = Content::Processors::Markdown.new

      # Renders Markdown to HTML and generates a Table of Contents
      # @param highlight - whether to enable syntax highlighting for code blocks
      # @param safe - if true, raw HTML will not be passed through (replaced by comments)
      # @param lazy_loading - if true, adds loading="lazy" to img tags
      # @param emoji - if true, converts emoji shortcodes to emoji characters
      def render(content : String, highlight : Bool = true, safe : Bool = false, lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil) : Tuple(String, Array(Models::TocHeader))
        @@instance.render(content, highlight, safe, lazy_loading, emoji, markdown_config)
      end

      # Memoized body render for the Generate-phase fallbacks: on warm
      # --cache builds (and in streaming mode) feeds and search hit pages
      # whose `page.content` is empty because the Render phase skipped
      # them, and the same page can be re-rendered up to four times in one
      # build (feed summary + full body + section feed + search index).
      # Output is a pure function of the raw content and the passed
      # options, so it is shared by content digest + options fingerprint.
      #
      # Callers should pass the site's markdown options so fallback bodies
      # match what the render phase produces (safe-mode HTML stripping,
      # emoji, extensions) instead of a default-options approximation.
      #
      # Mutex-guarded — feeds and search run as parallel fibers. The byte
      # cap keeps streaming mode's memory bound: once full, renders still
      # happen, they just stop being remembered.
      @@body_cache = {} of String => String
      @@body_cache_bytes = 0_i64
      @@body_cache_mutex = Mutex.new
      BODY_CACHE_MAX_BYTES = 32_i64 * 1024 * 1024

      def render_body_cached(content : String, safe : Bool = false, emoji : Bool = false, lazy_loading : Bool = false, markdown_config : Models::MarkdownConfig? = nil) : String
        key = String.build do |io|
          io << (safe ? '1' : '0') << (emoji ? '1' : '0') << (lazy_loading ? '1' : '0') << ':'
          io << Content::Processors::SyntaxHighlighter.body_fingerprint << ':'
          io << (markdown_config.try(&.cache_fingerprint) || "-") << ':'
          io << Digest::MD5.hexdigest(content)
        end
        @@body_cache_mutex.synchronize do
          if cached = @@body_cache[key]?
            return cached
          end
        end

        html, _ = render(content, safe: safe, lazy_loading: lazy_loading, emoji: emoji, markdown_config: markdown_config)

        @@body_cache_mutex.synchronize do
          unless @@body_cache.has_key?(key) || @@body_cache_bytes + html.bytesize > BODY_CACHE_MAX_BYTES
            @@body_cache[key] = html
            @@body_cache_bytes += html.bytesize
          end
        end
        html
      end

      # Returns parsed metadata and content
      def parse(raw_content : String, file_path : String = "")
        @@instance.parse(raw_content, file_path)
      end

      # Renders with anchor links injected into headings (delegates to shared instance)
      def render_with_anchors(content : String, highlight : Bool = true, safe : Bool = false, anchor_style : String = "heading", lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil) : Tuple(String, Array(Models::TocHeader))
        @@instance.render_with_anchors(content, highlight, safe, anchor_style, lazy_loading, emoji, markdown_config)
      end
    end
  end
end
