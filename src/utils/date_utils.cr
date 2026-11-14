# Shared date parsing for content dates.
#
# Two parsers live here on purpose — they accept different inputs and must
# not be merged:
#
# - `parse_lenient` is the RFC-3339-first, format-table parser used by
#   importers, which read dates written by OTHER tools.
# - `parse_content_date` mirrors the build's front-matter parser
#   (`Processors::Markdown#parse_time` delegates here), which defines what
#   a hwaro site itself accepts — so the content tools that report what a
#   build will do (`tool list` / `tool stats`) use it too.

module Hwaro
  module Utils
    module DateUtils
      extend self

      # Formats accepted by `parse_lenient`. Zone-bearing formats come
      # FIRST: Crystal's `Time.parse` ignores trailing input, so a zone-less
      # pattern would happily match `2026-07-01T10:00:00+09:00`, silently
      # drop the `+09:00`, and shift the instant by the whole offset.
      CONTENT_FORMATS = [
        "%Y-%m-%dT%H:%M:%S%:z",
        "%Y-%m-%dT%H:%M:%S%z",
        # Jekyll's conventional `2024-01-15 10:00:00 +0900`
        "%Y-%m-%d %H:%M:%S %:z",
        "%Y-%m-%d %H:%M:%S %z",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d",
      ]

      # Importers additionally accept minute-precision, slash and RFC 822
      # dates (and prose dates, see `parse_import`) — what Jekyll, Hexo and Astro accept in front matter.
      # The minute-precision formats must precede the bare `%Y-%m-%d` (the
      # last CONTENT_FORMATS entry): it ignores trailing input, so it matched
      # `2024-01-15 10:30` and silently dropped the time.
      IMPORT_FORMATS = CONTENT_FORMATS[0...-1] + [
        "%Y-%m-%dT%H:%M%:z",
        "%Y-%m-%d %H:%M %:z",
        "%Y-%m-%d %H:%M %z",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %H:%M",
        CONTENT_FORMATS.last,
        # Hexo's `2024/01/20 14:00:00` — zone-bearing forms first, for the
        # same trailing-input reason as above.
        "%Y/%m/%d %H:%M:%S %:z",
        "%Y/%m/%d %H:%M:%S %z",
        "%Y/%m/%d %H:%M %:z",
        "%Y/%m/%d %H:%M %z",
        "%Y/%m/%d %H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y/%m/%d",
        # RFC 822 (WordPress <pubDate>, RSS feeds)
        "%a, %d %b %Y %H:%M:%S %z",
      ]

      # Prose dates (`July 8, 2022`, and `Jul 08 2022` from Astro's blog
      # template, a JS Date string). Tried only on input shaped like
      # `Month D YYYY`: unguarded, `%B %d %Y` read `May 2022` as day 20 of
      # the year 22.
      PROSE_DATE_RE      = /\A[A-Za-z]+\.? \d{1,2},? \d{4}\b/
      PROSE_DATE_FORMATS = ["%B %d, %Y", "%B %d %Y"]

      # The importers' parser: `parse_lenient` over IMPORT_FORMATS, then the
      # guarded prose formats.
      def parse_import(date_str : String) : Time?
        parse_lenient(date_str, IMPORT_FORMATS) ||
          (date_str.strip.matches?(PROSE_DATE_RE) ? parse_lenient(date_str, PROSE_DATE_FORMATS) : nil)
      end

      # Parse a date string in common formats, returns nil on failure.
      # RFC 3339 is probed first, then the format table in UTC.
      def parse_lenient(date_str : String, formats : Array(String) = CONTENT_FORMATS) : Time?
        str = date_str.strip

        begin
          return Time.parse_rfc3339(str)
        rescue Time::Format::Error | Time::Error | ArgumentError
          # Time::Format::Error → not RFC 3339 at all. ArgumentError → the
          # shape is RFC 3339 but the value is impossible ("2024-02-30").
          # Either way, fall through to the lenient formats.
        end

        formats.each do |fmt|
          return Time.parse(str, fmt, Time::Location::UTC)
        rescue Time::Format::Error | Time::Error | ArgumentError
          next
        end

        nil
      end

      # The shape of a date the build reads: a four-digit year, optionally a
      # time of day (`T`, `t` or a space, then `HH:MM:SS` and a fraction) and
      # a zone (`Z`, `+09`, `+0900` or `+09:00`, also after a space). The whole
      # string must match: `Time.parse` ignores trailing input, so any looser
      # route dropped a written offset it did not recognise (`+09`,
      # `.5 +09:00`) and read the value as local time — a different instant
      # on every machine, with no warning.
      CONTENT_DATE_SHAPE = /\A(\d{4})-(\d{1,2})-(\d{1,2})(?:[Tt ](\d{1,2}):(\d{1,2}):(\d{1,2})(\.\d+)?\s*(?:([Zz])|([+-])(\d{2})(?::?(\d{2}))?)?)?\z/

      # The build's front-matter date parser (see `CONTENT_DATE_SHAPE`).
      # A written UTC offset is honoured; a date or time without one is read
      # in the machine's local zone. nil means "not a usable date" (the
      # caller warns): a shape mismatch, an impossible value (`2024-02-30`)
      # or an offset past ±23:59.
      def parse_content_date(time_str : String?) : Time?
        return unless time_str
        m = CONTENT_DATE_SHAPE.match(time_str.strip) || return
        day = "%04d-%02d-%02d" % {m[1].to_i, m[2].to_i, m[3].to_i}
        return Time.parse(day, "%Y-%m-%d", Time::Location.local) unless m[4]?

        clock = "#{day}T%02d:%02d:%02d" % {m[4].to_i, m[5].to_i, m[6].to_i}
        if m[8]?
          Time.parse_rfc3339("#{clock}#{m[7]?}Z")
        elsif sign = m[9]?
          minutes = (m[11]? || "00").to_i
          return if m[10].to_i > 23 || minutes > 59
          Time.parse_rfc3339("#{clock}#{m[7]?}#{sign}#{m[10]}:#{"%02d" % minutes}")
        else
          Time.parse(clock, "%Y-%m-%dT%H:%M:%S", Time::Location.local)
        end
      rescue Time::Format::Error | Time::Error | ArgumentError
        # Impossible value ("2024-13-45", "2024-02-30"): no usable date, so
        # the caller can treat it as absent.
        nil
      end
    end
  end
end
