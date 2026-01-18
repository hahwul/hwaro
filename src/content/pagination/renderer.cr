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
              str << "    <li class=\"pagination-prev\"><a href=\"#{prev_full_url}\" rel=\"prev\">Previous</a></li>\n"
            else
              str << "    <li class=\"pagination-prev pagination-disabled\"><span>Previous</span></li>\n"
            end

            # Page numbers
            (1..paginated_page.total_pages).each do |page_num|
              page_url = if page_num == 1
                          HTML.escape("#{@base_url}#{paginated_page.first_url}")
                        else
                          base = paginated_page.first_url.rstrip("/")
                          HTML.escape("#{@base_url}#{base}/page/#{page_num}/")
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
