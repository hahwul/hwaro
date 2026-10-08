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
        rescue Time::Format::Error | ArgumentError
          # Time::Format::Error → not RFC 3339 at all. ArgumentError → the
          # shape is RFC 3339 but the value is impossible ("2024-02-30").
          # Either way, fall through to the lenient formats.
        end

        formats.each do |fmt|
          return Time.parse(str, fmt, Time::Location::UTC)
        rescue Time::Format::Error | ArgumentError
          next
        end

        nil
      end

      # The zone-bearing forms of CONTENT_FORMATS (the first four), for a
      # string whose offset is written without RFC 3339's colon or after a
      # space. nil when none matches, so zone-less input is never claimed.
      private def parse_written_offset(str : String) : Time?
        CONTENT_FORMATS.first(4).each do |fmt|
          return Time.parse(str, fmt, Time::Location::UTC)
        rescue Time::Format::Error | ArgumentError
          next
        end
        nil
      end

      # The build's front-matter date parser. Format selection is based on
      # the string's shape to avoid exception-based control flow; zone-less
      # values are interpreted in the machine's local zone.
      def parse_content_date(time_str : String?) : Time?
        return unless time_str
        str = time_str.strip
        return if str.empty?

        # A written UTC offset is honoured, never dropped: `Time.parse` ignores
        # trailing input, so the zone-less formats below would read
        # `2024-01-15 10:00:00 +0900` / `…T10:00:00+0900` (no colon, which RFC
        # 3339 rejects) as local time — a different instant on every machine.
        # Zone-bearing formats go first, as in CONTENT_FORMATS.
        fmt = if str.includes?('T')
                # Could be RFC 3339 (with timezone) or plain ISO
                if str.includes?('+') || str.includes?('Z') || str.matches?(/T.+-\d{2}:\d{2}$/) || str.matches?(/\d{2}-\d{2}$/)
                  begin
                    return Time.parse_rfc3339(str)
                  rescue Time::Format::Error | ArgumentError
                    zoned = parse_written_offset(str)
                    return zoned if zoned
                    "%Y-%m-%dT%H:%M:%S"
                  end
                else
                  "%Y-%m-%dT%H:%M:%S"
                end
              elsif str.size > 10
                zoned = parse_written_offset(str)
                return zoned if zoned
                "%Y-%m-%d %H:%M:%S"
              else
                "%Y-%m-%d"
              end

        begin
          Time.parse(str, fmt, Time::Location.local)
        rescue Time::Format::Error | ArgumentError
          # Time::Format::Error  → string doesn't match the format at all.
          # ArgumentError        → format matches but the value is out of
          #   range (e.g. "2024-13-45", "2024-02-30"). Both mean "no usable
          #   date" — return nil so the caller can treat it as absent.
          nil
        end
      end
    end
  end
end
