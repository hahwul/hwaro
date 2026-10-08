# Monkey-patch for the vendored toml shard's parser — kept here so we don't
# fork the library, like ext/toml_nesting_limit_fix.cr (which owns
# `parse_value`; this file touches only the methods below, so the two never
# redefine the same one).
#
# Valid TOML that toml 0.8.1 (src/toml/parser.cr) rejected, aborting the build
# with HWARO_E_CONTENT / HWARO_E_CONFIG for front matter, config.toml and
# data/*.toml alike:
#
#   * `tags = ["a"]` + `[extra.tags]` — `parse_table_header` (:181) looked the
#     header component up in the ROOT table instead of the table being
#     walked, so any root-level array whose key matched the last segment of a
#     dotted header was "a static array being appended to".
#   * `list = {}` — `parse_inline_table` (:319) had no empty-table branch.
#   * an array with a comment line, or a leading comma, before `]` —
#     `parse_array` (:275) consumed exactly one NEWLINE after a value.
#   * `[1, 2.5]` / `["a", 1]` — `parse_array` enforced the TOML 0.x rule that
#     elements share a type; TOML 1.0 dropped it.
#
# Remove when: upstream fixes these four.

require "toml"

# Replaces the upstream methods wholesale (no `previous_def`), so pin the
# version they were copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_parser_fix.cr replaces TOML::Parser#parse_table_header/#parse_array/#parse_inline_table from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Parser
  private def parse_table_header(root_table)
    next_token

    if token.type == :"["
      # Array of Tables
      next_token
      return parse_array_table_header(root_table)
    end

    # Table. `table` is the table the component lives in; for a single
    # segment header it IS the root, so the check is unchanged there.
    parse_header(root_table) do |table, name, has_more_names|
      raise "Cannot append to static array array" if (existing = table[name]?) && existing.is_static_array?
      handle_table(table, name, has_more_names)
    end
  end

  private def parse_array
    next_token

    ary = [] of Any

    while true
      case token.type
      when :NEWLINE
        next_token
        next
      when :"]"
        next_token
        break
      else
        ary << parse_value

        # Blank and comment-only lines may precede the separator.
        while token.type == :NEWLINE
          next_token
        end

        case token.type
        when :","
          next_token
        when :"]"
          next_token
          break
        else
          raise "expected ',', ']' or newline, not #{token}"
        end
      end
    end

    ary
  end

  private def parse_inline_table
    next_token

    table = Table.new
    if token.type == :"}"
      next_token
      return table
    end

    while true
      case token.type
      when :KEY, :STRING, :INT
        parse_key_value_after_key(table)

        if token.type == :","
          next_token
        end

        if token.type == :"}"
          next_token
          break
        end
      else
        unexpected_token
      end
    end
    table
  end
end
