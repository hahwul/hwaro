# Shared date parsing for content dates.
#
# Two parsers live here on purpose — they accept different inputs and must
# not be merged:
#
# - `parse_lenient` is the RFC-3339-first, format-table parser used by
#   importers and content listings, which read dates written by OTHER tools.
# - `parse_content_date` mirrors the build's front-matter parser
#   (`Processors::Markdown#parse_time` delegates here), which defines what
#   a hwaro site itself accepts.

module Hwaro
  module Utils
    module DateUtils
      extend self

      # Formats accepted by content listings. Zone-bearing formats come
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

      # Importers additionally accept prose and RFC 822 dates.
      IMPORT_FORMATS = CONTENT_FORMATS + [
        "%B %d, %Y",
        # RFC 822 (WordPress <pubDate>, RSS feeds)
        "%a, %d %b %Y %H:%M:%S %z",
      ]

      # Parse a date string in common formats, returns nil on failure.
      # RFC 3339 is probed first, then the format table in UTC.
      def parse_lenient(date_str : String, formats : Array(String) = CONTENT_FORMATS) : Time?
        str = date_str.strip

        begin
          return Time.parse_rfc3339(str)
        rescue Time::Format::Error
          # Not RFC 3339; fall through to the lenient formats.
        end

        formats.each do |fmt|
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

        fmt = if str.includes?('T')
                # Could be RFC 3339 (with timezone) or plain ISO
                if str.includes?('+') || str.includes?('Z') || str.matches?(/T.+-\d{2}:\d{2}$/) || str.matches?(/\d{2}-\d{2}$/)
                  begin
                    return Time.parse_rfc3339(str)
                  rescue Time::Format::Error | ArgumentError
                    "%Y-%m-%dT%H:%M:%S"
                  end
                else
                  "%Y-%m-%dT%H:%M:%S"
                end
              elsif str.size > 10
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
