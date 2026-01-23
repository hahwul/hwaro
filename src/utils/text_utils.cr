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
    end
  end
end
