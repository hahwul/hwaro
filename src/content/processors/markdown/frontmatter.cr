# Markdown processor — front matter detection, TOML/YAML/JSON extraction and typed field access.
#
# Reopens `Processors::Markdown`; the part require order and the processor
# registration live in ../markdown.cr. Parts only reopen the class: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      class Markdown < Base
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

        # Returns parsed metadata and content
        def parse(raw_content : String, file_path : String = "")
          # A UTF-8 BOM would defeat every `\A`-anchored fence below and the
          # leading-`{` JSON test, silently turning the front matter into body
          # text. Strip it first so BOM'd files parse like any other.
          raw_content = Utils::TextUtils.strip_bom(raw_content)
          markdown_content = raw_content

          # Try TOML (+++), YAML (---), then JSON ({...}) front matter.
          # The body is only truncated to match[2] when the fenced block really
          # WAS front matter: `---` doubles as a Markdown thematic break, so a
          # document opening with one (scalar/sequence YAML, or invalid YAML
          # with no `key:` line) must keep its FULL content — assigning
          # match[2] up front silently dropped the first block.
          if match = raw_content.match(TOML_FRONT_MATTER_REGEX)
            if result = extract_from_toml(match[1], file_path)
              markdown_content = match[2]
            end
          elsif match = raw_content.match(YAML_FRONT_MATTER_REGEX)
            if result = extract_from_yaml(match[1], file_path)
              markdown_content = match[2]
            elsif yaml_empty_front_matter?(match[1])
              # `---\n---` / comment-only blocks are EMPTY front matter:
              # strip the fences and fall through to defaults.
              markdown_content = match[2]
            end
          elsif raw_content.starts_with?('{') && json_front_matter_start?(raw_content)
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
              insert_anchor_links: nil.as(Bool?),
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

        # A `{` also opens shortcodes (`{{ … }}`), Jinja tags (`{% … %}`) and
        # attribute lists (`{:.class}`) — constructs that legitimately start a
        # body. Only a `"` (first key) or `}` (empty object) after the leading
        # brace plausibly starts a JSON front-matter object; anything else is
        # content, not a broken JSON header worth aborting the build over.
        private def json_front_matter_start?(raw : String) : Bool
          reader = Char::Reader.new(raw)
          reader.next_char # skip the leading '{'
          while reader.has_next?
            ch = reader.current_char
            return true if ch == '"' || ch == '}'
            return false unless ch.whitespace?
            reader.next_char
          end
          false
        end

        # A top-level `key:` line is what distinguishes broken front matter
        # (worth a hard error) from a document that merely opens with a `---`
        # thematic break (whose first block may fail YAML parsing entirely).
        # `\p{L}` so non-ASCII keys (e.g. Korean `제목:`) count as front
        # matter too — otherwise their invalid-YAML blocks silently render
        # as body text instead of erroring.
        YAML_KEY_LINE_RE = /^[\p{L}_][\p{L}\p{N}_.-]*\s*:(\s|$)/

        private def yaml_front_matter_like?(raw : String) : Bool
          raw.each_line do |line|
            return true if line.matches?(YAML_KEY_LINE_RE)
          end
          false
        end

        # True when the fenced block parses to YAML null — `---\n---` and
        # comment-only blocks. Those are empty front matter (fences stripped),
        # unlike scalar/sequence blocks, which are document content. A
        # null-parse alone is not enough: `~` / `null` scalars ALSO parse to
        # nil but are content, so the raw text must carry nothing beyond
        # whitespace and comments.
        private def yaml_empty_front_matter?(raw : String) : Bool
          return false unless YAML.parse(raw).raw.nil?
          raw.each_line.all? do |line|
            stripped = line.strip
            stripped.empty? || stripped.starts_with?('#')
          end
        rescue
          false
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

          date = parse_toml_time(toml_fm["date"]?, "date", file_path)
          updated = parse_toml_time(toml_fm["updated"]?, "updated", file_path)
          expires = parse_toml_time(toml_fm["expires"]?, "expires", file_path)

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
          tags = fm_string_array(toml_fm, "tags", file_path)
          tags = taxonomies["tags"]? || tags if tags.empty?
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(toml_fm, date, updated, extra, front_matter_keys, taxonomies, tags, file_path)
          result.merge({expires: expires})
        rescue ex : Hwaro::HwaroError
          raise ex
        rescue ex
          # Reaching here means the fence PARSED as TOML but a value could not
          # be converted. Degrading to nil tells the caller "this file has no
          # front matter", which is the worst possible answer: `draft = true`
          # is lost so the page ships, and the raw `+++` block is rendered as
          # body text. Fail with a classified content error instead. Library
          # use (no file_path) keeps the graceful nil.
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
            # A document opening with a `---` thematic break can put ANY prose
            # in the "front matter" slot; only abort when the block plausibly
            # is front matter (carries a top-level `key:` line). Otherwise the
            # caller keeps the full content as body text.
            return unless yaml_front_matter_like?(raw)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "Invalid YAML frontmatter in #{file_path}: #{ex.message}",
              hint: "Check YAML frontmatter between `---` fences",
            )
          end
          return unless yaml_fm.as_h?

          date = parse_yaml_time(yaml_fm["date"]?, "date", file_path)
          updated = parse_yaml_time(yaml_fm["updated"]?, "updated", file_path)
          expires = parse_yaml_time(yaml_fm["expires"]?, "expires", file_path)

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
          tags = fm_string_array(yaml_fm, "tags", file_path)
          tags = taxonomies["tags"]? || tags if tags.empty?
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(yaml_fm, date, updated, extra, front_matter_keys, taxonomies, tags, file_path)
          result.merge({expires: expires})
        rescue ex : Hwaro::HwaroError
          raise ex
        rescue ex
          # The block already parsed into a YAML mapping (see the `as_h?` guard
          # above), so this is a value-conversion failure, not a "maybe it was
          # a thematic break" case. Silently returning nil would drop `draft`,
          # date and taxonomies and publish the raw `---` block as body text.
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

          date = parse_time(json_fm["date"]?.try(&.as_s?), "date", file_path)
          updated = parse_time(json_fm["updated"]?.try(&.as_s?), "updated", file_path)
          expires = parse_time(json_fm["expires"]?.try(&.as_s?), "expires", file_path)

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
          tags = fm_string_array(json_fm, "tags", file_path)
          tags = taxonomies["tags"]? || tags if tags.empty?
          taxonomies["tags"] = tags if tags.present?

          result = build_front_matter_result(json_fm, date, updated, extra, front_matter_keys, taxonomies, tags, file_path)
          result.merge({expires: expires})
        rescue ex : Hwaro::HwaroError
          raise ex
        rescue ex
          # Same reasoning as the TOML/YAML extractors: the object parsed, so a
          # failure here is a value-conversion problem and must not masquerade
          # as "no front matter" (which would publish drafts verbatim).
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
          fm[key]?.try { |val| fm_int_value?(val) }
        end

        # Narrow a single front matter number to Int32.
        #
        # Goes through the 64-bit accessor and clamps, mirroring
        # `Models::Config#int_value`: `as_i?` on TOML/YAML/JSON `Any` is a TYPE
        # guard with no RANGE guard (`@raw.as(Int).to_i`), so `weight =
        # 3000000000` — perfectly valid TOML/YAML, in range for the Int64 these
        # parsers actually produce — raised OverflowError from a *nil-safe*
        # accessor. That unwound the whole front matter extraction, and the
        # document was then treated as having NO front matter at all: `draft`,
        # title, date and taxonomies were lost in one go and a draft page
        # shipped with its raw `+++` block rendered as body text.
        private def fm_int_value?(value : TOML::Any | YAML::Any | JSON::Any) : Int32?
          value.as_i64?.try(&.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32)
        end

        # Shared helper: extract a String with a default from a front matter value.
        private def fm_string(fm : TOML::Table | YAML::Any | JSON::Any, key : String, default : String) : String
          fm[key]?.try(&.as_s?) || default
        end

        # `paginate_path` is used twice over, unescaped: the render phase joins
        # it into `<output>/<section>/<paginate_path>/<n>/index.html`, and the
        # paginator interpolates the same string into `paginator.next`/`last`.
        # A traversing value (`"../.."`) therefore made the output-dir guard
        # refuse every pager write — and that guard is silent — while the
        # section index still advertised `/blog/../../2/` as the only link to
        # the pages that were never written. An empty value wrote the pagers
        # but advertised `/blog//2/`. Normalize to safe path segments and fall
        # back to the documented default rather than ship either shape.
        private def fm_paginate_path(fm : TOML::Table | YAML::Any | JSON::Any, file_path : String) : String
          raw = fm_string(fm, "paginate_path", "page")
          segments, refused = Utils::PathUtils.split_safe_segments(raw)
          if refused || segments.empty?
            Logger.warn "#{file_path}: `paginate_path` #{raw.inspect} is not a usable path segment — using \"page\"." unless file_path.empty?
            return "page"
          end
          segments.join("/")
        end

        # Shared helper: extract a nilable String from a front matter value.
        #
        # A non-string scalar (`title = 2024`, `slug = 7`) used to be dropped in
        # silence, so the page shipped as "Untitled" with no slug and no hint of
        # why — and that bogus title propagated into <title>, feeds, llms.txt
        # and every listing. Warn in the same shape as the `cascade` type
        # warning below, but stay quiet for an explicitly empty key
        # (`description:` with no value), which is a placeholder rather than a
        # type mistake. The value is still ignored: this classifies the mistake,
        # it does not coerce it, so output for valid front matter is unchanged.
        private def fm_string?(fm : TOML::Table | YAML::Any | JSON::Any, key : String, file_path : String = "") : String?
          val = fm[key]?
          return unless val
          if str = val.as_s?
            return str
          end
          Logger.warn "#{file_path}: `#{key}` must be a string — ignored." unless file_path.empty? || val.raw.nil?
          nil
        end

        # Shared helper: extract a string array from a front matter value.
        # Uses compact_map(&.as_s?) instead of map(&.as_s) to safely skip
        # non-string elements rather than raising at runtime.
        #
        # Values are stripped: a tag authored as `"  crystal  "` must be the
        # SAME term as `"crystal"` — untrimmed values leaked verbatim into
        # term-page titles/RSS and split one term into two slug-disambiguated
        # term pages (slugification already trimmed; identity/display didn't).
        #
        # …and then dropped when empty. An entry that is blank or all
        # whitespace has no publishable identity: the taxonomy generator
        # already skips it (no `/tags/<slug>/` page is ever written), so
        # keeping it in `page.tags` only let templates render a term whose
        # page does not exist — the stock scaffold's tag list emitted
        # `<a class="tag" href="/tags/term-/"></a>`, an empty anchor pointing
        # at a 404. `aliases` shares this helper and wants the same rule: a
        # blank alias normalizes to `/`, which then loses a collision warning
        # against the homepage instead of quietly doing nothing.
        #
        # A bare scalar (`tags = "solo"`) is NOT silently coerced to a
        # one-element list — that would invent taxonomy term pages for sites
        # that build fine today — but it is no longer silent either: the key is
        # named in a warning so the author sees why the list came out empty.
        private def fm_string_array(fm : TOML::Table | YAML::Any | JSON::Any, key : String, file_path : String = "") : Array(String)
          val = fm[key]?
          return [] of String unless val
          if arr = val.as_a?
            return arr.compact_map(&.as_s?).map(&.strip).reject(&.empty?)
          end
          Logger.warn "#{file_path}: `#{key}` must be a list of strings — ignored." unless file_path.empty? || val.raw.nil?
          [] of String
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
          authors = fm_string_array(fm, "authors", file_path)
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
            title:          fm_string?(fm, "title", file_path) || "Untitled",
            description:    fm_string?(fm, "description", file_path),
            image:          fm_string?(fm, "image", file_path),
            draft:          fm_bool(fm, "draft", false),
            template:       fm_string?(fm, "template", file_path),
            in_sitemap:     fm_bool(fm, "in_sitemap", true),
            toc:            fm_bool(fm, "toc", false),
            date:           date,
            updated:        updated,
            render:         fm_bool(fm, "render", true),
            slug:           fm_string?(fm, "slug", file_path),
            custom_path:    fm_string?(fm, "path", file_path),
            aliases:        fm_string_array(fm, "aliases", file_path),
            transparent:    fm_bool(fm, "transparent", false),
            generate_feeds: fm_bool(fm, "generate_feeds", false),
            # `paginate_by` is Zola's spelling (also exposed on `paginator` in
            # templates); accept it as an alias so migrated sites paginate
            # instead of silently rendering one unbounded page.
            paginate:            fm_int?(fm, "paginate") || fm_int?(fm, "paginate_by"),
            pagination_enabled:  fm_bool?(fm, "pagination_enabled"),
            sort_by:             fm_string?(fm, "sort_by", file_path),
            reverse:             fm_bool?(fm, "reverse"),
            authors:             authors,
            extra:               extra,
            in_search_index:     fm_bool(fm, "in_search_index", true),
            insert_anchor_links: fm_bool?(fm, "insert_anchor_links"),
            page_template:       fm_string?(fm, "page_template", file_path),
            paginate_path:       fm_paginate_path(fm, file_path),
            redirect_to:         fm_string?(fm, "redirect_to", file_path),
            weight:              fm_int?(fm, "weight") || 0,
            series:              fm_string?(fm, "series", file_path),
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
        private def extract_extra_value(value : TOML::Any, depth : Int32 = 0) : Models::ExtraValue
          Utils::Nesting.check!(depth)
          if h = value.as_h?
            out = {} of String => Models::ExtraValue
            h.each { |k, v| out[k] = extract_extra_value(v, depth + 1) }
            out
          elsif arr = value.as_a?
            extract_extra_array(arr, depth)
          elsif str = value.as_s?
            str
          elsif (bool_val = value.as_bool?) != nil
            bool_val.as(Bool)
          elsif int = value.as_i64?
            # 64-bit accessor, matching the YAML/JSON siblings below: `as_i?`
            # raised OverflowError on `[extra] build_id = 1755043200000` and
            # took the entire front matter down with it.
            int
          elsif float = value.as_f?
            float
          else
            value.to_s
          end
        end

        # `depth` exists for the YAML overload's sake above all: a
        # self-referencing anchor (`x: &a\n  b: *a`) parses fine and yields a
        # CYCLIC `YAML::Any`, so this walk never terminates on its own. See
        # `Utils::Nesting`; `extract_from_yaml` converts the raise into the
        # usual HWARO_E_CONTENT front-matter error.
        private def extract_extra_value(value : YAML::Any, depth : Int32 = 0) : Models::ExtraValue
          Utils::Nesting.check!(depth)
          if h = value.as_h?
            out = {} of String => Models::ExtraValue
            h.each do |k_any, v|
              key = k_any.as_s? || k_any.to_s
              out[key] = extract_extra_value(v, depth + 1)
            end
            out
          elsif arr = value.as_a?
            extract_extra_array(arr, depth)
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

        private def extract_extra_value(value : JSON::Any, depth : Int32 = 0) : Models::ExtraValue
          Utils::Nesting.check!(depth)
          if h = value.as_h?
            out = {} of String => Models::ExtraValue
            h.each { |k, v| out[k] = extract_extra_value(v, depth + 1) }
            out
          elsif arr = value.as_a?
            extract_extra_array(arr, depth)
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
        private def extract_extra_array(arr : Array(TOML::Any) | Array(YAML::Any) | Array(JSON::Any), depth : Int32 = 0) : Array(String) | Array(Models::ExtraValue)
          if arr.all? { |v| !v.as_s?.nil? }
            arr.compact_map(&.as_s?)
          else
            arr.map { |v| extract_extra_value(v, depth + 1).as(Models::ExtraValue) }
          end
        end
      end
    end
  end
end
