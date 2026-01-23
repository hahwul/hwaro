# Markdown Table Parser
#
# This module parses markdown tables and converts them to HTML.
# Since markd doesn't support GFM tables, this provides table support
# by preprocessing markdown content before passing to markd.
#
# Supported features:
# - Basic pipe-delimited tables
# - Column alignment (left, center, right)
# - Inline formatting within cells (handled by markd after conversion)
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

          # Convert table to HTML
          def to_html : String
            html = String.build do |str|
              str << "<table>\n"
              str << "<thead>\n<tr>\n"

              @headers.each_with_index do |header, i|
                alignment = @alignments[i]? || Alignment::Left
                align_attr = alignment_attr(alignment)
                str << "<th#{align_attr}>#{escape_html(header.strip)}</th>\n"
              end

              str << "</tr>\n</thead>\n"

              if @rows.any?
                str << "<tbody>\n"
                @rows.each do |row|
                  str << "<tr>\n"
                  row.each_with_index do |cell, i|
                    alignment = @alignments[i]? || Alignment::Left
                    align_attr = alignment_attr(alignment)
                    str << "<td#{align_attr}>#{escape_html(cell.strip)}</td>\n"
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

              str << "</table>"
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

          private def escape_html(text : String) : String
            text
              .gsub("&", "&amp;")
              .gsub("<", "&lt;")
              .gsub(">", "&gt;")
              .gsub("\"", "&quot;")
          end
        end

        # Process markdown content and convert tables to HTML
        # Tables are converted to HTML placeholders, then markd processes the rest,
        # and placeholders are replaced with actual HTML tables.
        def process(content : String) : String
          return content unless has_table?(content)

          lines = content.split("\n")
          result = [] of String
          i = 0

          while i < lines.size
            # Check if this could be the start of a table
            if table_row?(lines[i]) && i + 1 < lines.size && separator_row?(lines[i + 1])
              # Try to parse the table
              table, consumed = parse_table(lines, i)
              if table
                result << table.to_html
                i += consumed
                next
              end
            end

            result << lines[i]
            i += 1
          end

          result.join("\n")
        end

        # Quick check if content might contain tables
        def has_table?(content : String) : Bool
          content.includes?("|")
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
            cell.matches?(/^:?-{1,}:?$/)
          end
        end

        # Split a table row into cells
        private def split_row(line : String) : Array(String)
          stripped = line.strip

          # Remove leading pipe if present
          if stripped.starts_with?("|")
            stripped = stripped[1..]
          end

          # Remove trailing pipe if present
          if stripped.ends_with?("|")
            stripped = stripped[0..-2]
          end

          # Split by pipe, handling escaped pipes
          cells = [] of String
          current = String::Builder.new
          i = 0
          chars = stripped.chars

          while i < chars.size
            char = chars[i]
            if char == '\\' && i + 1 < chars.size && chars[i + 1] == '|'
              # Escaped pipe - include literal pipe
              current << '|'
              i += 2
            elsif char == '|'
              cells << current.to_s
              current = String::Builder.new
              i += 1
            else
              current << char
              i += 1
            end
          end
          cells << current.to_s

          cells
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
