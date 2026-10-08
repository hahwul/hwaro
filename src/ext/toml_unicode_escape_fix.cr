# Monkey-patch for the vendored toml shard's `\u` escape — kept here so we
# don't fork the library, like ext/toml_datetime_fix.cr.
#
# `TOML::Lexer#consume_unicode_scalar` (toml 0.8.1, src/toml/lexer.cr:298) read
# four hex digits, then peeked the next char and, when that was a hex digit
# too, kept going as if it were an 8-digit `\U` escape: `"ée"` failed
# with "expecting hexadecimal number" and `"Acafe"` with "0x41cafe out of
# char range" (an ArgumentError, which no caller treats as a parse failure).
# There was no real `\U` at all ("unknown escape"). TOML says `\u` is exactly
# four hex digits and `\U` exactly eight; everything after is literal text.
#
# That made `FrontmatterWriter.escape_toml_string` (control chars -> `\u00XX`)
# emit files hwaro could not read back whenever a hex digit followed.
#
# Remove when: upstream reads `\u` as exactly four digits and supports `\U`.

require "toml"

# Replaces the upstream methods wholesale (no `previous_def`), so pin the
# version they were copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_unicode_escape_fix.cr replaces TOML::Lexer#consume_escape/#consume_unicode_scalar from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
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

  # Reads exactly *digits* hex digits after the `u`/`U` (current char) and
  # leaves `current_char` on the first char after them.
  private def consume_unicode_scalar(digits : Int32 = 4)
    value = 0_i64

    digits.times do
      value = value * 16 + (next_char.to_i?(16) || raise("expecting hexadecimal number"))
    end
    next_char

    if value > 0x10FFFF || (0xD800..0xDFFF).includes?(value)
      raise "invalid unicode scalar value U+#{value.to_s(16).upcase}"
    end
    value.to_i32.chr
  end
end
