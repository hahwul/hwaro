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
        # construction; the title is HTML-escaped plain text.
        CONTAINER_OPEN_RE  = /\A {0,3}:{3,}([A-Za-z][\w-]*)[ \t]*(.*)\z/
        CONTAINER_CLOSE_RE = /\A {0,3}:{3,}\z/

        def preprocess_containers(content : String) : String
          return content unless content.includes?(":::")

          open_count = 0
          String.build do |io|
            tracker = FenceTracker.new
            content.each_line(chomp: false) do |line|
              if tracker.fence_line?(line)
                io << line
                next
              end

              stripped = line.rstrip
              if m = CONTAINER_OPEN_RE.match(stripped)
                type = m[1].downcase
                title = m[2].presence.try { |t| HTML.escape(t) } || m[1].capitalize
                open_count += 1
                io << "<div class=\"admonition admonition-#{type}\">\n"
                io << "<p class=\"admonition-title\">#{title}</p>\n\n"
                next
              end
              if open_count > 0 && CONTAINER_CLOSE_RE.matches?(stripped)
                open_count -= 1
                # Trailing blank line: `</div>` opens a type-6 HTML block that
                # runs until the next blank line, so without one the FIRST line
                # after the container (`- item`, `## Heading`, a paragraph) was
                # swallowed into that block and emitted as raw, unparsed
                # markdown. Markd drops the trailing blank from the block's
                # literal, so a container followed by a blank line renders
                # byte-identically.
                io << "\n</div>\n\n"
                next
              end

              io << line
            end
            # Auto-close unclosed containers at EOF (markdown-it behavior).
            open_count.times { io << "\n</div>\n\n" }
          end
        end
      end
    end
  end
end
