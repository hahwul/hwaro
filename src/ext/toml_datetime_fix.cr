# Monkey-patch for the vendored toml shard's date/time lexing — kept here so
# we don't fork the library, like ext/toml_nesting_limit_fix.cr.
#
# `TOML::Lexer#consume_datetime` / `#consume_time` (toml 0.8.1,
# src/toml/lexer.cr:502-581) read fractional seconds as EXACTLY six digits:
# `2024-03-05T10:20:30.5Z` and `…30.123Z` fail with "expected microsecond
# digit", and `…30.123456789Z` with "unexpected token". TOML allows any
# precision ("fractional seconds … at least millisecond precision"), and
# millisecond timestamps are what most tools export, so a valid front-matter
# date aborted the build with HWARO_E_CONTENT. Digits past nanoseconds are
# truncated, as the TOML spec permits.
#
# Remove when: upstream accepts arbitrary fractional-second precision.

require "toml"

# Replaces the upstream methods wholesale (no `previous_def`), so pin the
# version they were copied from — see toml_nesting_limit_fix.cr.
{% if (shard_yml = read_file?("lib/toml/shard.yml")) && !shard_yml.includes?("version: 0.8.1") %}
  {% raise "src/ext/toml_datetime_fix.cr replaces TOML::Lexer#consume_datetime/#consume_time from toml 0.8.1, but a different toml version is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

class TOML::Lexer
  # Reads the digits after a `.` (already consumed) and leaves
  # `current_char` on the first non-digit, like the upstream six-digit read
  # followed by `next_char`. Returns nanoseconds.
  private def hwaro_consume_fraction : Int32
    nanos = 0
    digits = 0
    char = next_char
    raise "expected fractional second digit" unless char.ascii_number?
    while char.ascii_number?
      if digits < 9
        nanos = nanos * 10 + char.to_i
        digits += 1
      end
      char = next_char
    end
    (9 - digits).times { nanos *= 10 }
    nanos
  end

  private def consume_time(hour)
    minute = consume_datetime_component 2, "expected minute digit"
    raise "expected ':'" unless next_char == ':'
    second = consume_datetime_component 2, "expected second digit"

    nanosecond = next_char == '.' ? hwaro_consume_fraction : 0

    time_local = Time.local
    time = Time.local(time_local.year, time_local.month, time_local.day, hour.to_i32,
      minute, second, nanosecond: nanosecond)

    @token.type = :TIME
    @token.time_value = time
  end

  private def consume_datetime(year)
    t_delimiter_with_space = false

    month = consume_datetime_component 2, "expected month digit"
    raise "expected '-'" unless next_char == '-'
    day = consume_datetime_component 2, "expected day digit"
    case next_char
    when 'T'
    when ' '
      t_delimiter_with_space = true
    else
      @token.type = :TIME
      @token.time_value = Time.local(year.to_i32, month, day)
      return
    end
    if t_delimiter_with_space && !peek_next_char.to_i?
      @token.type = :TIME
      @token.time_value = Time.local(year.to_i32, month, day)
      return
    end
    hour = consume_datetime_component 2, "expected hour digit"
    raise "expected ':'" unless next_char == ':'
    minute = consume_datetime_component 2, "expected minute digit"
    raise "expected ':'" unless next_char == ':'
    second = consume_datetime_component 2, "expected second digit"

    nanosecond = next_char == '.' ? hwaro_consume_fraction : 0

    local_time = false

    negative = false
    case current_char
    when 'Z'
      next_char
    when '+', '-'
      negative = current_char == '-'
      hour_offset = consume_datetime_component 2, "expected hour offset digit"
      raise "expected ':'" unless next_char == ':'
      minute_offset = consume_datetime_component 2, "expected minute offset digit"
      next_char
    else
      local_time = true
    end

    if local_time
      time = Time.local(year.to_i32, month, day, hour, minute, second, nanosecond: nanosecond)
    else
      time = Time.utc(year.to_i32, month, day, hour, minute, second, nanosecond: nanosecond)
      time += (negative ? hour_offset : -hour_offset).hours if hour_offset
      time += (negative ? minute_offset : -minute_offset).minutes if minute_offset
    end

    @token.type = :TIME
    @token.time_value = time
  end
end
