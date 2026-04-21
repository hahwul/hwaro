# Content Stats Service
#
# Computes statistics about content files: total/draft/published counts,
# word count metrics, tag distribution, and monthly publishing frequency.

require "json"
require "yaml"
require "toml"
require "./content_lister"
require "../utils/logger"

module Hwaro
  module Services
    struct StatsResult
      include JSON::Serializable

      property total : Int32
      property drafts : Int32
      property published : Int32
      property words_total : Int32
      property words_avg : Int32
      property words_min : Int32
      property words_max : Int32
      property tags : Hash(String, Int32)
      property monthly : Hash(String, Int32)

      def initialize(
        @total : Int32 = 0,
        @drafts : Int32 = 0,
        @published : Int32 = 0,
        @words_total : Int32 = 0,
        @words_avg : Int32 = 0,
        @words_min : Int32 = 0,
        @words_max : Int32 = 0,
        @tags : Hash(String, Int32) = {} of String => Int32,
        @monthly : Hash(String, Int32) = {} of String => Int32,
      )
      end
    end

    class ContentStats
      TOML_FRONTMATTER_RE = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m
      YAML_FRONTMATTER_RE = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

      @content_dir : String

      def initialize(@content_dir : String = "content")
      end

      def run : StatsResult
        lister = ContentLister.new(@content_dir)
        items = lister.list_all

        return StatsResult.new if items.empty?

        drafts = items.count(&.draft)
        published = items.size - drafts

        # Compute word counts and tags by reading each file
        word_counts = [] of Int32
        tags = {} of String => Int32
        monthly = {} of String => Int32

        items.each do |item|
          content = File.read(item.path) rescue next

          body = extract_body(content)
          wc = count_words(body)
          word_counts << wc

          # Extract tags
          extract_tags(content).each do |tag|
            tags[tag] = (tags[tag]? || 0) + 1
          end

          # Monthly frequency
          if date = item.date
            key = date.to_s("%Y-%m")
            monthly[key] = (monthly[key]? || 0) + 1
          end
        end

        words_total = word_counts.sum
        words_avg = items.empty? ? 0 : words_total // items.size
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
          words_total: words_total,
          words_avg: words_avg,
          words_min: words_min,
          words_max: words_max,
          tags: sorted_tags,
          monthly: sorted_monthly,
        )
      end

      private def extract_body(content : String) : String
        content.sub(TOML_FRONTMATTER_RE, "").sub(YAML_FRONTMATTER_RE, "")
      end

      private def count_words(body : String) : Int32
        # Strip code blocks, then count whitespace-separated tokens
        stripped = body.gsub(/(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$/, "")
        stripped.split(/\s+/).count { |w| !w.empty? }
      end

      private def extract_tags(content : String) : Array(String)
        if match = content.match(TOML_FRONTMATTER_RE)
          begin
            toml_data = TOML.parse(match[1])
            if tags_val = toml_data["tags"]?
              raw = tags_val.raw
              if raw.is_a?(Array)
                return raw.compact_map { |item| item.as(TOML::Any).raw.as?(String) }
              end
            end
          rescue
          end
        elsif match = content.match(YAML_FRONTMATTER_RE)
          begin
            yaml_data = YAML.parse(match[1])
            if h = yaml_data.as_h?
              if tags_node = h[YAML::Any.new("tags")]?
                if arr = tags_node.as_a?
                  return arr.compact_map(&.as_s?)
                end
              end
            end
          rescue
          end
        end

        [] of String
      end
    end
  end
end
