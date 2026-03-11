# Renderer - Generates HTML for pagination navigation
#
# Provides functionality to generate:
# - Section list HTML with paginated pages
# - Pagination navigation HTML (prev/next, page numbers)

require "html"
require "./paginator"
require "../../models/config"

module Hwaro
  module Content
    module Pagination
      class Renderer
        @config : Models::Config
        @base_url : String

        def initialize(@config : Models::Config)
          @base_url = @config.base_url
        end

        # Render section list HTML for a paginated page
        def render_section_list(paginated_page : PaginatedPage) : String
          String.build do |str|
            paginated_page.pages.each do |page|
              escaped_url = HTML.escape("#{@base_url}#{page.url}")
              escaped_title = HTML.escape(page.title)
              str << "<li><a href=\"#{escaped_url}\">#{escaped_title}</a></li>\n"
            end
          end
        end

        # Render pagination navigation HTML
        def render_pagination_nav(paginated_page : PaginatedPage) : String
          return "" unless paginated_page.total_pages > 1

          String.build do |str|
            str << "<nav class=\"pagination\" aria-label=\"Pagination\">\n"
            str << "  <ul class=\"pagination-list\">\n"

            # Previous button
            if paginated_page.has_prev
              prev_full_url = HTML.escape("#{@base_url}#{paginated_page.prev_url}")
              str << "    <li class=\"pagination-prev\"><a href=\"#{prev_full_url}\" rel=\"prev\">Prev</a></li>\n"
            else
              str << "    <li class=\"pagination-prev pagination-disabled\"><span>Prev</span></li>\n"
            end

            # Page numbers with ellipsis for large page counts
            pages = visible_pages(paginated_page.page_number, paginated_page.total_pages)
            prev_page = 0
            pages.each do |page_num|
              # Insert ellipsis if there's a gap
              if page_num > prev_page + 1
                str << "    <li class=\"pagination-ellipsis\"><span>\u2026</span></li>\n"
              end
              prev_page = page_num

              page_url = if page_num == 1
                           HTML.escape("#{@base_url}#{paginated_page.first_url}")
                         else
                           HTML.escape("#{@base_url}#{paginated_page.base_url}#{page_num}/")
                         end

              if page_num == paginated_page.page_number
                str << "    <li class=\"pagination-page pagination-current\"><span>#{page_num}</span></li>\n"
              else
                str << "    <li class=\"pagination-page\"><a href=\"#{page_url}\">#{page_num}</a></li>\n"
              end
            end

            # Next button
            if paginated_page.has_next
              next_full_url = HTML.escape("#{@base_url}#{paginated_page.next_url}")
              str << "    <li class=\"pagination-next\"><a href=\"#{next_full_url}\" rel=\"next\">Next</a></li>\n"
            else
              str << "    <li class=\"pagination-next pagination-disabled\"><span>Next</span></li>\n"
            end

            str << "  </ul>\n"
            str << "</nav>\n"
          end
        end

        # Render SEO <link rel="prev/next"> tags for <head>
        def render_seo_links(paginated_page : PaginatedPage) : String
          return "" unless paginated_page.total_pages > 1

          String.build do |str|
            if paginated_page.has_prev
              prev_full_url = HTML.escape("#{@base_url}#{paginated_page.prev_url}")
              str << "<link rel=\"prev\" href=\"#{prev_full_url}\">\n"
            end
            if paginated_page.has_next
              next_full_url = HTML.escape("#{@base_url}#{paginated_page.next_url}")
              str << "<link rel=\"next\" href=\"#{next_full_url}\">\n"
            end
          end
        end

        private def visible_pages(current : Int32, total : Int32) : Array(Int32)
          return (1..total).to_a if total <= 7

          pages = Set(Int32).new
          pages << 1
          pages << total
          ((current - 2)..(current + 2)).each do |p|
            pages << p if p >= 1 && p <= total
          end
          pages.to_a.sort
        end

        # Render combined section list with pagination info
        def render_paginated_section(paginated_page : PaginatedPage) : String
          section_list = render_section_list(paginated_page)
          pagination_nav = render_pagination_nav(paginated_page)

          "#{section_list}#{pagination_nav}"
        end
      end
    end
  end
end
