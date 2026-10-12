# Sorting utility functions for page ordering
#
# Provides reusable sorting utilities for content pages:
# - compare_by_date: Compare pages by date (newest first)
# - compare_by_published: Compare pages by publish date only (newest first)
# - compare_by_title: Compare pages by title alphabetically
# - compare_by_weight: Compare pages by weight value
# - sort_pages: Generic page sorting with multiple criteria

require "../models/page"
require "./logger"

module Hwaro
  module Utils
    module SortUtils
      extend self

      # Stand-in date for an undated page where a timestamp must be printed
      # (feed <updated>); never used for ordering.
      FALLBACK_DATE = Time.utc(1970, 1, 1)

      # Compare two pages by date (newest first by default)
      #
      # Uses updated date if available, then date. An undated page sorts
      # after every dated one — including pre-1970 dates, which a 1970
      # stand-in date used to put below undated pages.
      # Returns negative if a should come first, positive if b should come first
      #
      def compare_by_date(a : Models::Page, b : Models::Page) : Int32
        compare_dates(a, a.updated || a.date, b, b.updated || b.date)
      end

      # Like compare_by_date, but on the publish `date` alone: a revised post
      # (`updated`) keeps its place in a chronological archive (gh#865).
      def compare_by_published(a : Models::Page, b : Models::Page) : Int32
        compare_dates(a, a.date, b, b.date)
      end

      private def compare_dates(a : Models::Page, a_date : Time?, b : Models::Page, b_date : Time?) : Int32
        # Default: newest first (descending); tiebreak by path for deterministic ordering
        result = if a_date && b_date
                   b_date <=> a_date
                 elsif a_date || b_date
                   a_date ? -1 : 1
                 else
                   0
                 end
        result == 0 ? (a.path <=> b.path) : result
      end

      # Compare two pages by title alphabetically (A-Z)
      #
      def compare_by_title(a : Models::Page, b : Models::Page) : Int32
        result = a.title <=> b.title
        result == 0 ? (a.path <=> b.path) : result
      end

      # Compare two taxonomy term names alphabetically, ignoring case
      # ("acp" < "SRI" < "Zola"); byte order breaks ties so "Go" and "go"
      # still order deterministically.
      def compare_term_names(a : String, b : String) : Int32
        result = a.compare(b, case_insensitive: true)
        result == 0 ? (a <=> b) : result
      end

      # Taxonomy term order (`terms_sort_by`): by name, or with `by_count` by
      # the block's page count descending with the name order as tiebreak.
      def sort_term_names(names : Array(String), by_count : Bool, & : String -> Int32) : Array(String)
        return names.sort { |a, b| compare_term_names(a, b) } unless by_count
        counts = names.to_h { |name| {name, yield name} }
        names.sort do |a, b|
          result = counts[b] <=> counts[a]
          result == 0 ? compare_term_names(a, b) : result
        end
      end

      # Compare two pages by weight value (lower weight first)
      #
      def compare_by_weight(a : Models::Page, b : Models::Page) : Int32
        # Tiebreak by path so equal weights (e.g. the archetype's default
        # weight = 0) keep a stable, deterministic order across builds.
        result = a.weight <=> b.weight
        result == 0 ? (a.path <=> b.path) : result
      end

      # Generic page sorting with specified criteria
      #
      # Supported sort_by values: "date", "published", "title", "weight"
      #
      def sort_pages(
        pages : Array(Models::Page),
        sort_by : String = "date",
        reverse : Bool = false,
      ) : Array(Models::Page)
        comparator = case sort_by.downcase
                     when "title"     then ->compare_by_title(Models::Page, Models::Page)
                     when "weight"    then ->compare_by_weight(Models::Page, Models::Page)
                     when "date"      then ->compare_by_date(Models::Page, Models::Page)
                     when "published" then ->compare_by_published(Models::Page, Models::Page)
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
