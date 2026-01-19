# Taxonomy generation for Hwaro
#
# Builds taxonomy index and term pages based on configured taxonomies.

require "file_utils"
require "html"
require "path"
require "../models/site"
require "../models/page"
require "../models/section"
require "../models/config"
require "../utils/logger"
require "../content/pagination/renderer"

module Hwaro
  module Content
    class Taxonomies
      def self.generate(site : Models::Site, output_dir : String, templates : Hash(String, String))
        config = site.config
        return if config.taxonomies.empty?

        build_taxonomy_index(site)

        config.taxonomies.each do |taxonomy|
          next if taxonomy.name.strip.empty?

          terms = site.taxonomies[taxonomy.name]?
          next unless terms

          base_path = "/#{taxonomy.name}/"
          index_page = build_taxonomy_index_page(taxonomy, base_path)

          render_taxonomy_index(index_page, terms.keys.sort, templates, site, output_dir)

          terms.each do |term, pages|
            render_taxonomy_term(taxonomy, term, pages, templates, site, output_dir)
          end
        end
      end

      private def self.build_taxonomy_index(site : Models::Site)
        site.taxonomies.clear
        config = site.config

        site.pages.each do |page|
          next if page.draft
          next if page.generated

          config.taxonomies.each do |taxonomy|
            name = taxonomy.name
            next if name.strip.empty?

            values = extract_terms_for(page, taxonomy)
            next if values.empty?

            values.each do |term|
              next if term.strip.empty?

              terms = site.taxonomies[name]? || begin
                site.taxonomies[name] = {} of String => Array(Models::Page)
                site.taxonomies[name]
              end

              list = terms[term]? || begin
                terms[term] = [] of Models::Page
                terms[term]
              end

              list << page
            end
          end
        end

        site.taxonomies.each_value do |terms|
          terms.each_value do |pages|
            pages.sort! do |a, b|
              date_a = a.updated || a.date
              date_b = b.updated || b.date

              if date_a && date_b
                date_b.not_nil! <=> date_a.not_nil!
              elsif date_a
                -1
              elsif date_b
                1
              else
                a.title <=> b.title
              end
            end
          end
        end
      end

      private def self.render_taxonomy_index(
        page : Models::Section,
        terms : Array(String),
        templates : Hash(String, String),
        site : Models::Site,
        output_dir : String,
      )
        template_content = templates["taxonomy"]? || templates["page"]?
        html_content = build_term_list(terms, page.url, site.config.base_url)

        final_html = apply_template(template_content, html_content, page, site, templates)
        write_output(page, output_dir, final_html)
      end

      private def self.render_taxonomy_term(
        taxonomy : Models::TaxonomyConfig,
        term : String,
        pages : Array(Models::Page),
        templates : Hash(String, String),
        site : Models::Site,
        output_dir : String,
      )
        slug = slugify(term)
        base_url = "/#{taxonomy.name}/#{slug}/"

        index_page = Models::Section.new("taxonomies/#{taxonomy.name}/#{slug}/index.md")
        index_page.title = "#{taxonomy.name.capitalize}: #{term}"
        index_page.section = taxonomy.name
        index_page.url = base_url
        index_page.is_index = true
        index_page.render = true
        index_page.generated = true
        index_page.in_sitemap = taxonomy.sitemap
        index_page.taxonomies = {taxonomy.name => [term]}
        index_page.taxonomy_name = taxonomy.name
        index_page.taxonomy_term = term
        index_page.pagination_enabled = false

        paginated_pages = paginate_taxonomy(taxonomy, pages, index_page)

        template_content = templates["taxonomy_term"]? || templates["taxonomy"]? || templates["page"]?

        paginated_pages.each do |paginated_page|
          list_html = build_page_list(paginated_page.pages, site.config.base_url)
          pagination_html = Content::Pagination::Renderer.new(site.config).render_pagination_nav(paginated_page)
          html_content = list_html + pagination_html

          final_html = apply_template(template_content, html_content, index_page, site, templates)

          if paginated_page.page_number == 1
            write_output(index_page, output_dir, final_html)
          else
            write_paginated_output(index_page, paginated_page.page_number, output_dir, final_html)
          end
        end

        return unless taxonomy.feed

        generate_taxonomy_feed(taxonomy, term, pages, site, output_dir, base_url)
      end

      private def self.paginate_taxonomy(
        taxonomy : Models::TaxonomyConfig,
        pages : Array(Models::Page),
        index_page : Models::Section,
      ) : Array(Content::Pagination::PaginatedPage)
        per_page = taxonomy.paginate_by || pages.size
        return [Content::Pagination::PaginatedPage.new(
          pages: pages,
          page_number: 1,
          total_pages: 1,
          per_page: pages.size,
          total_items: pages.size,
          has_prev: false,
          has_next: false,
          prev_url: nil,
          next_url: nil,
          first_url: index_page.url,
          last_url: index_page.url,
        )] if per_page <= 0 || pages.size <= per_page

        total_items = pages.size
        total_pages = [(total_items.to_f / per_page).ceil.to_i, 1].max
        paginated_pages = [] of Content::Pagination::PaginatedPage

        (1..total_pages).each do |page_number|
          start_idx = (page_number - 1) * per_page
          end_idx = [start_idx + per_page, total_items].min
          page_items = pages[start_idx...end_idx]

          has_prev = page_number > 1
          has_next = page_number < total_pages
          prev_url = has_prev ? page_url(index_page.url, page_number - 1) : nil
          next_url = has_next ? page_url(index_page.url, page_number + 1) : nil
          first_url = page_url(index_page.url, 1)
          last_url = page_url(index_page.url, total_pages)

          paginated_pages << Content::Pagination::PaginatedPage.new(
            pages: page_items,
            page_number: page_number,
            total_pages: total_pages,
            per_page: per_page,
            total_items: total_items,
            has_prev: has_prev,
            has_next: has_next,
            prev_url: prev_url,
            next_url: next_url,
            first_url: first_url,
            last_url: last_url,
          )
        end

        paginated_pages
      end

      private def self.build_taxonomy_index_page(taxonomy : Models::TaxonomyConfig, base_path : String) : Models::Section
        page = Models::Section.new("taxonomies/#{taxonomy.name}/index.md")
        page.title = taxonomy.name.capitalize
        page.section = taxonomy.name
        page.url = base_path
        page.is_index = true
        page.render = true
        page.generated = true
        page.in_sitemap = taxonomy.sitemap
        page.taxonomies = {} of String => Array(String)
        page.taxonomy_name = taxonomy.name
        page.pagination_enabled = false
        page
      end

      private def self.extract_terms_for(page : Models::Page, taxonomy : Models::TaxonomyConfig) : Array(String)
        name = taxonomy.name
        if page.taxonomies.has_key?(name)
          return page.taxonomies[name].dup
        end

        if page.front_matter_keys.includes?(name)
          return [] of String
        end

        return page.tags.dup if name == "tags"

        [] of String
      end

      private def self.apply_template(
        template_content : String?,
        html_content : String,
        page : Models::Section,
        site : Models::Site,
        templates : Hash(String, String),
      ) : String
        return html_content unless template_content

        builder = Core::Build::Builder.new
        builder.apply_template(template_content, html_content, page, site.config, "", "", templates)
      end

      private def self.generate_taxonomy_feed(
        taxonomy : Models::TaxonomyConfig,
        term : String,
        pages : Array(Models::Page),
        site : Models::Site,
        output_dir : String,
        base_url : String,
      )
        return if site.config.base_url.empty?

        feed_output_dir = File.join(output_dir, base_url.sub(/^\//, ""))
        FileUtils.mkdir_p(feed_output_dir)
        feed_title = "#{site.config.title} - #{taxonomy.name.capitalize}: #{term}"

        feed_pages = pages.dup
        feed_pages.sort! do |a, b|
          date_a = a.updated || a.date
          date_b = b.updated || b.date

          if date_a && date_b
            date_b.not_nil! <=> date_a.not_nil!
          elsif date_a
            -1
          elsif date_b
            1
          else
            0
          end
        end

        if site.config.feeds.limit > 0
          feed_pages = feed_pages.first(site.config.feeds.limit)
        end

        Content::Seo::Feeds.process_feed(
          feed_pages,
          site.config,
          feed_output_dir,
          "",
          feed_title,
          base_url
        )
      end

      private def self.page_url(base_url : String, page_number : Int32) : String
        if page_number == 1
          base_url
        else
          "#{base_url}page/#{page_number}/"
        end
      end

      private def self.build_term_list(terms : Array(String), base_path : String, base_url : String) : String
        String.build do |str|
          str << "<ul class=\"taxonomy-terms\">\n"
          terms.each do |term|
            term_slug = slugify(term)
            term_url = join_url(base_url, base_path, term_slug + "/")
            str << "  <li><a href=\"#{HTML.escape(term_url)}\">#{HTML.escape(term)}</a></li>\n"
          end
          str << "</ul>\n"
        end
      end

      private def self.build_page_list(pages : Array(Models::Page), base_url : String) : String
        String.build do |str|
          str << "<ul class=\"taxonomy-pages\">\n"
          pages.each do |page|
            term_url = join_url(base_url, page.url)
            str << "  <li><a href=\"#{HTML.escape(term_url)}\">#{HTML.escape(page.title)}</a></li>\n"
          end
          str << "</ul>\n"
        end
      end

      private def self.join_url(*parts : String) : String
        base = parts.first? || ""
        suffix = parts[1..].join("")
        if base.empty?
          return suffix
        end

        base.rstrip("/") + "/" + suffix.lstrip("/")
      end

      private def self.slugify(text : String) : String
        text.downcase
          .gsub(/[^a-z0-9\s-]/, "")
          .gsub(/\s+/, "-")
          .strip("-")
      end

      private def self.write_output(page : Models::Section, output_dir : String, content : String)
        output_path = File.join(output_dir, page.url.sub(/^\//, ""), "index.html")
        FileUtils.mkdir_p(Path[output_path].dirname)
        File.write(output_path, content)
        Logger.action :create, output_path
      end

      private def self.write_paginated_output(page : Models::Section, page_number : Int32, output_dir : String, content : String)
        output_path = File.join(output_dir, page.url.sub(/^\//, ""), "page", page_number.to_s, "index.html")
        FileUtils.mkdir_p(Path[output_path].dirname)
        File.write(output_path, content)
        Logger.action :create, output_path
      end
    end
  end
end
