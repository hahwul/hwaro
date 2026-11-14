# Monkey-patch for the vendored toml shard's lexer — kept here so we don't fork
# the library, like ext/toml_syntax_fix.cr.
#
# TOML bare keys are `A-Za-z0-9_-` (TOML 1.0 "Keys"), so `2024 = "x"`,
# `1password = true`, `-dash = 1`, `007 = 1`, `1e3 = 1`, `inf = 1` and
# `[2024]` are all valid. toml 0.8.1 lexes a token by its first character, so
# a key starting with a digit or `-` was read as a number (`-dash` and `1e3`
# failed to parse; `0x1` and `1_0` silently became the keys `1` and `10`) and
# `inf`/`nan` as a math constant. Only the position of the token says whether
# it is a key: this patch tracks that in the lexer (line starts, table
# headers, after `.` and after `{`/`,` of an inline table) and reads a bare
# key as one run of key characters there. Values lex exactly as before.
#
# Remove when: upstream fixes bare keys.

require "toml"

class TOML::Lexer
  # True while the next token is a key (or a table-header segment).
  @key_pos = true
  # Open `[` (array value) / `{` (inline table) contexts of the value being lexed.
  @nest = [] of Char

  def next_token : Token
    skip_whitespace
    skip_comment
    if @key_pos && key_part?(current_char)
      @token.line_number = @line_number
      @token.column_number = @column_number
      consume_key
      @token.type = :KEY
      @key_pos = false
      return @token
    end
    token = previous_def
    track_key_position(token.type)
    token
  end

  private def track_key_position(type) : Nil
    case type
    when :NEWLINE
      @key_pos = @nest.empty?
    when :"["
      # At a key position (and not inside a value) `[`/`[[` opens a header.
      if @key_pos
        # still waiting for the first key segment
      else
        @nest << '['
      end
    when :"]"
      @nest.pop? unless @nest.empty?
      @key_pos = false
    when :"{"
      @nest << '{'
      @key_pos = true
    when :"}"
      @nest.pop? unless @nest.empty?
      @key_pos = false
    when :","
      @key_pos = @nest.last? == '{'
    when :"."
      @key_pos = true
    else
      @key_pos = false
    end
  end
end
