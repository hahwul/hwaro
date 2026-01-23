# Paginator - Handles pagination logic for section pages
#
# Provides functionality to:
# - Paginate arrays of pages into groups based on per_page setting
# - Calculate page numbers and navigation links
# - Generate paginated page data for section rendering

require "../../models/page"
require "../../models/section"
require "../../models/config"
require "../../utils/sort_utils"

module Hwaro
  module Content
    module Pagination
      # Represents a single page in a paginated result set
      struct PaginatedPage
        property pages : Array(Models::Page)
        property page_number : Int32
        property total_pages : Int32
        property per_page : Int32
        property total_items : Int32
        property has_prev : Bool
        property has_next : Bool
        property prev_url : String?
        property next_url : String?
        property first_url : String
        property last_url : String

        def initialize(
          @pages : Array(Models::Page),
          @page_number : Int32,
          @total_pages : Int32,
          @per_page : Int32,
          @total_items : Int32,
          @has_prev : Bool,
          @has_next : Bool,
          @prev_url : String?,
          @next_url : String?,
          @first_url : String,
          @last_url : String,
        )
        end
      end

      # Result of pagination containing all paginated pages
      struct PaginationResult
        property paginated_pages : Array(PaginatedPage)
        property enabled : Bool
        property per_page : Int32

        def initialize(
          @paginated_pages : Array(PaginatedPage),
          @enabled : Bool,
          @per_page : Int32,
        )
        end
      end

      class Paginator
        @config : Models::Config

        def initialize(@config : Models::Config)
        end

        # Paginate pages for a section
        # Returns PaginationResult with all paginated pages
        def paginate(section : Models::Section, pages : Array(Models::Page)) : PaginationResult
          enabled = pagination_enabled_for_section?(section)
          per_page = per_page_for_section(section)

          unless enabled
            # Return single page with all items when pagination is disabled
            single_page = PaginatedPage.new(
              pages: pages,
              page_number: 1,
              total_pages: 1,
              per_page: pages.size,
              total_items: pages.size,
              has_prev: false,
              has_next: false,
              prev_url: nil,
              next_url: nil,
              first_url: section.url,
              last_url: section.url
            )
            return PaginationResult.new(
              paginated_pages: [single_page],
              enabled: false,
              per_page: pages.size
            )
          end

          # Sort pages before paginating (by date desc, then title asc)
          sorted_pages = sort_section_pages(pages, section)

          # Calculate pagination
          total_items = sorted_pages.size
          total_pages = [(total_items.to_f / per_page).ceil.to_i, 1].max
          base_url = section.url.rstrip("/")

          paginated_pages = [] of PaginatedPage

          (1..total_pages).each do |page_num|
            start_idx = (page_num - 1) * per_page
            end_idx = [start_idx + per_page, total_items].min
            page_items = sorted_pages[start_idx...end_idx]

            has_prev = page_num > 1
            has_next = page_num < total_pages

            # Generate URLs
            current_url = page_url(base_url, page_num)
            prev_url = has_prev ? page_url(base_url, page_num - 1) : nil
            next_url = has_next ? page_url(base_url, page_num + 1) : nil
            first_url = page_url(base_url, 1)
            last_url = page_url(base_url, total_pages)

            paginated_pages << PaginatedPage.new(
              pages: page_items,
              page_number: page_num,
              total_pages: total_pages,
              per_page: per_page,
              total_items: total_items,
              has_prev: has_prev,
              has_next: has_next,
              prev_url: prev_url,
              next_url: next_url,
              first_url: first_url,
              last_url: last_url
            )
          end

          PaginationResult.new(
            paginated_pages: paginated_pages,
            enabled: true,
            per_page: per_page
          )
        end

        # Check if pagination is enabled for a section
        private def pagination_enabled_for_section?(section : Models::Section) : Bool
          # Section-level override takes precedence
          if section_enabled = section.pagination_enabled
            return section_enabled
          end
          # Fall back to global config
          @config.pagination.enabled
        end

        # Get per_page setting for a section
        private def per_page_for_section(section : Models::Section) : Int32
          # Section-level override takes precedence
          if section_per_page = section.paginate
            return section_per_page
          end
          # Fall back to global config
          @config.pagination.per_page
        end

        # Sort pages according to section settings
        private def sort_section_pages(pages : Array(Models::Page), section : Models::Section) : Array(Models::Page)
          sort_by = section.sort_by || "date"
          reverse = section.reverse || false
          Utils::SortUtils.sort_pages(pages, sort_by, reverse)
        end

        # Generate URL for a specific page number
        private def page_url(base_url : String, page_number : Int32) : String
          if page_number == 1
            "#{base_url}/"
          else
            "#{base_url}/page/#{page_number}/"
          end
        end
      end
    end
  end
end
