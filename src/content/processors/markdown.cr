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
require "./base"
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
        IMG_LAZY_REGEX = /<img(?![^>]*\bloading\s*=)([^>]*?)\s*\/?>/i
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
        # See `find_json_front_matter_end` for the brace scanner.

        # Known front-matter keys (shared between TOML, YAML, and JSON parsers).
        # Using a Set for O(1) lookup instead of Array#includes? O(n).
        KNOWN_FRONT_MATTER_KEYS = Set{
          "title", "description", "image", "draft", "template", "in_sitemap",
          "toc", "date", "updated", "render", "slug", "path", "aliases", "tags",
          "transparent", "generate_feeds", "paginate", "pagination_enabled",
          "sort_by", "reverse", "authors", "in_search_index", "insert_anchor_links",
          "page_template", "paginate_path", "redirect_to", "weight", "categories",
          "series", "series_weight", "expires",
        }

        # Warn about unknown front-matter keys that look like typos of known keys.
        # Uses Levenshtein distance ≤ 2 to detect likely misspellings while ignoring
        # intentional custom fields (which tend to differ significantly from known keys).
        private def warn_typo_keys(unknown_keys : Array(String), file_path : String)
          return if file_path.empty?
          unknown_keys.each do |key|
            KNOWN_FRONT_MATTER_KEYS.each do |known|
              dist = levenshtein(key, known)
              if dist > 0 && dist <= 2
                Logger.warn "#{file_path}: unknown front-matter key '#{key}' — did you mean '#{known}'?"
                break
              end
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
          # Pre-process markdown extensions (task lists, footnotes, etc.)
          processed = if md_cfg = markdown_config
                        MarkdownExtensions.preprocess(content, md_cfg)
                      else
                        content
                      end

          # Use SyntaxHighlighter for rendering with highlighting support
          html = SyntaxHighlighter.render(processed, highlight, safe)

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
        rescue
          # Fallback in case of XML parsing error
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
          elsif raw_content.starts_with?('{') && (end_idx = Utils::FrontmatterScanner.find_json_end(raw_content))
            result = extract_from_json(raw_content[0, end_idx], file_path)
            body = raw_content[end_idx..]
            markdown_content = body.lchop("\r\n").lchop("\n")
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
              extra:               {} of String => String | Bool | Int64 | Float64 | Array(String),
              in_search_index:     true,
              insert_anchor_links: false,
              page_template:       nil.as(String?),
              paginate_path:       "page",
              redirect_to:         nil.as(String?),
              weight:              0,
              series:              nil.as(String?),
              series_weight:       0,
              expires:             nil.as(Time?),
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

          extra = {} of String => String | Bool | Int64 | Float64 | Array(String)
          unknown_keys = [] of String
          toml_fm.each do |key, value|
            next if KNOWN_FRONT_MATTER_KEYS.includes?(key)
            unknown_keys << key
            extra[key] = extract_extra_value(value)
          end
          warn_typo_keys(unknown_keys, file_path)

          front_matter_keys = toml_fm.keys
          taxonomies = extract_taxonomies(toml_fm, front_matter_keys)
          tags = fm_string_array(toml_fm, "tags")
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(toml_fm, date, updated, extra, front_matter_keys, taxonomies, tags)
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

          date = parse_time(yaml_fm["date"]?.try(&.as_s?))
          updated = parse_time(yaml_fm["updated"]?.try(&.as_s?))
          expires = parse_time(yaml_fm["expires"]?.try(&.as_s?))

          extra = {} of String => String | Bool | Int64 | Float64 | Array(String)
          unknown_keys = [] of String
          if fm_hash = yaml_fm.as_h?
            fm_hash.each do |key_any, value|
              key = key_any.as_s?
              next unless key
              next if KNOWN_FRONT_MATTER_KEYS.includes?(key)
              unknown_keys << key
              extra[key] = extract_extra_value(value)
            end
          end
          warn_typo_keys(unknown_keys, file_path)

          front_matter_keys = yaml_fm.as_h?.try(&.keys).try { |ks| ks.compact_map(&.as_s?) } || [] of String
          taxonomies = extract_taxonomies(yaml_fm, front_matter_keys)
          tags = fm_string_array(yaml_fm, "tags")
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(yaml_fm, date, updated, extra, front_matter_keys, taxonomies, tags)
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
          return unless json_fm.as_h?

          date = parse_time(json_fm["date"]?.try(&.as_s?))
          updated = parse_time(json_fm["updated"]?.try(&.as_s?))
          expires = parse_time(json_fm["expires"]?.try(&.as_s?))

          extra = {} of String => String | Bool | Int64 | Float64 | Array(String)
          unknown_keys = [] of String
          json_fm.as_h.each do |key, value|
            next if KNOWN_FRONT_MATTER_KEYS.includes?(key)
            unknown_keys << key
            extra[key] = extract_extra_value(value)
          end
          warn_typo_keys(unknown_keys, file_path)

          front_matter_keys = json_fm.as_h.keys
          taxonomies = extract_taxonomies(json_fm, front_matter_keys)
          tags = fm_string_array(json_fm, "tags")
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(json_fm, date, updated, extra, front_matter_keys, taxonomies, tags)
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
          extra : Hash(String, String | Bool | Int64 | Float64 | Array(String)),
          front_matter_keys : Array(String),
          taxonomies : Hash(String, Array(String)),
          tags : Array(String),
        )
          {
            title:               fm["title"]?.try(&.as_s?) || "Untitled",
            description:         fm["description"]?.try(&.as_s?),
            image:               fm["image"]?.try(&.as_s?),
            draft:               fm_bool(fm, "draft", false),
            template:            fm["template"]?.try(&.as_s?),
            in_sitemap:          fm_bool(fm, "in_sitemap", true),
            toc:                 fm_bool(fm, "toc", false),
            date:                date,
            updated:             updated,
            render:              fm_bool(fm, "render", true),
            slug:                fm["slug"]?.try(&.as_s?),
            custom_path:         fm["path"]?.try(&.as_s?),
            aliases:             fm_string_array(fm, "aliases"),
            transparent:         fm_bool(fm, "transparent", false),
            generate_feeds:      fm_bool(fm, "generate_feeds", false),
            paginate:            fm_int?(fm, "paginate"),
            pagination_enabled:  fm_bool?(fm, "pagination_enabled"),
            sort_by:             fm["sort_by"]?.try(&.as_s?),
            reverse:             fm_bool?(fm, "reverse"),
            authors:             fm_string_array(fm, "authors"),
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
          }
        end

        # Extract extra value from TOML::Any, YAML::Any, or JSON::Any
        private def extract_extra_value(value : TOML::Any | YAML::Any | JSON::Any) : String | Bool | Int64 | Float64 | Array(String)
          if str = value.as_s?
            str
          elsif (bool_val = value.as_bool?) != nil
            bool_val.as(Bool)
          elsif int = value.as_i?
            int.to_i64
          elsif float = value.as_f?
            float
          elsif arr = value.as_a?
            arr.compact_map(&.as_s?)
          else
            value.to_s
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

              slug = Utils::TextUtils.slugify(title)
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

              # Rebuild the tag, injecting id if it was missing
              if existing_id
                match # Return unchanged
              else
                "<#{tag_name}#{attrs} id=\"#{id}\">#{inner_html}</#{tag_name}>"
              end
            end
          end

          {result, roots}
        end

        # Apply emoji shortcode conversion to HTML, skipping <code> and <pre> blocks
        private def apply_emoji(html : String) : String
          return html unless html.includes?(":")

          result = String::Builder.new(html.bytesize)
          pos = 0
          len = html.size

          while pos < len
            # Check for <code or <pre tags (bounded check avoids O(n) substring)
            if html[pos] == '<' && pos + 1 < len
              is_code = pos + 5 <= len && html[pos, 5] == "<code"
              is_pre = !is_code && pos + 4 <= len && html[pos, 4] == "<pre"
              if is_code || is_pre
                close_tag = is_code ? "</code>" : "</pre>"
                end_pos = html.index(close_tag, pos)
                if end_pos
                  block_end = end_pos + close_tag.size
                  result << html[pos, block_end - pos]
                  pos = block_end
                  next
                end
              end
            end

            # Find next tag or end
            next_tag = html.index('<', pos + 1)
            chunk_end = next_tag || len

            if html[pos] == '<'
              # Inside a tag, don't transform
              tag_end = html.index('>', pos)
              if tag_end
                result << html[pos..tag_end]
                pos = tag_end + 1
              else
                result << html[pos]
                pos += 1
              end
            else
              # Text content — apply emoji conversion
              chunk = html[pos...chunk_end]
              result << Emoji.emojize(chunk)
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
                    rescue
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
          rescue
            nil
          end
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

      # Returns parsed metadata and content
      def parse(raw_content : String, file_path : String = "")
        @@instance.parse(raw_content, file_path)
      end
    end
  end
end
