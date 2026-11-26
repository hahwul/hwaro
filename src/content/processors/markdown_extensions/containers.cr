# Markdown extensions — custom ::: containers.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- Custom containers (opt-in) ---
        # `:::type Optional Title` … `:::` blocks (markdown-it/remark
        # style), emitted with the admonition markup so site CSS is shared:
        #
        #   <div class="admonition admonition-TYPE">
        #   <p class="admonition-title">Title</p>
        #   <blank line — ends the type-6 HTML block, so the body is
        #   parsed as ordinary markdown, fences and task lists included>
        #   …body…
        #   </div>
        #
        # A bare `:{3,}` run closes the innermost open container, which
        # gives natural nesting (`::::outer` / `:::inner` / `:::` /
        # `::::`) with a plain counter. Unclosed containers auto-close at
        # EOF (markdown-it behavior). Fence-aware: ::: lines inside code
        # fences stay verbatim. The type token is class-safe by
        # construction; the title is inline markdown (escaped).
        CONTAINER_OPEN_RE  = /\A {0,3}:{3,}[ \t]*([A-Za-z][\w-]*)[ \t]*(.*)\z/
        CONTAINER_CLOSE_RE = /\A {0,3}:{3,}\z/

        def preprocess_containers(content : String, *, flags : InlineMarkdown::Flags = InlineMarkdown::Flags.new, trusted : Bool = false) : String
          return content unless Utils::ByteScan.includes?(content, ":::")

          # Indentation of each open container's opener, innermost last: the
          # markup keeps it, so a container written in a list item stays in
          # the item (at column 0 the `<div>` ended the item and the list).
          open_indents = [] of String
          last_line_ended = true
          String.build do |io|
            tracker = FenceTracker.new
            content.each_line(chomp: false) do |line|
              last_line_ended = line.ends_with?('\n')
              if tracker.fence_line?(line)
                io << line
                next
              end

              stripped = line.rstrip
              if m = CONTAINER_OPEN_RE.match(stripped)
                type = m[1].downcase
                # Inline-rendered like an admonition's `> [!NOTE] *Title*`.
                title = m[2].presence.try { |t| render_inline_md(t, flags) } || m[1].capitalize
                indent = line[/\A[ \t]*/]
                open_indents << indent
                io << indent << trust("<div class=\"admonition admonition-#{type}\">\n", trusted)
                io << indent << trust("<p class=\"admonition-title\">#{title}</p>\n\n", trusted)
                last_line_ended = true
                next
              end
              if !open_indents.empty? && CONTAINER_CLOSE_RE.matches?(stripped)
                indent = open_indents.pop
                # Trailing blank line: `</div>` opens a type-6 HTML block that
                # runs until the next blank line, so without one the FIRST line
                # after the container (`- item`, `## Heading`, a paragraph) was
                # swallowed into that block and emitted as raw, unparsed
                # markdown. Markd drops the trailing blank from the block's
                # literal, so a container followed by a blank line renders
                # byte-identically.
                io << "\n" << indent << "</div>\n\n"
                last_line_ended = true
                next
              end

              io << line
            end
            # Auto-close unclosed containers at EOF (markdown-it behavior),
            # outside any fence the page left open.
            unless open_indents.empty?
              io << document_end_separator(last_line_ended, tracker)
              open_indents.reverse_each { |indent| io << "\n" << indent << "</div>\n\n" }
            end
          end
        end
      end
    end
  end
end
