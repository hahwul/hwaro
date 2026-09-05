# Markdown extensions — GFM task lists.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- Task Lists ---
        # Converts - [ ] and - [x] to checkbox HTML in list items
        TASK_LIST_RE = /^(\s*[-*+]\s)\[([ xX])\]/m

        def preprocess_task_lists(content : String) : String
          content.gsub(TASK_LIST_RE) do |_|
            prefix = $1
            checked = $2.downcase == "x"
            if checked
              "#{prefix}<input type=\"checkbox\" checked disabled>"
            else
              "#{prefix}<input type=\"checkbox\" disabled>"
            end
          end
        end

        # --- Task list classes (GFM markup, opt-in) ---
        # preprocess_task_lists runs before Markd, when the <li> doesn't
        # exist yet — so the GFM classes are added here, on the rendered
        # HTML. Matches both list shapes markd emits: tight
        # (`<li><input …`) and loose (`<li>\n<p><input …`). Code blocks
        # are immune (their `<input` is entity-escaped).
        TASK_LIST_ITEM_RE = /<li>(\n?(?:<p>)?)<input type="checkbox"( checked)? disabled>/

        def postprocess_task_list_classes(html : String) : String
          return html unless html.includes?(%(<input type="checkbox"))

          result = html.gsub(TASK_LIST_ITEM_RE) do
            %(<li class="task-list-item">#{$1}<input type="checkbox"#{$2?} disabled class="task-list-item-checkbox">)
          end
          return result unless result.includes?("task-list-item")

          mark_containing_lists(result)
        end

        # Adds `contains-task-list` to every <ul>/<ol> that directly
        # contains a task-list <li>. A linear byte scan with a stack of
        # open list tags — a regex can't pair nested lists correctly
        # (mixed lists, task item not first, task lists nested in plain
        # lists). markd's list tags carry at most `start="N"`, no quoted
        # '>' to worry about.
        private def mark_containing_lists(html : String) : String
          slice = html.to_slice
          stack = [] of {Int32, Bool} # {insert offset (at the tag's '>'), marked}
          insertions = [] of Int32

          # Byte offsets throughout — every marker byte is ASCII, so the
          # scan is UTF-8 safe (same rationale as apply_emoji's scanner).
          pos = 0
          while found = html.byte_index('<', pos)
            pos = found + 1
            if bytes_at?(slice, found, "<ul") || bytes_at?(slice, found, "<ol")
              if close = html.byte_index('>', found)
                stack << {close, false}
                pos = close + 1
              end
            elsif bytes_at?(slice, found, "</ul>") || bytes_at?(slice, found, "</ol>")
              if top = stack.pop?
                insertions << top[0] if top[1]
              end
              pos = found + 5
            elsif bytes_at?(slice, found, %(<li class="task-list-item")) && !stack.empty?
              stack[-1] = {stack[-1][0], true}
            end
          end
          return html if insertions.empty?

          insertions.sort!
          String.build(html.bytesize + insertions.size * 26) do |io|
            prev = 0
            insertions.each do |offset|
              io.write(slice[prev, offset - prev])
              io << %( class="contains-task-list")
              prev = offset
            end
            io.write(slice[prev, slice.size - prev])
          end
        end

        private def bytes_at?(slice : Bytes, offset : Int32, prefix : String) : Bool
          bytes = prefix.to_slice
          return false if offset + bytes.size > slice.size
          slice[offset, bytes.size] == bytes
        end
      end
    end
  end
end
