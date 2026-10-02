# XML minifier for raw `.xml` files published from content/ (see
# Phases::Write#process_raw_files).

module Hwaro
  module Content
    module Processors
      module Xml
        extend self

        # CDATA sections and comments extracted as opaque placeholders
        # before minification. `\x00` is illegal in XML, so the token
        # cannot collide with author content.
        private CDATA_COMMENT_RE  = /<!\[CDATA\[.*?\]\]>|<!--.*?-->/m
        private PRESERVE_TOKEN_RE = /\x00HWXMLP(\d+)\x00/

        # A whitespace-only text node that spans a line break — the
        # pretty-printing between tags this minifier removes.
        private INDENT_RE    = /\A\s*\n\s*\z/
        private XML_SPACE_RE = /\sxml:space\s*=\s*["'](preserve|default)["']/

        # Simple XML minification - removes excess whitespace.
        #
        # Only cross-line, whitespace-only text BETWEEN tags is removed, and
        # only where it is formatting: inside an element whose children are
        # all elements. In mixed content (`<t>Hello <b>bold</b>\n <i>x</i></t>`)
        # that whitespace is a word separator — removing it rendered
        # "bolditalic" — and under `xml:space="preserve"` it is content by
        # declaration, so both keep it verbatim.
        def minify(xml : String) : String
          # CDATA sections and comments are raw character data — the
          # cross-line collapse below must never reach inside them (a
          # CDATA body containing `</a>\n<em>` is content, not markup).
          # Stash them behind placeholders and restore verbatim at the end.
          preserved = [] of String
          work = xml.gsub(CDATA_COMMENT_RE) do |m|
            preserved << m
            "\x00HWXMLP#{preserved.size - 1}\x00"
          end

          tokens = tokenize_xml(work)
          removable = removable_indents(tokens, preserved)

          result = String.build(work.bytesize) do |io|
            tokens.each_with_index do |token, i|
              next if removable.includes?(i)
              if token.starts_with?('<')
                # Collapse whitespace runs only BETWEEN attributes; leave
                # whitespace inside quoted attribute values intact (e.g.
                # `title="a    b"`), otherwise the minifier silently corrupts
                # attribute content. Comments and CDATA sections are
                # placeholders here and never reach this branch.
                io << token.gsub(/("[^"]*"|'[^']*')|\s{2,}/) do |m|
                  (m.starts_with?('"') || m.starts_with?('\'')) ? m : " "
                end
              else
                io << token
              end
            end
          end.strip
          return result if preserved.empty?
          result.gsub(PRESERVE_TOKEN_RE) do
            # to_i? bounds-guards a counterfeit token (NUL is illegal in
            # XML, but be defensive): emit it unchanged instead of raising.
            idx = $1.to_i?
            idx && idx < preserved.size ? preserved[idx] : $0
          end
        end

        # Split into tags (`<...>`) and the text runs between them. Byte
        # offsets: `<` and `>` are ASCII, so slicing on them never splits a
        # UTF-8 sequence, and char indexing would be quadratic on non-ASCII
        # input.
        private def tokenize_xml(work : String) : Array(String)
          tokens = [] of String
          pos = 0
          size = work.bytesize
          while pos < size
            if work.byte_at(pos) == '<'.ord && (close = tag_end(work, pos))
              tokens << work.byte_slice(pos, close - pos + 1)
              pos = close + 1
            else
              stop = work.byte_index('<'.ord, pos + 1) || size
              tokens << work.byte_slice(pos, stop - pos)
              pos = stop
            end
          end
          tokens
        end

        # Byte index of the `>` closing the tag that opens at `pos`, skipping
        # any `>` inside a quoted attribute value (`<x a="1>2"/>` is one
        # self-closing tag, not an open element that never closes). An
        # unbalanced quote falls back to the first `>`, so malformed input
        # never swallows the rest of the document.
        private def tag_end(work : String, pos : Int32) : Int32?
          quote = 0_u8
          i = pos + 1
          size = work.bytesize
          while i < size
            byte = work.byte_at(i)
            if quote != 0
              quote = 0_u8 if byte == quote
            elsif byte == '"'.ord || byte == '\''.ord
              quote = byte
            elsif byte == '>'.ord
              return i
            end
            i += 1
          end
          work.byte_index('>'.ord, pos)
        end

        # Indices of the cross-line whitespace-only text tokens that sit
        # between two tags inside an element-only parent (or at document
        # level) outside any `xml:space="preserve"` scope.
        private def removable_indents(tokens : Array(String), preserved : Array(String)) : Set(Int32)
          # Per open element: does it carry character data, and is it in a
          # preserve scope? Document level (empty stack) is element-only.
          mixed = [] of Bool
          preserve = [] of Bool
          stack = [] of Int32
          parent_of = {} of Int32 => Int32
          candidates = [] of Int32

          tokens.each_with_index do |token, i|
            if token.starts_with?('<')
              if token.starts_with?("</")
                stack.pop?
              elsif token.starts_with?("<?") || token.starts_with?("<!") || token.ends_with?("/>")
                # declaration, processing instruction, empty element
              else
                inherited = stack.empty? ? false : preserve[stack.last]
                # An explicit `xml:space` wins either way: "default" resets an
                # inherited preserve.
                preserve << ((m = token.match(XML_SPACE_RE)) ? m[1] == "preserve" : inherited)
                mixed << false
                stack << mixed.size - 1
              end
            elsif INDENT_RE.matches?(token)
              prev_tag = i > 0 && tokens[i - 1].starts_with?('<')
              next_tag = i + 1 < tokens.size && tokens[i + 1].starts_with?('<')
              if prev_tag && next_tag
                candidates << i
                parent_of[i] = stack.last? || -1
              end
            elsif (top = stack.last?) && character_data?(token, preserved)
              mixed[top] = true
            end
          end

          removable = Set(Int32).new
          candidates.each do |i|
            parent = parent_of[i]
            next if parent >= 0 && (mixed[parent] || preserve[parent])
            removable << i
          end
          removable
        end

        # True when a text token holds character data: anything but
        # whitespace and stashed comments (a CDATA section is character data).
        private def character_data?(token : String, preserved : Array(String)) : Bool
          stripped = token.gsub(PRESERVE_TOKEN_RE) do
            idx = $1.to_i?
            idx && idx < preserved.size && preserved[idx].starts_with?("<!--") ? "" : "x"
          end
          !stripped.strip.empty?
        end
      end
    end
  end
end
