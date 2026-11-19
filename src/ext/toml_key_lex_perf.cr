# Monkey-patch for the vendored toml shard's lexer — kept here so we don't fork
# the library, like ext/toml_bare_key_fix.cr.
#
# `TOML::Lexer#consume_key` (toml 0.8.1, src/toml/lexer.cr:591-607) reads a
# bare word and, when it sits after an `=`, asks `process_math_constant`
# whether it is `inf` or `nan`. For every other word that method RAISES a
# `TOML::ParseException`, which `consume_key` rescues and discards:
# exceptions as control flow. `@before_eq_symbol` is only set back by a blank
# line, so in practice that is one raised-and-swallowed exception — message
# interpolation, backtrace capture, stack unwind — for every key after the
# first of a paragraph and for every `true`/`false` value. On macOS, where
# each unwind walks dyld's image list, that was 23 % of the CPU of a cold
# build of the 10k-page public benchmark corpus (one such key per page) and
# more on front matter with several keys.
#
# Same tokens, without the raise: `process_math_constant` is only called for
# the two words it accepts.
#
# Remove when: upstream stops raising for non-constants.

require "toml"

# Replaces the upstream method wholesale (no `previous_def`), so pin the
# version it was copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_key_lex_perf.cr replaces TOML::Lexer#consume_key from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Lexer
  private def consume_key
    @token.string_value = String.build do |io|
      io << current_char
      while key_part? next_char
        io << current_char
      end
    end
    @token.type = :KEY

    if !@before_eq_symbol && @token.string_value.in?("inf", "nan")
      process_math_constant(@token.string_value)
    end
  end
end
