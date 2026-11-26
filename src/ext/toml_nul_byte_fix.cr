# Monkey-patch for the vendored toml shard's lexer — kept here so we don't fork
# the library, like ext/toml_syntax_fix.cr.
#
# `TOML::Lexer` (toml 0.8.1) spells end of input as `@input.read_char || '\0'`
# and every loop tests `when '\0'` for EOF, so a raw NUL byte in the source
# was indistinguishable from the end of the file. Outside a string — in a
# comment, between key/value lines, or as the first byte — the lexer emitted
# EOF there and the parser returned the table read so far: everything after
# the NUL vanished without an error. A stray NUL in front matter
# (`+++\ntitle = "x"\n# note<NUL>\ndraft = true\n+++`) published a draft;
# in config.toml it dropped every setting below it; a file that STARTED with
# a NUL parsed as an empty table. TOML forbids raw control characters other
# than tab everywhere (strings, comments, whitespace), so a NUL read from the
# input is now a `ParseException` at its line and column. EOF stays `'\0'`.
#
# Replaces the upstream `initialize` and `peek_next_char`; `next_char` (already
# replaced in ext/toml_datetime_fix.cr) reads through `read_source_char` too.
#
# Remove when: upstream tells a NUL byte from end of input.

require "toml"

# Replaces upstream methods wholesale (no `previous_def`), so pin the version
# they were copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_nul_byte_fix.cr replaces TOML::Lexer#initialize/#peek_next_char from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Lexer
  def initialize(@input : IO)
    @token = Token.new
    @line_number = 1
    @column_number = 1
    @before_eq_symbol = true
    @current_char = '\0'
    @current_char = read_source_char
  end

  private def peek_next_char : Char
    if peeked = @peeked
      return peeked
    end
    @peeked = read_source_char
  end

  # The next char of the input, `'\0'` at end of input. A NUL byte IN the
  # input raises instead of passing for EOF.
  private def read_source_char : Char
    char = @input.read_char
    raise "NUL byte (U+0000) is not allowed in TOML" if char == '\0'
    char || '\0'
  end
end
