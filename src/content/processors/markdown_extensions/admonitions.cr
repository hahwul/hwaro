# Markdown extensions — GitHub-style admonitions.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- GitHub-style Admonitions ---
        # Recognised types match GitHub's alert syntax.
        ADMONITION_TYPES = {"NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"}

        # Captures a blockquote whose first paragraph starts with `[!TYPE]`.
        # Non-void tags that markd's inline renderer can open on a title line.
        # Balanced when every opener on the line is closed on the line: a
        # `<strong>`/`<a>`/`<code>`… opened here and closed on a later line
        # of the same paragraph means the author wrapped one inline element
        # across the soft break, not that they wrote a title.
        INLINE_TAG_RE    = /<(\/?)([a-zA-Z][\w-]*)[^>]*>/
        VOID_INLINE_TAGS = Set{"br", "img", "wbr", "hr", "input"}

        def inline_html_balanced?(fragment : String) : Bool
          return true unless fragment.includes?('<')
          open = [] of String
          fragment.scan(INLINE_TAG_RE) do |m|
            name = m[2].downcase
            next if VOID_INLINE_TAGS.includes?(name) || m[0].ends_with?("/>")
            if m[1].empty?
              open << name
            else
              return false if open.empty? || open.pop != name
            end
          end
          open.empty?
        end

        # Group 1: type token (uppercased). Group 2: whatever else sat on the
        # marker's own line — the custom title (Obsidian / Hugo syntax:
        # `> [!NOTE] Custom Title`); empty for a bare marker. Group 3: the rest
        # of the blockquote body, possibly starting with `</p>` (when the
        # marker line was a paragraph of its own) or with the inline body
        # content (when body text followed the marker via a soft break).
        #
        # Group 2 stops at the line break, so a same-line title can never be
        # confused with a soft-broken body. It used to be `\s*(.*?)`, which
        # swallowed the title into the first body paragraph — `Custom Title`
        # rendered as body text under the default "Note" heading. Obsidian's
        # optional fold marker (`[!NOTE]+` / `[!NOTE]-`) is accepted and
        # dropped; folding itself is not modeled.
        ADMONITION_BLOCKQUOTE_RE = /<blockquote>\s*<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][+-]?([^\n]*?)(?:\n|(?=<\/p>))\s*(.*?)<\/blockquote>/m

        # Post-processing: rewrite GitHub `> [!TYPE]` blockquotes as admonition divs.
        # Note: the lazy match against `</blockquote>` means a nested blockquote
        # inside the admonition will close the match early. Acceptable for v1 —
        # GitHub admonitions don't support nested blockquotes either.
        def postprocess_admonitions(html : String) : String
          return html unless html.includes?("[!")

          html.gsub(ADMONITION_BLOCKQUOTE_RE) do |_|
            type = $1
            title_line = $2
            rest = $3
            # Two or more trailing spaces on the marker line become a hard
            # break in markd (`[!NOTE]  ` → `[!NOTE]<br />\n`), and the break
            # tag sits before the newline group 2 stops at — so it landed in
            # the title and a bare marker lost its "Note" heading to an empty
            # `<br />`. It is line-end residue, never title text.
            title_line = title_line.sub(/\s*<br\s*\/?>\s*\z/, "")
            # An inline element that wraps from the marker line onto the next
            # (`[!WARNING] see [the\n> docs](…)`) cannot be a title: cutting
            # it at the soft break split `<a>` between title and body. Treat
            # the whole paragraph as body, as before custom titles existed.
            unless inline_html_balanced?(title_line)
              rest = "#{title_line}\n#{rest}"
              title_line = ""
            end
            custom_title = title_line.strip
            type_lower = type.downcase
            # The custom title is already inline-rendered (and escaped) by
            # markd — it was part of the paragraph — so it is emitted as-is.
            type_title = custom_title.empty? ? type[0].to_s + type[1..].downcase : custom_title

            body = if rest.lstrip.starts_with?("</p>")
                     # Marker was alone on its paragraph; remaining content
                     # already consists of well-formed block elements.
                     rest.sub(/\A\s*<\/p>\s*/, "").strip
                   elsif rest.strip.empty?
                     # Title-only admonition with no body.
                     ""
                   else
                     # Body text shared the marker's paragraph (soft break).
                     # The closing </p> is already inside `rest`.
                     "<p>#{rest.lstrip}".strip
                   end

            String.build do |str|
              str << %(<div class="admonition admonition-#{type_lower}">\n)
              str << %(<p class="admonition-title">#{type_title}</p>\n)
              unless body.empty?
                str << body
                str << '\n'
              end
              str << "</div>"
            end
          end
        end
      end
    end
  end
end
