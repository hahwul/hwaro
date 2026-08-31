# Monkey-patch for the vendored toml shard's parser — kept here so we don't
# fork the library, mirroring ext/markd_entity_fix.cr and
# ext/crinja_resolve_fix.cr.
#
# `TOML::Parser#parse_value` (toml 0.8.1, src/toml/parser.cr:103) and
# `#parse_array` (:275) / `#parse_inline_table` (:319) are mutually recursive
# with no nesting counter, so nesting in the SOURCE maps one-for-one onto
# native stack frames:
#
#   x = [[[[[[ … 8000 deep … ]]]]]]        # data/deep.toml, or +++ front matter
#
# That exhausts the stack: `Stack overflow (e.g., infinite or very deep
# recursion)`, ~15.5k backtrace lines, exit 11. Crystal cannot rescue a
# stack overflow, so it walks straight through both hwaro call sites —
# `DataDisk.parse_file` (which warns and drops the key) and
# `Processors::Markdown#extract_from_toml` (which raises HWARO_E_CONTENT) —
# both of which assume a malformed file arrives as a catchable exception.
# The same input as JSON or YAML degrades cleanly, because Crystal's own
# parsers cap nesting at 512 ("Nesting of 513 is too deep").
#
# So we give TOML the same cap. `parse_value` is the single choke point:
# every array element and every inline-table value goes through it, so
# counting entries there counts nesting depth exactly, and the counter is a
# plain instance variable on a parser that is created fresh per
# `TOML.parse` (no sharing between fibers). The limit matches Crystal's
# `JSON::PullParser`/`YAML` MAX_NESTING of 512 deliberately: no hand-written
# TOML comes close, and 512 is far below the ~3800 levels it took to blow
# the stack, leaving room for the recursive conversion (`CrinjaUtils
# .from_toml`) that runs over the parsed value afterwards.
#
# The private `raise(msg)` helper (parser.cr:349) is what upstream uses for
# every other parse failure: it raises `TOML::ParseException` with the
# current line/column, which is exactly what both hwaro call sites already
# catch. Valid TOML is unaffected — the only added work on the happy path is
# an integer increment and decrement per value.
#
# Remove when: upstream bounds recursion in `parse_value`.

require "toml"

# Like markd_list_fix.cr this REPLACES the upstream method wholesale (no
# `previous_def`), so a shard bump changing `parse_value` would be silently
# reverted by the copy below. The toml shard ships no VERSION constant, so the
# pin is read from its shard.yml at compile time; `read_file?` keeps a build
# from an unusual working directory (where the relative path misses) working
# exactly as before rather than failing on the guard itself.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_nesting_limit_fix.cr replaces TOML::Parser#parse_value verbatim from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Parser
  # See the header: same value as Crystal's JSON/YAML parsers.
  HWARO_MAX_NESTING = 512

  @hwaro_nesting_depth : Int32 = 0

  private def parse_value : Any
    @hwaro_nesting_depth += 1
    if @hwaro_nesting_depth > HWARO_MAX_NESTING
      raise "Nesting of #{@hwaro_nesting_depth} is too deep"
    end

    value = case token.type
            when :KEY
              case token.string_value
              when "true"
                true.tap { next_token }
              when "false"
                false.tap { next_token }
              else
                unexpected_token
              end
            when :INT
              token.int_value.tap { next_token }
            when :FLOAT
              token.float_value.tap { next_token }
            when :STRING
              token.string_value.tap { next_token }
            when :TIME
              token.time_value.tap { next_token }
            when :"["
              parse_array
            when :"{"
              parse_inline_table
            else
              unexpected_token
            end
    Any.new value
  ensure
    @hwaro_nesting_depth -= 1
  end
end
