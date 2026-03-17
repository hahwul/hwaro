# Sorting utility functions for page ordering
#
# Provides reusable sorting utilities for content pages:
# - compare_by_date: Compare pages by date (newest first)
# - compare_by_title: Compare pages by title alphabetically
# - compare_by_weight: Compare pages by weight value
# - sort_pages: Generic page sorting with multiple criteria

require "../models/page"
require "./logger"

module Hwaro
  module Utils
    module SortUtils
      extend self

      # Default fallback date used when a page has no date set
      FALLBACK_DATE = Time.utc(1970, 1, 1)

      # Compare two pages by date (newest first by default)
      #
      # Uses updated date if available, falls back to date, then FALLBACK_DATE
      # Returns negative if a should come first, positive if b should come first
      #
      def compare_by_date(a : Models::Page, b : Models::Page) : Int32
        a_date = a.updated || a.date || FALLBACK_DATE
        b_date = b.updated || b.date || FALLBACK_DATE
        # Default: newest first (descending); tiebreak by path for deterministic ordering
        result = b_date <=> a_date
        result == 0 ? (a.path <=> b.path) : result
      end

      # Compare two pages by title alphabetically (A-Z)
      #
      def compare_by_title(a : Models::Page, b : Models::Page) : Int32
        a.title <=> b.title
      end

      # Compare two pages by weight value (lower weight first)
      #
      def compare_by_weight(a : Models::Page, b : Models::Page) : Int32
        a.weight <=> b.weight
      end

      # Sort pages by date (newest first)
      def sort_by_date(pages : Array(Models::Page), reverse : Bool = false) : Array(Models::Page)
        sort_pages(pages, "date", reverse)
      end

      # Sort pages by title alphabetically
      def sort_by_title(pages : Array(Models::Page), reverse : Bool = false) : Array(Models::Page)
        sort_pages(pages, "title", reverse)
      end

      # Sort pages by weight
      def sort_by_weight(pages : Array(Models::Page), reverse : Bool = false) : Array(Models::Page)
        sort_pages(pages, "weight", reverse)
      end

      # Generic page sorting with specified criteria
      #
      # Supported sort_by values: "date", "title", "weight"
      #
      def sort_pages(
        pages : Array(Models::Page),
        sort_by : String = "date",
        reverse : Bool = false,
      ) : Array(Models::Page)
        comparator = case sort_by.downcase
                     when "title"  then ->compare_by_title(Models::Page, Models::Page)
                     when "weight" then ->compare_by_weight(Models::Page, Models::Page)
                     when "date"   then ->compare_by_date(Models::Page, Models::Page)
                     else
                       Logger.warn "Unknown sort_by '#{sort_by}', defaulting to 'date'"
                       ->compare_by_date(Models::Page, Models::Page)
                     end

        # Single sort — swap arguments for reverse instead of sort + reverse (avoids extra allocation)
        if reverse
          pages.sort { |a, b| comparator.call(b, a) }
        else
          pages.sort { |a, b| comparator.call(a, b) }
        end
      end
    end
  end
end
