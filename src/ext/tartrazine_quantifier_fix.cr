# Monkey-patch for Tartrazine's pattern compilation — kept here so we don't
# fork the vendored library, like ext/tartrazine_mt_fix.cr.
#
# The bundled lexers come from Pygments, where `x{,n}` means `x{0,n}`.
# PCRE2 reads that form as a quantifier only from 10.43 on; older PCRE2
# matches the five characters `{,n}` literally. hwaro links whatever PCRE2
# the build toolchain ships (the official Crystal macOS tarball bundles
# 10.42), so the same lexer highlighted differently per binary: on 10.42 the
# Python docstring rule `^(\s*)([rRuUbB]{,2})("""…""")` never matched and
# docstrings came out as plain strings, and C++ raw strings lost their `R`.
# Python, Python 2, C++, Arduino, GDScript 3, Hy and Mojo use the form.
#
# Every pattern now has `{,n}` rewritten to `{0,n}`, which all PCRE2
# versions read the same way. A brace inside a character class, an escaped
# brace and a `\Q…\E` literal are left alone.
#
# Remove when: every supported toolchain links PCRE2 >= 10.43.

require "tartrazine"

module BytesRegex
  # `pattern` with each `{,n}` quantifier spelled `{0,n}`.
  def self.hwaro_portable_quantifiers(pattern : String) : String
    return pattern unless pattern.includes?("{,")
    String.build(pattern.bytesize + 4) do |io|
      reader = Char::Reader.new(pattern)
      in_class = false
      while reader.has_next?
        char = reader.current_char
        if char == '\\'
          io << char
          nxt = reader.next_char
          break unless reader.has_next?
          io << nxt
          if nxt == 'Q'
            # \Q…\E: literal up to \E (or the end of the pattern).
            loop do
              c = reader.next_char
              break unless reader.has_next?
              io << c
              if c == '\\' && reader.peek_next_char == 'E'
                io << reader.next_char
                break
              end
            end
          end
        elsif in_class
          io << char
          if char == '[' && reader.peek_next_char == ':'
            # POSIX class `[:alpha:]` inside a bracket expression.
            close = pattern.byte_index(":]", reader.pos + 2)
            if close
              io << pattern.byte_slice(reader.pos + 1, close + 2 - reader.pos - 1)
              reader.pos = close + 1
            end
          elsif char == ']'
            in_class = false
          end
        elsif char == '['
          in_class = true
          io << char
          # `]` straight after `[` or `[^` is a literal member.
          if reader.peek_next_char == '^'
            io << reader.next_char
          end
          if reader.peek_next_char == ']'
            io << reader.next_char
          end
        elsif char == '{' && (digits = quantifier_upper_bound(pattern, reader.pos))
          io << "{0," << digits << '}'
          reader.pos += digits.bytesize + 2
        else
          io << char
        end
        reader.next_char
      end
    end
  end

  # The digits of a `{,n}` starting at byte `pos`, or nil.
  private def self.quantifier_upper_bound(pattern : String, pos : Int32) : String?
    return unless pattern.byte_at?(pos + 1) == ','.ord
    stop = pos + 2
    while (byte = pattern.byte_at?(stop)) && byte.unsafe_chr.ascii_number?
      stop += 1
    end
    return if stop == pos + 2 || pattern.byte_at?(stop) != '}'.ord
    pattern.byte_slice(pos + 2, stop - pos - 2)
  end

  class Regex
    def initialize(pattern : String, multiline = false, dotall = false, ignorecase = false, anchored = false)
      previous_def(BytesRegex.hwaro_portable_quantifiers(pattern), multiline, dotall, ignorecase, anchored)
    end
  end
end
