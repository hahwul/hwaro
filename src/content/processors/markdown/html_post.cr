# Markdown processor — post-render HTML passes (heading anchors, lazy images, emoji).
#
# Reopens `Processors::Markdown`; the part require order and the processor
# registration live in ../markdown.cr. Parts only reopen the class: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      class Markdown < Base
        # Regex for matching h1-h6 tags with IDs to insert anchor links.
        # Attribute scans here and below are quote-aware (a `>` inside a
        # quoted value, e.g. title="a > b", is legal HTML5 and must not end
        # the tag) and the `id` key uses a `(?<![\w-])` guard so `data-id=`
        # never counts as the element's id.
        ANCHOR_LINK_REGEX = /<(h[1-6])((?:[^>"']|"[^"]*"|'[^']*')*?(?<![\w-])id="([^"]+)"(?:[^>"']|"[^"]*"|'[^']*')*)>(.*?)<\/\1>/m

        # Regex for post_process_html — lightweight replacements for XML.parse_html
        # Matches <h1>…</h1> through <h6>…</h6>, capturing tag name, level digit, attributes, and inner HTML
        # The inner group is `.*?`, not `.+?`: an EMPTY heading (`##` with no
        # text, or one whose only content was a stripped `{#id}` block) must
        # still match on its own. With `.+?` the empty `<h2></h2>` could not
        # match, so the scan slid on and paired that opening tag with the NEXT
        # heading's `</h2>` — handing the empty heading the following
        # heading's id and leaving the real one with none, which also broke
        # the render-hooks convergence invariant (HookedRenderer#heading gets
        # this right).
        HEADING_TAG_REGEX = /<(h([1-6]))(\s(?:[^>"']|"[^"]*"|'[^']*')*)?>(.*?)<\/h\2>/mi
        # Matches <img ...> tags that do NOT already have a loading= attribute
        # (the lookahead is quote-aware too, so a loading= sitting after a
        # quoted `>` is still seen, and `data-loading=` doesn't count).
        IMG_LAZY_REGEX = /<img(?!(?:[^>"']|"[^"]*"|'[^']*')*(?<![\w-])loading\s*=)((?:[^>"']|"[^"]*"|'[^']*')*?)\s*\/?>/i
        # Extracts id="value" from an attribute string
        ID_ATTR_REGEX = /(?<![\w-])id\s*=\s*["']([^"']+)["']/

        # Render with anchor links inserted into headings
        def render_with_anchors(content : String, highlight : Bool = true, safe : Bool = false, anchor_style : String = "heading", lazy_loading : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil,
                                hooks : Content::Processors::RenderHooks::HookRenderContext? = nil) : Tuple(String, Array(Models::TocHeader))
          html, toc = render(content, highlight, safe, lazy_loading, emoji, markdown_config, hooks: hooks)
          html_with_anchors = insert_anchor_links_to_html(html, anchor_style)
          {html_with_anchors, toc}
        end

        # Byte spans covered by `<!-- … -->` comments in the rendered HTML.
        #
        # A heading that lives inside a comment is invisible in the browser, so
        # the heading passes below must leave it alone: otherwise a
        # commented-out section shows up in the VISIBLE table of contents and
        # links to an anchor the reader can never reach, and the comment body
        # gets an `id=` and a 🔗 anchor injected into it. Headings inside fenced
        # code blocks and code spans are already immune — markd entity-escapes
        # `<` there, so `&lt;h2&gt;` never matches and `&lt;!--` never opens a
        # span here either.
        private def html_comment_spans(html : String) : Array(Range(Int32, Int32))
          spans = [] of Range(Int32, Int32)
          pos = 0
          while open = html.byte_index("<!--", pos)
            close = html.byte_index("-->", open + 4)
            # An UNTERMINATED `<!--` is deliberately NOT treated as a comment
            # running to end of input. In practice a lone `<!--` this deep in
            # rendered HTML is far more likely to be a stray sequence inside a
            # raw attribute value — which browsers do not treat as a comment at
            # all — than a runaway comment, and masking to EOF there would strip
            # ids and TOC entries from headings that render perfectly well.
            break unless close
            spans << (open...(close + 3))
            pos = close + 3
          end
          spans
        end

        # True when a match starting at `offset` (a BYTE offset, as reported by
        # `Regex::MatchData#byte_begin`) opens inside one of `spans`.
        private def in_comment?(spans : Array(Range(Int32, Int32)), offset : Int32) : Bool
          spans.any?(&.includes?(offset))
        end

        # Insert anchor links into headings
        # Note: This modifies the HTML string directly since XML node manipulation is limited
        private def insert_anchor_links_to_html(html : String, style : String = "heading") : String
          return html unless html.includes?("<h")

          result = html

          # A page with no comment at all costs one extra `byte_index` scan
          # here and an empty array to test against per heading.
          comment_spans = html_comment_spans(html)

          # Match h1-h6 tags with id attributes and insert anchor links
          result = result.gsub(ANCHOR_LINK_REGEX) do |match|
            # Never inject a 🔗 anchor into a heading that only exists inside
            # an HTML comment (see `html_comment_spans`).
            next match if in_comment?(comment_spans, $~.byte_begin(0))

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

            # Spans are measured against the post-lazy-load `result`, which is
            # exactly the string this gsub scans, so the byte offsets line up.
            comment_spans = html_comment_spans(result)

            result = result.gsub(HEADING_TAG_REGEX) do |match|
              # A commented-out heading is invisible: it gets no id, and no TOC
              # entry (see `html_comment_spans`).
              next match if in_comment?(comment_spans, $~.byte_begin(0))

              tag_name = $1     # e.g. "h2"
              level = $2.to_i   # e.g. 2
              attrs = $3? || "" # existing attributes (may be empty)
              inner_html = $4   # inner content (may contain inline HTML)

              # Extract plain text for TOC title (inline char-level strip
              # avoids regex + alloc). Quote-aware: a `>` inside a quoted
              # attribute value must not end the tag, or the value's tail
              # leaks into the title.
              title = String.build(inner_html.bytesize) do |io|
                in_tag = false
                quote = nil.as(Char?)
                inner_html.each_char do |c|
                  if in_tag
                    if quote
                      quote = nil if c == quote
                    elsif c == '"' || c == '\''
                      quote = c
                    elsif c == '>'
                      in_tag = false
                    end
                  elsif c == '<'
                    in_tag = true
                  else
                    io << c
                  end
                end
              end.strip

              # Use existing id or generate one
              existing_id = if id_match = attrs.match(ID_ATTR_REGEX)
                              id_match[1]
                            end

              # The TOC title keeps the escaped form — both consumers
              # (generate_toc_html and Crinja with autoescape off)
              # interpolate it into HTML verbatim; slugify/unescape happen
              # inside HeadingIds.assign.
              id = HeadingIds.assign(title, existing_id, used_ids, id_counters)

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
                  # `backreferences: false`: `id` derives from the author's own
                  # `id="..."` attribute (plus a dedup suffix) and may contain a
                  # backslash. `String#sub(Regex, String)` expands `\0`-`\9` and
                  # `\k<name>` inside the REPLACEMENT, so two headings sharing
                  # an id like `a\k<x>` would raise `IndexError` mid-render and
                  # abort the build, while `a\1` would silently lose the `\1`.
                  new_attrs = attrs.sub(ID_ATTR_REGEX, %(id="#{id}"), backreferences: false)
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
      end
    end
  end
end
