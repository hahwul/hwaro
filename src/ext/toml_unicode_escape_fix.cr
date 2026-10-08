# Monkey-patch for the vendored toml shard's `\u` escape — kept here so we
# don't fork the library, like ext/toml_multiline_string_fix.cr.
#
# `TOML::Lexer#consume_unicode_scalar` (toml 0.8.1, src/toml/lexer.cr:297-313)
# read four hex digits and then speculatively consumed a fifth char as the start
# of an 8-digit escape, so `"\u000Bb"` was a parse error ("expecting
# hexadecimal number") and `\U` was not supported at all ("unknown escape").
# Anything written as `\uXXXX` directly before a hex digit (every control char
# `FrontmatterWriter.escape_toml_string` emits) produced an unloadable file.
#
# Per the TOML spec, `\u` is exactly four hex digits and `\U` exactly eight.
#
# Remove when: upstream lexes `\u`/`\U` per the spec.

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
      io << hwaro_unicode_scalar(4)
      return
    when 'U'
      io << hwaro_unicode_scalar(8)
      return
    when '\\', '\'', '"'
      io << current_char
    else
      raise "unknown escape: \\#{current_char}"
    end

    next_char
  end

  # Reads exactly *digits* hex digits after `\u`/`\U`, leaving `current_char`
  # on the first char after the escape.
  private def hwaro_unicode_scalar(digits : Int32) : Char
    value = 0
    digits.times do
      value = value * 16 + (next_char.to_i?(16) || raise("expecting hexadecimal number"))
    end
    next_char

    raise "invalid unicode scalar: #{value.to_s(16)}" unless value <= 0x10FFFF && !(0xD800..0xDFFF).includes?(value)
    value.chr
  end
end
