# Content Stats Service
#
# Computes statistics about content files: total/draft/published counts,
# word count metrics, tag distribution, and monthly publishing frequency.

require "json"
require "yaml"
require "toml"
require "./content_lister"
require "../utils/errors"
require "../utils/frontmatter_scanner"
require "../utils/logger"

module Hwaro
  module Services
    struct StatsResult
      include JSON::Serializable

      property total : Int32
      property drafts : Int32
      property published : Int32
      # Files a default build drops for reasons other than `draft`. They used
      # to be counted as published, so the report disagreed with the site.
      property future : Int32
      property expired : Int32
      # Int64: summing per-file Int32 counts overflowed Int32 on giant
      # corpora (an Int32 total caps out around 2 billion words).
      property words_total : Int64
      property words_avg : Int32
      property words_min : Int32
      property words_max : Int32
      property tags : Hash(String, Int32)
      property monthly : Hash(String, Int32)

      def initialize(
        @total : Int32 = 0,
        @drafts : Int32 = 0,
        @published : Int32 = 0,
        @future : Int32 = 0,
        @expired : Int32 = 0,
        @words_total : Int64 = 0_i64,
        @words_avg : Int32 = 0,
        @words_min : Int32 = 0,
        @words_max : Int32 = 0,
        @tags : Hash(String, Int32) = {} of String => Int32,
        @monthly : Hash(String, Int32) = {} of String => Int32,
      )
      end
    end

    class ContentStats
      TOML_FRONTMATTER_RE = Utils::FrontmatterScanner::TOML_FRONTMATTER_RE
      YAML_FRONTMATTER_RE = Utils::FrontmatterScanner::YAML_FRONTMATTER_RE

      @content_dir : String

      def initialize(@content_dir : String = "content")
      end

      def run : StatsResult
        # A missing content directory is a failure, not an empty report: the
        # command used to print "not found" on stderr, a zeroed report on
        # stdout and still exit 0, so a script could not tell "no content"
        # from "wrong directory". Matches `tool list` / `tool validate`.
        unless Dir.exists?(@content_dir)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONTENT,
            message: "Content directory '#{@content_dir}' does not exist",
            hint: "Create it or pass --content-dir DIR to point at your content root.",
          )
        end

        lister = ContentLister.new(@content_dir)
        items = lister.list_all

        return StatsResult.new if items.empty?

        drafts = items.count { |i| i.status == "draft" }
        future = items.count { |i| i.status == "future" }
        expired = items.count { |i| i.status == "expired" }
        published = items.count(&.published?)

        # Word counts, tag distribution, and publishing frequency reflect
        # what `hwaro build` actually ships, so anything the build drops is
        # excluded from the metrics — `total` / `drafts` / `future` /
        # `expired` / `published` above already describe the on-disk content
        # set (gh#528 C).
        published_items = items.select(&.published?)

        word_counts = [] of Int32
        tags = {} of String => Int32
        monthly = {} of String => Int32

        published_items.each do |item|
          content = begin
            File.read(item.path)
          rescue IO::Error
            next
          end

          # PCRE2 raises ArgumentError on invalid UTF-8 — the same escape
          # extract_tags guards against; one bad file must not kill the
          # whole report.
          body = begin
            extract_body(content)
          rescue ArgumentError
            next
          end
          wc = count_words(body)
          word_counts << wc

          # Extract tags
          extract_tags(content, item.path).each do |tag|
            tags[tag] = (tags[tag]? || 0) + 1
          end

          # Monthly frequency
          if date = item.date
            key = date.to_s("%Y-%m")
            monthly[key] = (monthly[key]? || 0) + 1
          end
        end

        # Sum in Int64: a giant corpus overflows Int32 (Crystal raises
        # OverflowError, killing the report).
        words_total = word_counts.sum(0_i64)
        # Divide by the number of files actually read (word_counts), not the
        # published count — a file unreadable between listing and read is skipped
        # from word_counts but would otherwise dilute the average. Matches the
        # population used by words_min/words_max below. The average of Int32
        # per-file counts always fits Int32, so `.to_i` cannot overflow.
        words_avg = word_counts.empty? ? 0 : (words_total // word_counts.size).to_i
        words_min = word_counts.min? || 0
        words_max = word_counts.max? || 0

        # Sort tags by count descending
        sorted_tags = tags.to_a.sort_by { |_, count| -count }.to_h

        # Sort monthly by key
        sorted_monthly = monthly.to_a.sort_by(&.first).to_h

        StatsResult.new(
          total: items.size,
          drafts: drafts,
          published: published,
          future: future,
          expired: expired,
          words_total: words_total,
          words_avg: words_avg,
          words_min: words_min,
          words_max: words_max,
          tags: sorted_tags,
          monthly: sorted_monthly,
        )
      end

      private def extract_body(content : String) : String
        Utils::FrontmatterScanner.strip_frontmatter(content)
      end

      private def count_words(body : String) : Int32
        # Exactly the code path the build uses for `page.word_count` /
        # `page.reading_time`: `Models::Page#calculate_word_count` calls
        # `TextUtils.count_words` on the frontmatter-stripped body, fenced
        # code blocks included. Stats used to strip fences first, so the
        # report drifted from the numbers the site itself renders — and the
        # build is the source of truth.
        Utils::TextUtils.count_words(body)
      end

      # Front matter that does not parse costs this file its tags, never the
      # whole report: `tool stats` is a read-only summary of a tree the author
      # is still editing, and one typo used to abort it.
      #
      # `ArgumentError` is rescued alongside the parse exceptions because both
      # front-matter parsers build values eagerly: an out-of-range but
      # syntactically valid date (`date = 2024-02-30`) raises Crystal's
      # `ArgumentError("Invalid time")` from `Time.new`, not a
      # `TOML::ParseException`, so the narrow rescue let it unwind the run.
      # The file is named on the way past so the omission is not silent —
      # `tool validate` reports the same file with the same message.
      # Tags exactly as the build resolves them: a top-level `tags` list, or —
      # when that is absent or empty — the `[taxonomies] tags` table, which is
      # how the scaffolds and every Zola-style site declare them. Reading only
      # the top-level key reported an EMPTY tag distribution for those sites
      # (`Processors::Markdown` applies the same fallback).
      private def extract_tags(content : String, path : String) : Array(String)
        if match = content.match(TOML_FRONTMATTER_RE)
          begin
            toml_data = TOML.parse(match[1])
            tags = toml_string_array(toml_data["tags"]?)
            return tags unless tags.empty?
            nested = toml_data["taxonomies"]?.try(&.as_h?).try(&.["tags"]?)
            return toml_string_array(nested)
          rescue ex : TOML::ParseException | ArgumentError
            warn_unparsed_frontmatter(path, "TOML", ex)
          end
        elsif match = content.match(YAML_FRONTMATTER_RE)
          begin
            yaml_data = YAML.parse(match[1])
            if h = yaml_data.as_h?
              tags = yaml_string_array(h[YAML::Any.new("tags")]?)
              return tags unless tags.empty?
              nested = h[YAML::Any.new("taxonomies")]?.try(&.as_h?).try(&.[YAML::Any.new("tags")]?)
              return yaml_string_array(nested)
            end
          rescue ex : YAML::ParseException | ArgumentError
            warn_unparsed_frontmatter(path, "YAML", ex)
          end
        elsif content.starts_with?('{') && (end_idx = Utils::FrontmatterScanner.find_json_end(content))
          # JSON front matter is a first-class dialect for the build, so a
          # JSON-authored post used to contribute nothing to the report.
          begin
            if h = JSON.parse(content.byte_slice(0, end_idx)).as_h?
              tags = json_string_array(h["tags"]?)
              return tags unless tags.empty?
              return json_string_array(h["taxonomies"]?.try(&.as_h?).try(&.["tags"]?))
            end
          rescue ex : JSON::ParseException
            warn_unparsed_frontmatter(path, "JSON", ex)
          end
        end

        [] of String
      end

      private def toml_string_array(value : TOML::Any?) : Array(String)
        raw = value.try(&.raw)
        return [] of String unless raw.is_a?(Array)
        raw.compact_map { |item| item.as(TOML::Any).raw.as?(String) }
      end

      private def yaml_string_array(value : YAML::Any?) : Array(String)
        value.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def json_string_array(value : JSON::Any?) : Array(String)
        value.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def warn_unparsed_frontmatter(path : String, dialect : String, ex : Exception) : Nil
        Logger.warn "#{path}: #{dialect} frontmatter parse error: #{ex.message}; tags not counted."
      end
    end
  end
end
