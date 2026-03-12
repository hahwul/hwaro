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
      # Supports Unicode characters (CJK, Hangul, etc.) in addition to ASCII.
      #
      # Examples:
      #   slugify("Hello World!")  # => "hello-world"
      #   slugify("My Blog Post")  # => "my-blog-post"
      #   slugify("한글 제목")      # => "한글-제목"
      #   slugify("CJK 테스트!")   # => "cjk-테스트"
      #
      def slugify(text : String) : String
        result = String.build do |io|
          text.each_char do |char|
            if char.ascii_letter? || char.ascii_number?
              io << char.downcase
            elsif char.ascii_whitespace? || char == '-' || char == '_'
              io << ' '
            elsif cjk_char?(char) || unicode_letter?(char)
              io << char
            end
            # All other characters (punctuation, symbols) are dropped
          end
        end
        result.gsub(/\s+/, "-").strip("-")
      end

      # Check if a character is a Unicode letter (non-ASCII)
      private def unicode_letter?(char : Char) : Bool
        !char.ascii? && char.letter?
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
        String.build(text.bytesize) do |io|
          text.each_char do |char|
            case char
            when '&'  then io << "&amp;"
            when '<'  then io << "&lt;"
            when '>'  then io << "&gt;"
            when '"'  then io << "&quot;"
            when '\'' then io << "&apos;"
            else           io << char
            end
          end
        end
      end

      # Strip HTML tags from text (single-pass)
      #
      # Example:
      #   strip_html("<p>Hello <b>World</b></p>")  # => "Hello World"
      #
      def strip_html(text : String) : String
        String.build(text.bytesize) do |io|
          in_tag = false
          last_was_space = true # suppress leading space
          text.each_char do |char|
            if char == '<'
              in_tag = true
            elsif char == '>'
              in_tag = false
              # Emit a single space in place of the tag
              unless last_was_space
                io << ' '
                last_was_space = true
              end
            elsif !in_tag
              if char.ascii_whitespace?
                unless last_was_space
                  io << ' '
                  last_was_space = true
                end
              else
                io << char
                last_was_space = false
              end
            end
          end
        end.strip
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
