# Markdown extensions — definition lists.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- Definition Lists ---
        # Converts Term\n: Definition syntax to <dl><dt><dd> HTML.
        # Fence-aware: `Term` / `: def` lines shown inside a ```/~~~ example
        # stay verbatim instead of becoming <dl> markup inside the code block.
        # `math: true` keeps `$…$` spans in <dt>/<dd> bodies untransformed
        # for the later math pass (see InlineMarkdown.render). Pre-F10
        # signature — delegates to the `flags` overload (existing
        # callers/specs keep calling this one directly).
        def preprocess_definition_lists(content : String, *, math : Bool = false) : String
          preprocess_definition_lists(content, flags: InlineMarkdown::Flags.new(math: math))
        end

        # `flags` also threads the F10 opt-in inline markup (ins/mark/sub/
        # sup) into term/definition bodies, alongside the math flag.
        def preprocess_definition_lists(content : String, *, flags : InlineMarkdown::Flags) : String
          # Whole-content marker pre-check (memchr-fast): every definition line
          # must lstrip-start with ": " (see the loop conditions below), so a
          # content without ": " anywhere cannot contain a definition list and
          # the walk is the identity transform — skip it.
          return content unless content.includes?(": ")

          lines = content.split("\n")

          tracker = FenceTracker.new
          fenced = lines.map { |line| tracker.fence_line?(line) }

          result = [] of String
          i = 0

          while i < lines.size
            line = lines[i]

            if fenced[i]
              result << line
              i += 1
              next
            end

            # Check if next line starts with ": " (definition). The term line
            # (lines[i]) must be non-empty: a blank line followed by a ": "
            # line is an orphan definition, not a definition list — entering
            # the branch there emitted a stray empty <dl></dl> and leaked the
            # ": " line through as literal text.
            if i + 1 < lines.size && !fenced[i + 1] && !line.strip.empty? && lines[i + 1].lstrip.starts_with?(": ")
              # This is a definition list
              result << "<dl>"
              while i < lines.size && !fenced[i]
                term = lines[i].strip
                if term.empty?
                  i += 1
                  break
                end

                result << "<dt>#{render_inline_md(term, flags)}</dt>"
                i += 1

                # Collect definitions for this term
                while i < lines.size && !fenced[i] && lines[i].lstrip.starts_with?(": ")
                  definition = lines[i].lstrip.lchop(": ").strip
                  i += 1
                  # PHP-Markdown-Extra soft wrap: 4-space/tab-indented
                  # continuation lines join the same <dd> with a space. An
                  # indented `: …` stays a new definition, and a blank line
                  # still ends the group as before (multi-paragraph <dd> is
                  # deliberately out of scope).
                  while i < lines.size && !fenced[i] && dd_continuation?(lines[i])
                    definition += " #{lines[i].strip}"
                    i += 1
                  end
                  result << "<dd>#{render_inline_md(definition, flags)}</dd>"
                end

                # Skip one or more blank lines between term groups within the same dl
                peek = i
                while peek < lines.size && !fenced[peek] && lines[peek].strip.empty?
                  peek += 1
                end
                if peek > i && peek + 1 < lines.size && !fenced[peek] && !fenced[peek + 1] && lines[peek + 1].lstrip.starts_with?(": ")
                  i = peek
                  next
                end
                break
              end
              result << "</dl>"
            else
              result << line
              i += 1
            end
          end

          result.join("\n")
        end

        private def dd_continuation?(line : String) : Bool
          return false if line.strip.empty?
          return false unless line.starts_with?("    ") || line.starts_with?('\t')
          !line.lstrip.starts_with?(": ")
        end
      end
    end
  end
end
