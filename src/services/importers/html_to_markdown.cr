require "xml"
require "../../utils/logger"
require "../../content/processors/inline_markdown"

module Hwaro
  module Services
    module Importers
      # Lightweight HTML-to-Markdown converter.
      # Handles common HTML elements produced by WordPress and other CMS exports.
      module HtmlToMarkdown
        # Above this size the regex pipeline's lazy quantifiers (e.g. the anchor
        # body `(.*?)</a>`) degrade to O(n^2) on adversarial markup (many
        # unclosed tags). Imported exports are untrusted, so fall back to a
        # cheap linear tag-strip rather than spend minutes of CPU on a single
        # crafted item. The threshold is far above any real blog post.
        MAX_REGEX_HTML_BYTES = 4 * 1024 * 1024

        # Longest anchor TEXT the link conversion will match. Bounding the lazy
        # body is what actually makes an unclosed-anchor document linear — see
        # the anchor pass below. Far above any real inline link.
        #
        # The bound is needed exactly where a pass's tail carries MORE THAN
        # ONE closing literal (the anchor pass: `["'][^>]*>` then `</a>`;
        # the pre+code pass: `</code>` then `</pre>`). A failed attempt then
        # rescans between the literals from every opening tag — measured
        # O(n^2), minutes of CPU inside the 4 MB cap. Passes whose tail is a
        # SINGLE closing literal (`(.*?)</p>` and friends) are deliberately
        # left open: PCRE2 satisfies those in linear time (the required-
        # literal scan is memoized across bump-along attempts), and bounding
        # them defeats that optimization — measured ~200x SLOWER on
        # unclosed-tag spam with a `{0,n}?` body than with `(.*?)`.
        MAX_INLINE_BODY_CHARS = 4096

        # Longest <pre><code> body the fenced-code pass will match — the
        # bounded-lazy-body treatment for the one other multi-literal-tail
        # pass (see MAX_INLINE_BODY_CHARS above), sized up because real code
        # samples run far longer than inline spans. 65535 is PCRE2's {n,m}
        # quantifier ceiling. An over-long body keeps its text: the plain
        # `<pre>` pass right after has a single-literal tail and no bound.
        MAX_CODE_BODY_CHARS = 65_535

        # Innermost-list matcher (see the list pass below). The body is
        # consumed in CHUNKS — possessive runs of non-`<` plus single `<`
        # guarded against opening a nested list — rather than the previous
        # per-character `(?:(?!<[uo]l[^>]*>).)*?`: PCRE2's JIT pushes a
        # backtrack frame per lazy iteration onto a fixed-size JIT stack,
        # and per-character iteration crashed the whole conversion with
        # "JIT stack limit reached" on list bodies only a few thousand
        # characters long. Chunking makes the frame count scale with the
        # number of tags instead of characters; the language matched is
        # identical (only `<` could ever start a nested-list open, and a
        # match can only ever end before the `<` of the closing tag, which
        # is always a chunk boundary). A `{0,n}` bound is no alternative —
        # PCRE2 unrolls bounded GROUP repeats and the pattern blows the
        # compile-size limit. A tag-spam body can still overflow the JIT
        # stack, which raises Regex::Error — `convert` catches that and
        # falls back to the linear tag strip.
        INNERMOST_LIST_RE = /<(ul|ol)[^>]*>((?:[^<]++|<(?![uo]l[^>]*>))*?)<\/\1>/mi

        # Maximum innermost-list conversion passes (one per nesting level).
        # Real content nests a handful of levels; a crafted thousand-deep
        # nest costs a full-document gsub per level, so cap it — deeper
        # levels fall through to `strip_tags`, which keeps their text.
        MAX_LIST_PASSES = 64

        # Cheap short-circuit for the anchor pass: a document with no closing
        # anchor tag has no link to convert. Exposed so the skip is assertable
        # without a wall-clock measurement.
        ANCHOR_CLOSE_RE = /<\/a>/i
        ANCHOR_RE       = Regex.new(
          "<a[^>]*\\bhref=[\"']([^\"']+)[\"'][^>]*>(.{0,#{MAX_INLINE_BODY_CHARS}}?)</a>",
          Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE
        )

        # True when `convert` will run the (bounded) anchor conversion pass on
        # this document.
        def self.anchor_pass_applicable?(html : String) : Bool
          html.matches?(ANCHOR_CLOSE_RE)
        end

        def self.convert(html : String) : String
          return "" if html.empty?

          if html.bytesize > MAX_REGEX_HTML_BYTES
            Logger.warn "HTML content is very large (#{html.bytesize} bytes); converting as plain text to avoid excessive processing time."
            return strip_to_text(html)
          end

          convert_via_regexes(html)
        rescue Regex::Error
          # Belt and suspenders: pathological markup can still error inside
          # PCRE2 (e.g. "JIT stack limit reached") despite the bounded
          # passes. Fall back to the same linear tag strip as the size cap
          # rather than dropping the whole item.
          Logger.warn "HTML content is too complex to convert; converting as plain text."
          strip_to_text(html)
        end

        # The plain-text fallback shared by the size cap and the
        # Regex::Error rescue in `convert`: linear tag strip, no Markdown.
        private def self.strip_to_text(html : String) : String
          html.gsub(/<[^>]*>/, " ").gsub(/[ \t]+/, " ").strip
        end

        private def self.convert_via_regexes(html : String) : String
          result = html

          # Normalize line endings
          result = result.gsub("\r\n", "\n")

          # Convert block elements first (order matters).
          #
          # Lazy-body policy: a pass whose tail is a single closing literal
          # keeps an open `(.*?)` body — linear under PCRE2, and bounding it
          # is a measured ~200x regression. A pass with a multi-literal tail
          # is bounded. See the MAX_INLINE_BODY_CHARS comment.

          # Headings
          (1..6).each do |level|
            prefix = "#" * level
            result = result.gsub(/<h#{level}[^>]*>(.*?)<\/h#{level}>/mi) { "#{prefix} #{$1.strip}\n\n" }
          end

          # Code blocks: <pre><code>...</code></pre> or <pre>...</pre>.
          # Stash the finished fences behind placeholders until the very end:
          # every later pass (lists, <p>, <a>, strip_tags, the final entity
          # decode) would otherwise run INSIDE the code sample, converting or
          # stripping the HTML it demonstrates and double-decoding entities.
          code_stash = [] of String
          # Indices of the stash entries that are inline code spans (the rest
          # are fenced blocks), for the table pass's pipe escaping.
          inline_code = Set(Int32).new
          result = result.gsub(/<pre[^>]*>\s*<code[^>]*>(.{0,#{MAX_CODE_BODY_CHARS}}?)<\/code>\s*<\/pre>/mi) do
            code = decode_html_entities($1)
            code_stash << "```\n#{code.strip}\n```\n\n"
            code_placeholder(code_stash.size - 1)
          end
          result = result.gsub(/<pre[^>]*>(.*?)<\/pre>/mi) do
            # A <pre><code> body longer than MAX_CODE_BODY_CHARS falls through
            # to this pass with its <code> wrapper still attached — strip it
            # here (both tags have single-literal tails, so this stays linear).
            body = $1.sub(/\A\s*<code[^>]*>/mi, "").sub(/<\/code>\s*\z/mi, "")
            code = decode_html_entities(body)
            code_stash << "```\n#{code.strip}\n```\n\n"
            code_placeholder(code_stash.size - 1)
          end

          # Inline code is stashed too, for the same reason: its text is
          # literal, so it is entity-decoded exactly once here and must not
          # be touched by the prose escaping in `decode_prose_entities`
          # (Markdown shows `&lt;` inside a code span verbatim).
          result = result.gsub(/<code\b[^>]*>(.*?)<\/code>/mi) do
            code_stash << "`#{decode_html_entities(strip_tags($1))}`"
            inline_code << code_stash.size - 1
            code_placeholder(code_stash.size - 1)
          end

          # WordPress's "Read more" tag (`<!--more-->`, optionally with custom
          # link text) is the post's excerpt separator. hwaro reads the same
          # marker as `<!-- more -->`, so keep it instead of letting
          # `strip_tags` delete it with every other comment. Only that tag:
          # an author's `<!-- more of the same -->` is just a comment.
          result = result.gsub(MORE_TAG_RE, MORE_PLACEHOLDER)

          # `[caption]` shortcode (classic-editor images): unwrap it, putting
          # the caption text in its own paragraph under the image. Left as
          # is, the shortcode rendered as literal `[caption id=…]` text.
          # Pre-3.4 exports carry the text in a `caption="…"` attribute instead.
          result = result.gsub(/\[caption\b([^\]]*)\](.*?)\[\/caption\]/mi) do
            attrs = $1
            inner = $2.strip
            if m = inner.match(/\A((?:<a\b[^>]*>\s*)?<img\b[^>]*>(?:\s*<\/a>)?)\s*(.*)\z/mi)
              caption = m[2].strip
              caption = attrs.match(/\bcaption=["']([^"']*)["']/i).try(&.[1].strip) || "" if caption.empty?
              caption.empty? ? "#{m[1]}\n\n" : "#{m[1]}\n\n#{caption}\n\n"
            else
              "#{inner}\n\n"
            end
          end

          # Blockquotes. Paragraph boundaries inside the quote (and a
          # Gutenberg `<cite>`) become quoted blank lines — deleting the
          # `<p>` tags outright glued every paragraph into one run-on line.
          result = result.gsub(/<blockquote[^>]*>(.*?)<\/blockquote>/mi) do
            # An excerpt marker can't split a quote (nor, below, a list
            # item or a table cell) without breaking it apart; drop it there.
            inner = $1.strip
              .gsub(MORE_PLACEHOLDER, "")
              .gsub(/<\/p\s*>/i, "\n\n")
              .gsub(/<p\b[^>]*>/i, "")
              .gsub(/<cite\b[^>]*>/i, "\n\n")
              .strip
              .gsub(/\n[ \t]*(?:\n[ \t]*)+/, "\n\n")
            lines = inner.split("\n").map { |l| l.strip.empty? ? ">" : "> #{l.strip}" }
            lines.join("\n") + "\n\n"
          end

          # Lists — innermost first, so a nested <ul> inside an <li> is
          # converted before its parent. The old single outer pass stopped at
          # the INNER </ul>, garbling nested lists and dropping trailing items.
          # A converted list opens with a newline and each item's continuation
          # lines are indented: by the time an OUTER list is converted, the
          # inner one is already Markdown sitting inside the parent `<li>`,
          # so without those two things `<li>b<ul><li>b1</li></ul></li>`
          # collapsed to the single line `- b- b1` (and `2. second1. s1` for
          # ordered lists), which renders as literal text.
          innermost_list = INNERMOST_LIST_RE
          passes = 0
          while (passes += 1) <= MAX_LIST_PASSES && result.matches?(innermost_list)
            result = result.gsub(innermost_list) do
              kind = $1.downcase
              items = $2.scan(/<li[^>]*>(.*?)<\/li>/mi)
              lines = items.map_with_index do |m, i|
                marker = kind == "ol" ? "#{i + 1}. " : "- "
                # Inline markup first: a bare `strip_tags` here ran before
                # the document-wide inline passes, so every link, image and
                # emphasis inside a list item was flattened to plain text.
                item = strip_tags(convert_inline(m[1])).gsub(MORE_PLACEHOLDER, "").strip
                "#{marker}#{indent_continuation(item, marker.size)}"
              end
              "\n" + lines.join("\n") + "\n\n"
            end
          end

          # Tables — convert <table> into Markdown pipe-tables. Uses the
          # first row as the header (typical for WXR exports, which wrap
          # headers in <thead><tr><th>). If no <th> is present the first
          # row is still promoted to a header so the table is legal
          # Markdown. Nested tables fall through strip_tags (the inner
          # table text is flattened) — WP blog posts rarely nest tables.
          result = result.gsub(/<table[^>]*>(.*?)<\/table>/mi) do
            inner = $1
            rows = inner.scan(/<tr[^>]*>(.*?)<\/tr>/mi).map do |m|
              m[1].scan(/<(?:th|td)[^>]*>(.*?)<\/(?:th|td)>/mi).map do |cell|
                # Same as list items: convert inline markup before stripping.
                text = strip_tags(convert_inline(cell[1])).gsub(MORE_PLACEHOLDER, "").strip.gsub(/\s+/, " ").gsub("|", "\\|")
                # A stashed code span sits in the cell as a placeholder, so
                # its pipes have to be escaped in the stash itself. Only a
                # span's: in a fenced block `\|` is literal text.
                text.scan(CODE_PLACEHOLDER_RE) do |pm|
                  idx = pm[1].to_i
                  code_stash[idx] = code_stash[idx].gsub("|", "\\|") if inline_code.includes?(idx)
                end
                text
              end
            end
            rows.reject!(&.empty?)
            if rows.empty?
              ""
            else
              width = rows.max_of(&.size)
              header = rows.shift
              header += [""] * (width - header.size)
              lines = [] of String
              lines << "| #{header.join(" | ")} |"
              lines << "| #{(["---"] * width).join(" | ")} |"
              rows.each do |row|
                padded = row + [""] * (width - row.size)
                lines << "| #{padded.join(" | ")} |"
              end
              lines.join("\n") + "\n\n"
            end
          end

          # Horizontal rules (attribute-bearing and uppercase forms included —
          # Gutenberg emits `<hr class="wp-block-separator …"/>`)
          result = result.gsub(/<hr\b[^>]*>/i, "\n---\n\n")

          # Paragraphs
          result = result.gsub(/<p[^>]*>(.*?)<\/p>/mi) { "#{$1.strip}\n\n" }

          # Line breaks
          result = result.gsub(/<br\b[^>]*>/i, "  \n")

          # Inline elements
          result = convert_inline(result)

          # Strip remaining HTML tags
          result = strip_tags(result)

          # Decode HTML entities
          result = decode_prose_entities(result)

          # Restore stashed code (already entity-decoded exactly once) and
          # the excerpt marker.
          code_stash.each_with_index do |block, i|
            result = result.sub(code_placeholder(i), block)
          end
          result = result.gsub(MORE_PLACEHOLDER, "\n\n<!-- more -->\n\n")

          # Clean up whitespace
          result = result.gsub(/\n{3,}/, "\n\n") # Max 2 consecutive newlines
          result.strip
        end

        # The inline passes (images, links, emphasis, strikethrough). Run on
        # the whole document and, before their own `strip_tags`, on list
        # items and table cells.
        private def self.convert_inline(html : String) : String
          result = html

          # Images (before links to avoid nested match issues).
          # Drop the URL (keep the alt text) when the scheme is unsafe so an
          # untrusted export can't smuggle a live `javascript:`/`data:` src
          # into content — the importer stays safe regardless of the markdown
          # renderer's `safe` flag.
          result = result.gsub(/<img[^>]*\bsrc=["']([^"']+)["'][^>]*\balt=["']([^"']*)["'][^>]*\/?>/i) { safe_media($1, $2, image: true) }
          result = result.gsub(/<img[^>]*\balt=["']([^"']*)["'][^>]*\bsrc=["']([^"']+)["'][^>]*\/?>/i) { safe_media($2, $1, image: true) }
          result = result.gsub(/<img[^>]*\bsrc=["']([^"']+)["'][^>]*\/?>/i) { safe_media($1, "", image: true) }

          # Links — likewise drop a dangerous href but keep the link text.
          #
          # The body is BOUNDED (`{0,MAX_INLINE_BODY_CHARS}?`) rather than an
          # open `(.*?)`. An open lazy body rescans every remaining character
          # from each `<a href=…>` that never closes, so a document of n
          # unclosed anchors costs O(n^2): measured 1.4 s for 20k anchors and
          # 6.0 s for 40k, while the same count of CLOSED anchors — a 1.4x
          # LARGER document — takes 0.07 s. `MAX_REGEX_HTML_BYTES` did not
          # bound that as its comment claims: ~175k unclosed anchors still fit
          # under the 4 MB cap, i.e. minutes of CPU inside one import of an
          # untrusted WXR export. With the bound, each anchor start costs a
          # fixed scan instead of a scan to end-of-document.
          #
          # The `</a>` probe stays as a cheap short-circuit for the common
          # no-anchor document, but it is an optimization, not the guard: a
          # single `</a>` anywhere re-enables the pass, which is why the bound
          # has to carry the cost argument. It is case-insensitive because the
          # conversion is: `</A>` closes a real anchor.
          #
          # Trade-off: an anchor whose text runs longer than the bound is left
          # as HTML and its text is kept by `strip_tags` below — the link
          # markup is lost, no content is. Real inline anchors are orders of
          # magnitude shorter.
          if result.matches?(ANCHOR_CLOSE_RE)
            result = result.gsub(ANCHOR_RE) { safe_media($1, $2, image: false) }
          end

          # Bold
          result = result.gsub(/<(?:strong|b)>(.*?)<\/(?:strong|b)>/mi) { emphasize($1, "**") }

          # Italic
          result = result.gsub(/<(?:em|i)>(.*?)<\/(?:em|i)>/mi) { emphasize($1, "*") }

          # Strikethrough
          result = result.gsub(/<(?:del|s|strike)>(.*?)<\/(?:del|s|strike)>/mi) { emphasize($1, "~~") }

          result
        end

        # Wrap `inner` in an emphasis delimiter, moving its edge whitespace
        # outside: WordPress's visual editor routinely leaves the space
        # inside the tag (`<strong>bold </strong>text`), and `**bold **text`
        # is not emphasis in Markdown — the asterisks render literally.
        # A no-break space (`&nbsp;`, `&#160;`, U+00A0) counts as edge
        # whitespace too — the editor inserts it just as often.
        private def self.emphasize(inner : String, delim : String) : String
          lead = inner[EDGE_SPACE_LEAD_RE]? || ""
          rest = inner[lead.size..]
          trail = rest[EDGE_SPACE_TRAIL_RE]? || ""
          core = rest[0, rest.size - trail.size]
          return inner if core.empty?
          "#{lead}#{delim}#{core}#{delim}#{trail}"
        end

        EDGE_SPACE          = "(?:\\s|\\x{A0}|&nbsp;|&#0*160;|&#x0*a0;)"
        EDGE_SPACE_LEAD_RE  = Regex.new("\\A#{EDGE_SPACE}+", Regex::Options::IGNORE_CASE)
        EDGE_SPACE_TRAIL_RE = Regex.new("#{EDGE_SPACE}+\\z", Regex::Options::IGNORE_CASE)

        # NUL-delimited placeholder: survives every regex pass (no `<>`, no
        # `&…;`) and can't occur in real exported content (XML forbids NUL).
        private def self.code_placeholder(index : Int32) : String
          "\u0000hwaro-code-#{index}\u0000"
        end

        CODE_PLACEHOLDER_RE = /\x{0}hwaro-code-(\d+)\x{0}/
        MORE_PLACEHOLDER    = "\u0000hwaro-more\u0000"
        MORE_TAG_RE         = /<!--more(?:\s.*?)?-->|<!--\s*more\s*-->/mi

        # Entity-decode prose for Markdown. Decoding is what makes the output
        # readable, but a decoded `&lt;script&gt;` — text the author wrote to
        # be SHOWN — turned into a live `<script>` tag that swallowed the
        # rest of the page. Re-escape exactly the characters Markdown would
        # read as markup: a `<` that could open an HTML tag, comment or
        # declaration, and an `&amp;` whose decoded `&` would start an entity
        # reference (`&amp;copy;` is the literal text "&copy;"). Named
        # entities this decoder doesn't know stay encoded; Markdown decodes
        # those itself.
        private def self.decode_prose_entities(text : String) : String
          decode_html_entities(text.gsub(/#{AMP_ENTITY}(?=#?[A-Za-z0-9]+;)/i, AMP_PLACEHOLDER))
            .gsub(/<(?=[A-Za-z\/!?])/, "&lt;")
            .gsub(AMP_PLACEHOLDER, "&amp;")
        end

        AMP_PLACEHOLDER = "\u0000hwaro-amp\u0000"

        # Every spelling of an encoded `&`: WordPress writes `&#038;` often.
        AMP_ENTITY = /&(?:amp|#0*38|#x0*26);/i

        private def self.strip_tags(html : String) : String
          html.gsub(/<[^>]*>/, "")
        end

        # Indent every line after the first to the item's content column so an
        # already converted nested list stays nested under its parent item.
        # The width is the marker's own width (`- ` → 2, `10. ` → 4), which is
        # what CommonMark requires for a child block. Blank lines are left
        # alone (trailing whitespace would survive into the imported Markdown).
        private def self.indent_continuation(text : String, width : Int32) : String
          return text unless text.includes?('\n')
          pad = " " * width
          text.lines(chomp: false).map_with_index do |line, i|
            i.zero? || line.strip.empty? ? line : "#{pad}#{line}"
          end.join
        end

        # Emit a markdown link/image only when the URL scheme is safe; otherwise
        # drop the URL and keep just the text/alt. Reuses the single source of
        # truth for URL-scheme sanitisation so imported content can never carry
        # a live `javascript:`/`vbscript:`/`file:`/non-image-`data:` reference.
        private def self.safe_media(url : String, text : String, image : Bool) : String
          return text unless Hwaro::Content::Processors::InlineMarkdown.safe_url?(url)
          image ? "![#{text}](#{url})" : "[#{text}](#{url})"
        end

        private def self.decode_html_entities(text : String) : String
          text
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&quot;", "\"")
            .gsub("&#39;", "'")
            .gsub("&apos;", "'")
            .gsub("&nbsp;", " ")
            .gsub("&#8211;", "-")
            .gsub("&#8212;", "--")
            .gsub("&#8216;", "'")
            .gsub("&#8217;", "'")
            .gsub("&#8220;", "\"")
            .gsub("&#8221;", "\"")
            .gsub("&#8230;", "...")
            .gsub(/&#(\d+);/) do
              # to_i? (not to_i): a numeric entity whose digits exceed Int32
              # (e.g. &#99999999999999999999;) must be dropped, not crash the
              # import. The range check below already rejects it, but to_i
              # would raise before we ever get there.
              code = $1.to_i?
              # Validate Unicode range (exclude surrogates 0xD800..0xDFFF).
              # An encoded `&` (38) is left for the final AMP_ENTITY pass.
              if code == 38
                $~[0]
              elsif code && code > 0 && code <= 0x10FFFF && !(0xD800 <= code <= 0xDFFF)
                code.chr.to_s
              else
                ""
              end
            end
            .gsub(/&#[xX]([0-9a-fA-F]+);/) do
              code = $1.to_i?(16)
              if code == 0x26
                $~[0]
              elsif code && code > 0 && code <= 0x10FFFF && !(0xD800 <= code <= 0xDFFF)
                code.chr.to_s
              else
                ""
              end
            end
            .gsub(AMP_ENTITY, "&")
          # An encoded `&` (`&amp;`, `&#038;`, `&#x26;`) LAST: decoding it
          # first turned `&amp;lt;` (a literal "&lt;" in the source text)
          # into a real `<` — the classic double-unescape.
        end
      end
    end
  end
end
