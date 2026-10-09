# Monkey-patch for the vendored toml shard — valid TOML 1.0 that its lexer and
# parser reject (toml 0.8.1), kept here so we don't fork the library, like
# ext/toml_datetime_fix.cr.
#
# * `\uXXXX` / `\UXXXXXXXX` — `TOML::Lexer#consume_unicode_scalar` read four
#   hex digits and then, if the NEXT char was also a hex digit, kept going for
#   four more. `"éab"` (é then "ab") therefore failed with "expecting
#   hexadecimal number" or "0xe9abcd out of char range". `\u` is exactly four
#   digits. `consume_escape` also had no `\U` arm (exactly eight digits), so
#   `"\U0001F600"` was "unknown escape". Surrogates and values past U+10FFFF
#   are a `ParseException` instead of an `ArgumentError` from `Int#chr`.
# * `0x` / `0o` / `0b` integers — `TOML::Lexer#consume_number` stopped at the
#   leading `0` and the prefix letter became a stray token. Only after the `=`
#   (bare keys such as `0b` are untouched), unsigned, `_` allowed between
#   digits, out-of-range values are a `ParseException`. `consume_number`
#   itself lives in ext/toml_float_fix.cr and hands the prefix to
#   `consume_prefixed_integer` here.
#
# Replaces the upstream methods wholesale (no `previous_def`).
#
# Remove when: upstream lexes TOML 1.0 escapes and prefixed integers.

require "toml"

# Pin the version the copies were taken from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_syntax_fix.cr replaces TOML::Lexer#consume_escape/#consume_unicode_scalar from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Lexer
  private def consume_escape(io)
    case current_char
    when 'b'
      io << '\b'
    when 't'
      io << '\t'
    when 'n'
      io << '\n'
    when 'f'
      io << '\f'
    when 'r'
      io << '\r'
    when 'u'
      io << consume_unicode_scalar(4)
      return
    when 'U'
      io << consume_unicode_scalar(8)
      return
    when '\\', '\'', '"'
      io << current_char
    else
      raise "unknown escape: \\#{current_char}"
    end

    next_char
  end

  # Reads exactly *digits* hex digits after the escape letter and leaves
  # `current_char` on the first char after them (what `consume_escape`'s
  # callers expect).
  private def consume_unicode_scalar(digits : Int32)
    value = 0_i64
    digits.times do
      value = value * 16 + (next_char.to_i?(16) || raise("expecting hexadecimal number"))
    end
    next_char
    raise "invalid unicode scalar value" if value > 0x10FFFF || (0xD800..0xDFFF).includes?(value)
    value.to_i32.chr
  end

  # `current_char` is the prefix letter of `0x…` / `0o…` / `0b…`.
  private def consume_prefixed_integer(base : Int32)
    digits = String.build do |io|
      last_is_underscore = true # no leading underscore
      while (char = next_char).to_i?(base) || char == '_'
        if char == '_'
          raise "double underscores in a number are now allowed" if last_is_underscore
          last_is_underscore = true
        else
          io << char
          last_is_underscore = false
        end
      end
      raise "expecting digit after integer prefix" if io.bytesize == 0 || last_is_underscore
    end
    @token.type = :INT
    @token.int_value = digits.to_i64?(base) || raise("integer out of range")
  end
end
