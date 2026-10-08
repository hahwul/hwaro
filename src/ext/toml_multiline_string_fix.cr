# Monkey-patch for the vendored toml shard's multi-line string lexing — kept
# here so we don't fork the library, like ext/toml_datetime_fix.cr.
#
# `TOML::Lexer#consume_multine_basic_string` / `#consume_multine_literal_string`
# (toml 0.8.1, src/toml/lexer.cr:150-262) advanced one char too far after a
# quote run that was not the closing delimiter, so the char after it was lost:
# `"""say "hi" now"""` lexed as `say "i"now`, `'''it''s'''` as `it''`.
# They also closed at the first `"""`, so the up-to-two quotes TOML allows
# right before the delimiter (`"""a"""""` is `a""`) were a parse error.
#
# Both now read the whole quote run: fewer than three quotes are content,
# three to five close the string (the extras are content), more is an error.
#
# CRLF files (git autocrlf, Windows editors) were only half understood: a
# `\r\n` right after the opening delimiter was kept (so a `description = """`
# meta tag began with a stray CRLF), and a line-ending backslash before `\r\n`
# was "unknown escape: \". Both consumers now read `\r\n` as one newline and
# store it as `\n`, like the LF twin of the file (and Python's tomllib).
#
# Remove when: upstream lexes quote runs and CRLF inside multi-line strings
# correctly.

require "toml"

# Replaces the upstream methods wholesale (no `previous_def`), so pin the
# version they were copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_multiline_string_fix.cr replaces TOML::Lexer#consume_multine_basic_string/#consume_multine_literal_string from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Lexer
  # Consumes the run of *quote* chars starting at `current_char`, leaving
  # `current_char` on the first char after it. Writes the run's content
  # quotes to *io* and returns true when the run closes the string.
  private def hwaro_quote_run(io, quote : Char) : Bool
    count = 1
    while next_char == quote
      count += 1
    end
    raise "unexpected char '#{quote}'" if count > 5
    (count >= 3 ? count - 3 : count).times { io << quote }
    count >= 3
  end

  # Skips the newline (`\n` or `\r\n`) right after an opening `"""` / `'''`;
  # `current_char` is the last delimiter char on entry.
  private def hwaro_skip_opening_newline
    case next_char
    when '\n'
      newline
      next_char
    when '\r'
      raise "expected '\\n' after '\\r'" unless next_char == '\n'
      newline
      next_char
    end
  end

  private def consume_multine_basic_string
    hwaro_skip_opening_newline

    @token.string_value = String.build do |io|
      loop do
        case current_char
        when '"'
          break if hwaro_quote_run(io, '"')
        when '\\'
          continuation = false
          case next_char
          when '\n'
            continuation = true
          when '\r'
            raise "unknown escape: \\\r" unless next_char == '\n'
            continuation = true
          end
          if continuation
            newline
            next_char
            loop do
              case current_char
              when ' ', '\t'
                next_char
              when '\n'
                newline
                next_char
              when '\r'
                # CRLF is a newline; a lone CR is content.
                if next_char == '\n'
                  newline
                  next_char
                else
                  io << '\r'
                  break
                end
              else
                break
              end
            end
          else
            consume_escape(io)
          end
        when '\n'
          newline
          io << '\n'
          next_char
        when '\r'
          # CRLF is stored as LF; a lone CR stays content.
          if next_char == '\n'
            newline
            io << '\n'
            next_char
          else
            io << '\r'
          end
        when '\0'
          raise "unterminated string literal"
        else
          io << current_char
          next_char
        end
      end
    end
  end

  private def consume_multine_literal_string
    hwaro_skip_opening_newline

    @token.string_value = String.build do |io|
      loop do
        case current_char
        when '\''
          break if hwaro_quote_run(io, '\'')
          next
        when '\n'
          newline
          io << '\n'
        when '\r'
          # CRLF is stored as LF; a lone CR stays content.
          if next_char == '\n'
            newline
            io << '\n'
          else
            io << '\r'
            next
          end
        when '\0'
          raise "unterminated string literal"
        else
          io << current_char
        end
        next_char
      end
    end
  end
end
