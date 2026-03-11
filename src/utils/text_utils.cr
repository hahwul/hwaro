# Text utility functions for common string operations
#
# Provides reusable text processing utilities:
# - slugify: Convert text to URL-friendly slugs
# - escape_xml: Escape XML special characters

module Hwaro
  module Utils
    module TextUtils
      extend self

      # Convert text to a URL-friendly slug
      #
      # Examples:
      #   slugify("Hello World!")  # => "hello-world"
      #   slugify("My Blog Post")  # => "my-blog-post"
      #   slugify("한글 제목")      # => "" (non-ASCII removed)
      #
      def slugify(text : String) : String
        text.downcase
          .gsub(/[^a-z0-9\s-]/, "") # Remove non-alphanumeric chars except space and hyphen
          .gsub(/\s+/, "-")         # Replace spaces with hyphens
          .strip("-")               # Trim leading/trailing hyphens
      end

      # Escape XML special characters
      #
      # Escapes: & < > " '
      #
      # Example:
      #   escape_xml("Tom & Jerry")  # => "Tom &amp; Jerry"
      #   escape_xml("<script>")     # => "&lt;script&gt;"
      #
      def escape_xml(text : String) : String
        text.gsub(/[&<>"']/) do |match|
          case match
          when "&"  then "&amp;"
          when "<"  then "&lt;"
          when ">"  then "&gt;"
          when "\"" then "&quot;"
          when "'"  then "&apos;"
          else           match
          end
        end
      end

      # Strip HTML tags from text
      #
      # Example:
      #   strip_html("<p>Hello <b>World</b></p>")  # => "Hello World"
      #
      def strip_html(text : String) : String
        text.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end

      # Check if a character is in a CJK Unicode range
      def cjk_char?(char : Char) : Bool
        code = char.ord
        (code >= 0x4E00 && code <= 0x9FFF) ||   # CJK Unified Ideographs
          (code >= 0x3040 && code <= 0x309F) || # Hiragana
          (code >= 0x30A0 && code <= 0x30FF) || # Katakana
          (code >= 0xAC00 && code <= 0xD7AF) || # Hangul Syllables
          (code >= 0x1100 && code <= 0x11FF) || # Hangul Jamo
          (code >= 0x3400 && code <= 0x4DBF) || # CJK Extension A
          (code >= 0x3300 && code <= 0x33FF) || # CJK Compatibility
          (code >= 0xFE30 && code <= 0xFE4F)    # CJK Compatibility Forms
      end

      # Tokenize CJK text into overlapping bigrams for search indexing
      #
      # CJK languages (Chinese, Japanese, Korean) often lack spaces between words.
      # This splits CJK character runs into overlapping 2-character pairs (bigrams)
      # so search libraries can match substrings.
      #
      # Example:
      #   tokenize_cjk("검색엔진")  # => "검색 색엔 엔진"
      #   tokenize_cjk("hello世界测试")  # => "hello世界 界测 测试"
      #
      def tokenize_cjk(text : String) : String
        builder = String::Builder.new(text.bytesize * 2)
        cjk_run = [] of Char

        text.each_char do |char|
          if cjk_char?(char)
            cjk_run << char
          else
            unless cjk_run.empty?
              flush_cjk_run(builder, cjk_run)
              cjk_run.clear
            end
            builder << char
          end
        end

        unless cjk_run.empty?
          flush_cjk_run(builder, cjk_run)
        end

        builder.to_s
      end

      private def flush_cjk_run(builder : String::Builder, run : Array(Char)) : Nil
        if run.size == 1
          builder << run[0]
          return
        end

        (run.size - 1).times do |i|
          builder << ' ' if i > 0
          builder << run[i]
          builder << run[i + 1]
        end
      end
    end
  end
end
