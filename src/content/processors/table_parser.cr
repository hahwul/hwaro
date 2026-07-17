# Markdown Table Parser
#
# This module parses markdown tables and converts them to HTML.
# Since markd doesn't support GFM tables, this provides table support
# by preprocessing markdown content before passing to markd.
#
# Supported features:
# - Basic pipe-delimited tables
# - Column alignment (left, center, right)
# - Inline formatting within cells (rendered via InlineMarkdown, which
#   HTML-escapes cell text — markd does not reparse the generated HTML)
#
# Table syntax:
#   | Header 1 | Header 2 | Header 3 |
#   |----------|:--------:|---------:|
#   | Left     | Center   | Right    |
#   | Cell     | Cell     | Cell     |
#
# Alignment:
#   - `---` or `:---` = left align (default)
#   - `:---:` = center align
#   - `---:` = right align

require "html"
require "./fence_tracker"
require "./inline_markdown"
require "./render_hooks"

module Hwaro
  module Content
    module Processors
      module TableParser
        extend self

        # Represents column alignment
        enum Alignment
          Left
          Center
          Right
        end

        # Represents a parsed table
        struct Table
          property headers : Array(String)
          property alignments : Array(Alignment)
          property rows : Array(Array(String))

          def initialize(@headers, @alignments, @rows)
          end

          # Convert table to HTML. `math: true` keeps `$…$` spans in cells
          # untransformed for the later math pass (see InlineMarkdown.render).
          # With a `hooks` context whose table hook is configured, the stock
          # markup (plus its thead/tbody sections) is handed to
          # `hooks.render_table` instead of returned directly.
          def to_html(math : Bool = false, flags : InlineMarkdown::Flags? = nil, hooks : RenderHooks::HookRenderContext? = nil) : String
            effective = flags || InlineMarkdown::Flags.new(math: math)

            header_html = String.build do |str|
              str << "<thead>\n<tr>\n"

              @headers.each_with_index do |header, i|
                alignment = @alignments[i]? || Alignment::Left
                align_attr = alignment_attr(alignment)
                str << "<th#{align_attr}>#{render_inline_markdown(header.strip, effective)}</th>\n"
              end

              str << "</tr>\n</thead>\n"
            end

            body_html = if @rows.present?
                          String.build do |str|
                            str << "<tbody>\n"
                            @rows.each do |row|
                              str << "<tr>\n"
                              row.each_with_index do |cell, i|
                                alignment = @alignments[i]? || Alignment::Left
                                align_attr = alignment_attr(alignment)
                                str << "<td#{align_attr}>#{render_inline_markdown(cell.strip, effective)}</td>\n"
                              end
                              # Fill missing cells if row has fewer columns than headers
                              if row.size < @headers.size
                                (@headers.size - row.size).times do |j|
                                  alignment = @alignments[row.size + j]? || Alignment::Left
                                  align_attr = alignment_attr(alignment)
                                  str << "<td#{align_attr}></td>\n"
                                end
                              end
                              str << "</tr>\n"
                            end
                            str << "</tbody>\n"
                          end
                        else
                          ""
                        end

            html = "<table>\n#{header_html}#{body_html}</table>"

            if hooks && hooks.table?
              return hooks.render_table(html: html, header_html: header_html, body_html: body_html)
            end
            html
          end

          private def alignment_attr(alignment : Alignment) : String
            case alignment
            when Alignment::Center
              " style=\"text-align: center;\""
            when Alignment::Right
              " style=\"text-align: right;\""
            else
              ""
            end
          end

          private def render_inline_markdown(text : String, flags : InlineMarkdown::Flags) : String
            InlineMarkdown.render(text, flags: flags)
          end
        end

        # Process markdown content and convert tables to HTML
        # Tables are converted to HTML placeholders, then markd processes the rest,
        # and placeholders are replaced with actual HTML tables.
        # `math: true` keeps `$…$` spans in cells untransformed for the later
        # math pass. `flags` (when given) takes precedence over `math` and
        # also threads the F10 inline markup flags (ins/mark/sub/sup) into
        # cell rendering. `hooks` routes each table through the render-table
        # hook (see `Table#to_html`); nil keeps the stock output.
        def process(content : String, *, math : Bool = false, flags : InlineMarkdown::Flags? = nil,
                    hooks : RenderHooks::HookRenderContext? = nil) : String
          return content unless has_table?(content)

          effective = flags || InlineMarkdown::Flags.new(math: math)
          lines = content.split("\n")
          result = [] of String
          i = 0
          # Track fenced code blocks via the shared FenceTracker so verbatim
          # pipe-table syntax shown inside ``` / ~~~ fences (common in docs)
          # isn't converted to a real <table> — including ``` examples nested
          # in ```` fences and indented-code lines where ``` is literal text.
          tracker = FenceTracker.new

          while i < lines.size
            if tracker.fence_line?(lines[i])
              result << lines[i]
              i += 1
              next
            end

            # Check if this could be the start of a table
            if table_row?(lines[i]) && i + 1 < lines.size && separator_row?(lines[i + 1])
              # Try to parse the table
              table, consumed = parse_table(lines, i)
              if table
                result << table.to_html(flags: effective, hooks: hooks)
                i += consumed
                next
              end
            end

            result << lines[i]
            i += 1
          end

          result.join("\n")
        end

        # Quick check if content might contain tables.
        # Detects the separator row pattern which is the definitive marker of a
        # markdown table (e.g. `|---|---|` or `---|---`).  This avoids false
        # positives from random `|` in code blocks, URLs, or inline code while
        # still catching tables with or without leading/trailing pipes.
        TABLE_SEPARATOR_CHECK = /^\s*\|?\s*:?-{3,}:?\s*\|/m

        def has_table?(content : String) : Bool
          TABLE_SEPARATOR_CHECK.matches?(content)
        end

        # Check if a line looks like a table row (contains pipe characters)
        private def table_row?(line : String) : Bool
          stripped = line.strip
          return false if stripped.empty?

          # Must contain at least one pipe
          stripped.includes?("|")
        end

        # Check if a line is a separator row (contains dashes and optional colons)
        private def separator_row?(line : String) : Bool
          stripped = line.strip
          return false if stripped.empty?
          return false unless stripped.includes?("|")

          # Remove leading/trailing pipes and split
          cells = split_row(stripped)
          return false if cells.empty?

          # Each cell should match the separator pattern
          cells.all? do |cell|
            cell = cell.strip
            # Must be at least 3 dashes (with optional colons)
            cell.matches?(/^:?-{3,}:?$/)
          end
        end

        # Split a table row into cells.
        #
        # A `|` only delimits columns when it is "bare": escaped pipes (`\|`)
        # and pipes that sit inside an inline code span (`` `a|b` ``) are
        # literal cell content, matching GFM / markdown-it. Without the
        # code-span guard a cell like `` `a|b` `` gets split mid-span, which
        # corrupts the code span (dangling backticks) and pushes a stray extra
        # `<td>` past the column count.
        # Scans BYTES rather than a materialized Array(Char): every byte the
        # scanner branches on (`\`, `` ` ``, `|`) is ASCII, and in UTF-8 the
        # bytes of a multi-byte character are all >= 0x80, so they can never
        # be mistaken for a delimiter — non-special stretches are copied to
        # the cell verbatim. This runs for every row of every table on a
        # page; the per-row Array(Char) it replaces was one of the largest
        # allocation sources under parallel rendering (the Boehm GC
        # allocation lock is the contention point across workers).
        private def split_row(line : String) : Array(String)
          # `strip` must stay a String op (it handles Unicode whitespace);
          # it returns self when there is nothing to strip. The leading /
          # trailing pipe trims are ASCII, so instead of lchop/rchop —
          # which each heap-allocate a fresh String for the common
          # `| a | b |` shape — narrow the slice view (subslicing copies
          # nothing). Ordering matches the old sequential lchop-then-rchop:
          # the trailing check runs on the remainder, so a lone "|" trims
          # to "" exactly as before.
          stripped = line.strip
          bytes = stripped.to_slice
          if bytes.size > 0 && bytes[0] == 0x7C_u8 # leading '|'
            bytes = bytes[1, bytes.size - 1]
          end
          if bytes.size > 0 && bytes[bytes.size - 1] == 0x7C_u8 # trailing '|'
            bytes = bytes[0, bytes.size - 1]
          end

          cells = [] of String
          current = String::Builder.new
          len = bytes.size
          i = 0

          while i < len
            byte = bytes[i]
            if byte == 0x5C_u8 && i + 1 < len && bytes[i + 1] == 0x7C_u8 # '\' '|'
              # Escaped pipe - include literal pipe
              current << '|'
              i += 2
            elsif byte == 0x60_u8 # '`'
              # Inline code span: keep an interior `|` from splitting the cell.
              # An opening run of N backticks is closed by the next run of
              # exactly N; with no closer the backtick is literal and scanning
              # resumes from the next character. `\|` is still unescaped to a
              # bare pipe inside the span (GFM tables collapse it before the
              # code span is rendered — see the spec's `b `\|` az` example).
              run_len = backtick_run_length(bytes, i)
              close = find_closing_backtick_run(bytes, i + run_len, run_len)
              if close
                end_index = close + run_len
                k = i
                while k < end_index
                  if bytes[k] == 0x5C_u8 && k + 1 < end_index && bytes[k + 1] == 0x7C_u8
                    current << '|'
                    k += 2
                  else
                    span_start = k
                    k += 1
                    while k < end_index && bytes[k] != 0x5C_u8
                      k += 1
                    end
                    current.write(bytes[span_start, k - span_start])
                  end
                end
                i = end_index
              else
                run_len.times { current << '`' }
                i += run_len
              end
            elsif byte == 0x7C_u8 # '|'
              cells << current.to_s
              current = String::Builder.new
              i += 1
            else
              # Copy verbatim up to the next byte the scanner cares about.
              span_start = i
              i += 1
              while i < len
                b = bytes[i]
                break if b == 0x5C_u8 || b == 0x60_u8 || b == 0x7C_u8
                i += 1
              end
              current.write(bytes[span_start, i - span_start])
            end
          end
          cells << current.to_s

          cells
        end

        # Number of consecutive backticks starting at `start`.
        private def backtick_run_length(bytes : Bytes, start : Int32) : Int32
          run = 0
          while start + run < bytes.size && bytes[start + run] == 0x60_u8
            run += 1
          end
          run
        end

        # Index where a closing backtick run of exactly `run_len` backticks
        # begins, scanning from `start`. Returns nil when the span is never
        # closed (the opening run is then treated as literal text). Runs of a
        # different length are skipped, per CommonMark's code-span rule.
        private def find_closing_backtick_run(bytes : Bytes, start : Int32, run_len : Int32) : Int32?
          i = start
          while i < bytes.size
            if bytes[i] == 0x60_u8
              run = backtick_run_length(bytes, i)
              return i if run == run_len
              i += run
            else
              i += 1
            end
          end
          nil
        end

        # Parse alignment from separator cell
        private def parse_alignment(cell : String) : Alignment
          stripped = cell.strip
          left_colon = stripped.starts_with?(":")
          right_colon = stripped.ends_with?(":")

          if left_colon && right_colon
            Alignment::Center
          elsif right_colon
            Alignment::Right
          else
            Alignment::Left
          end
        end

        # Parse a complete table starting at the given line index
        # Returns {Table, lines_consumed} or {nil, 0} if not a valid table
        private def parse_table(lines : Array(String), start_index : Int32) : Tuple(Table?, Int32)
          return {nil, 0} if start_index >= lines.size

          header_line = lines[start_index]
          return {nil, 0} unless table_row?(header_line)
          return {nil, 0} if start_index + 1 >= lines.size

          separator_line = lines[start_index + 1]
          return {nil, 0} unless separator_row?(separator_line)

          # Parse headers
          headers = split_row(header_line)
          return {nil, 0} if headers.empty?

          # Parse alignments from separator
          separator_cells = split_row(separator_line)
          alignments = separator_cells.map { |cell| parse_alignment(cell) }

          # Parse body rows
          rows = [] of Array(String)
          i = start_index + 2

          while i < lines.size
            line = lines[i]
            break unless table_row?(line)
            # Also break if we hit another separator (new table)
            break if separator_row?(line) && i > start_index + 2

            cells = split_row(line)
            rows << cells
            i += 1
          end

          table = Table.new(headers, alignments, rows)
          lines_consumed = i - start_index

          {table, lines_consumed}
        end
      end
    end
  end
end
