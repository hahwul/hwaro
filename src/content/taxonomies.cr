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
require "../utils/path_utils"
require "../utils/text_utils"
require "../utils/sort_utils"
require "../content/pagination/renderer"

module Hwaro
  module Content
    class Taxonomies
      def self.generate(site : Models::Site, output_dir : String, templates : Hash(String, String), verbose : Bool = false, builder : Core::Build::Builder? = nil) : Array(Models::Section)
        config = site.config
        return [] of Models::Section if config.taxonomies.empty?

        build_taxonomy_index(site)

        # Reuse the running build's Builder when provided: its Crinja value
        # caches are warm (every page already converted by the Render phase)
        # and its stashed render-phase global vars can be reused outright.
        # The previous always-fresh Builder re-converted the entire site to
        # Crinja values a SECOND time — a duplicate O(N) pass on every
        # taxonomy-enabled build. The fresh-Builder fallback remains for
        # direct callers outside a build run.
        builder ||= Core::Build::Builder.new

        # Compute (or reuse) the site-wide template vars ONCE. apply_template
        # otherwise falls back to build_global_vars(site) on every taxonomy
        # term/page, re-iterating all pages/sections (and re-hashing assets)
        # per page — O(terms × site_size) of redundant work on a site with
        # many terms.
        global_vars = builder.render_global_vars_or_build(site)

        # Generate root taxonomies. On a multilingual site the root is the
        # default language's space (its content pages live at the root), so
        # scope the term listings to default-language pages — otherwise the
        # English `/tags/foo/` page also lists the Korean posts (with `/ko/`
        # links and translated titles), a cross-language leak. Non-multilingual
        # sites pass `nil` (no filtering needed — every page is the one space).
        root_language = config.multilingual? ? config.default_language : nil

        # On a multilingual site the default language is served at the root and,
        # like every other language, should honor its own per-language
        # `taxonomies` list. Previously the root always used the global
        # `config.taxonomies`, so the default language silently ignored
        # `[languages.<default>].taxonomies` while non-default languages
        # respected theirs — an asymmetry that emitted e.g. `/authors/` but never
        # `/ko/authors/` for identical per-language config. Fall back to the
        # global list when the default language has no `[languages.<code>]` block.
        root_taxonomies = config.taxonomies
        if root_language && (default_cfg = config.languages[root_language]?)
          root_taxonomies = config.taxonomies.select { |t| default_cfg.taxonomies.includes?(t.name) }
        end

        # Collect every generated taxonomy index/term page (each a
        # Models::Section) so the caller can register them into the page set
        # the SEO generators read. Without this, taxonomy pages are written to
        # disk but never reach the sitemap/feeds/search/llms inputs, so
        # `taxonomy.sitemap` / `taxonomy.feed` had no effect.
        collected = [] of Models::Section

        generate_taxonomies_for_language(root_taxonomies, site, output_dir, templates, builder, verbose, global_vars, collected, language: root_language, lang_prefix: "")

        # For multilingual sites, also generate language-prefixed taxonomy pages
        # (e.g. /en/tags/, /en/categories/) using only pages of that language.
        # This closes the gap where non-default languages had no taxonomy UI at all.
        if config.multilingual?
          config.languages.each do |lang_code, lang_cfg|
            # The default language is served at the site root, and its
            # taxonomies were already emitted there by the call above. Emitting
            # them again under `/<default_language>/` produces orphaned
            # duplicate URLs (not in the sitemap, no canonical) — skip it.
            next if lang_code == config.default_language
            next if lang_cfg.taxonomies.empty?

            # Build a filtered view of taxonomies for just this language's pages
            lang_taxonomies = build_language_taxonomies(site, lang_cfg.taxonomies)
            next if lang_taxonomies.empty?

            lang_taxonomy_configs = config.taxonomies.select { |t| lang_cfg.taxonomies.includes?(t.name) }
            generate_taxonomies_for_language(lang_taxonomy_configs, site, output_dir, templates, builder, verbose, global_vars, collected,
              language: lang_code, lang_prefix: "/#{lang_code}", lang_taxonomies: lang_taxonomies)
          end
        end

        collected
      end

      # Generate taxonomy index + terms for a (possibly language-scoped) set of taxonomies.
      private def self.generate_taxonomies_for_language(
        taxonomies : Array(Models::TaxonomyConfig),
        site : Models::Site,
        output_dir : String,
        templates : Hash(String, String),
        builder : Core::Build::Builder,
        verbose : Bool,
        global_vars : Hash(String, Crinja::Value),
        collected : Array(Models::Section),
        language : String?,
        lang_prefix : String,
        lang_taxonomies : Hash(String, Hash(String, Array(Models::Page)))? = nil,
      )
        taxonomies.each do |taxonomy|
          next if taxonomy.name.strip.empty?

          # A configured taxonomy always renders its index page, even with zero
          # terms, so site-internal links to it (e.g. the scaffold homepage's
          # `/tags/`, `/categories/`) don't 404 after a user removes the sample
          # terms. An empty index lists no terms rather than 404ing.
          # When a language-scoped map is in play (per-language call), a missing
          # taxonomy key must mean an empty index for that language — never the
          # global all-language map, which would leak foreign-language terms and
          # 404 links into /<lang>/<taxonomy>/. The root call (lang_taxonomies
          # == nil) keeps the global fallback.
          terms_map = if lt = lang_taxonomies
                        lt[taxonomy.name]? || {} of String => Array(Models::Page)
                      else
                        site.taxonomies[taxonomy.name]? || {} of String => Array(Models::Page)
                      end

          base_path = "#{lang_prefix}/#{taxonomy.name}/"
          index_page = build_taxonomy_index_page(taxonomy, base_path)
          if language
            index_page.language = language
          end

          # Assign each term a UNIQUE slug shared by both the index links and
          # the term-page file paths. Distinct terms can slugify identically
          # (e.g. "C++"/"C#" → "c", "Hello World"/"hello-world" → "hello-world");
          # without disambiguation the second term page overwrites the first's
          # index.html and the index emits two links to the same URL. The same
          # helper backs the get_taxonomy / get_taxonomy_url template functions
          # (via build_global_vars) so their links match these written paths.
          slug_map = Utils::TextUtils.disambiguated_slugs(terms_map.keys)

          # Only list terms whose term pages are actually written for this
          # language, so the index never links to a term page that the
          # language-filtered loop below skips (dead /tags/<term>/ links).
          index_terms = if language
                          terms_map.select { |_term, pgs| pgs.any? { |p| (p.language || site.config.default_language) == language } }.keys
                        else
                          terms_map.keys
                        end
          render_taxonomy_index(index_page, sort_terms(taxonomy, index_terms, terms_map, language, site.config.default_language), templates, site, output_dir, builder, verbose, global_vars, slug_map)
          collected << index_page

          terms_map.each do |term, pages|
            # Filter pages to the requested language when doing per-lang generation
            filtered_pages = if language
                               pages.select { |p| (p.language || site.config.default_language) == language }
                             else
                               pages
                             end
            next if filtered_pages.empty?

            collected << render_taxonomy_term(taxonomy, term, filtered_pages, templates, site, output_dir, builder, verbose, global_vars, slug_map[term], lang_prefix: lang_prefix, language: language)
          end
        end
      end

      # Order the index page's terms list per the taxonomy's `terms_sort_by`:
      # "name" (default) is alphabetical ascending; "count" is page count
      # descending with a name-ascending tiebreak. Counts use the
      # language-filtered page lists so a per-language index reflects that
      # language's own term sizes.
      private def self.sort_terms(
        taxonomy : Models::TaxonomyConfig,
        terms : Array(String),
        terms_map : Hash(String, Array(Models::Page)),
        language : String?,
        default_language : String,
      ) : Array(String)
        return terms.sort unless taxonomy.terms_sort_by == "count"

        counts = {} of String => Int32
        terms.each do |term|
          pages = terms_map[term]? || [] of Models::Page
          counts[term] = if language
                           pages.count { |p| (p.language || default_language) == language }
                         else
                           pages.size
                         end
        end
        terms.sort do |a, b|
          cmp = counts[b] <=> counts[a]
          cmp == 0 ? (a <=> b) : cmp
        end
      end

      # Build per-language taxonomy maps from the already-aggregated site.taxonomies,
      # but only using pages that belong to the given language.
      private def self.build_language_taxonomies(site : Models::Site, enabled_taxonomy_names : Array(String)) : Hash(String, Hash(String, Array(Models::Page)))
        result = {} of String => Hash(String, Array(Models::Page))

        site.pages.each do |page|
          next if page.excluded_from_listings?

          enabled_taxonomy_names.each do |tax_name|
            values = page.taxonomy_values(tax_name)
            next if values.empty?

            values.each do |term|
              next if term.strip.empty?

              tax_map = result[tax_name]? || begin
                result[tax_name] = {} of String => Array(Models::Page)
                result[tax_name]
              end

              term_list = tax_map[term]? || begin
                tax_map[term] = [] of Models::Page
                tax_map[term]
              end

              term_list << page
            end
          end
        end

        # Sort each term's pages per its taxonomy's configured order
        # (consistent with global behavior)
        sort_taxonomy_pages(result, site.config)

        result
      end

      private def self.build_taxonomy_index(site : Models::Site)
        site.taxonomies.clear
        config = site.config

        site.pages.each do |page|
          next if page.excluded_from_listings?

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

        sort_taxonomy_pages(site.taxonomies, config)
      end

      # Sort every term's page list per its taxonomy's sort_by/reverse
      # (date-desc for taxonomies not in the config, matching the render
      # phase's rebuild_taxonomies).
      private def self.sort_taxonomy_pages(taxonomies : Hash(String, Hash(String, Array(Models::Page))), config : Models::Config)
        tax_configs = config.taxonomies.index_by(&.name)
        taxonomies.each do |name, terms|
          cfg = tax_configs[name]?
          sort_by = cfg.try(&.sort_by) || "date"
          reverse = cfg.try(&.reverse) || false
          terms.each_key do |term|
            terms[term] = Utils::SortUtils.sort_pages(terms[term], sort_by, reverse)
          end
        end
      end

      private def self.render_taxonomy_index(
        page : Models::Section,
        terms : Array(String),
        templates : Hash(String, String),
        site : Models::Site,
        output_dir : String,
        builder : Core::Build::Builder,
        verbose : Bool,
        global_vars : Hash(String, Crinja::Value),
        slug_map : Hash(String, String),
      )
        template_name = ["taxonomy", "page"].find { |n| templates.has_key?(n) }
        template_content = template_name.try { |n| templates[n] }
        html_content = build_term_list(terms, page.url, site.config.base_url, slug_map)

        final_html = apply_template(template_content, html_content, page, site, templates, builder: builder, global_vars: global_vars, template_name: template_name)
        write_output(page, output_dir, final_html, verbose)
      end

      private def self.render_taxonomy_term(
        taxonomy : Models::TaxonomyConfig,
        term : String,
        pages : Array(Models::Page),
        templates : Hash(String, String),
        site : Models::Site,
        output_dir : String,
        builder : Core::Build::Builder,
        verbose : Bool,
        global_vars : Hash(String, Crinja::Value),
        slug : String,
        lang_prefix : String = "",
        language : String? = nil,
      ) : Models::Section
        base_url = "#{lang_prefix}/#{taxonomy.name}/#{slug}/"

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
        if language
          index_page.language = language
        end

        paginated_pages = paginate_taxonomy(taxonomy, pages, index_page)

        template_name = ["taxonomy_term", "taxonomy", "page"].find { |n| templates.has_key?(n) }
        template_content = template_name.try { |n| templates[n] }

        paginated_pages.each do |paginated_page|
          list_html = build_page_list(paginated_page.pages, site.config.base_url)
          renderer = Content::Pagination::Renderer.new(site.config)
          pagination_html = renderer.render_pagination_nav(paginated_page)
          seo_links = renderer.render_seo_links(paginated_page)
          html_content = list_html + pagination_html

          final_html = apply_template(template_content, html_content, index_page, site, templates, paginated_page, builder: builder, global_vars: global_vars, template_name: template_name, pagination_seo_links: seo_links)

          if paginated_page.page_number == 1
            write_output(index_page, output_dir, final_html, verbose)
          else
            write_paginated_output(index_page, paginated_page.page_number, output_dir, final_html, verbose, index_page.paginate_path)
          end
        end

        generate_taxonomy_feed(taxonomy, term, pages, site, output_dir, base_url, verbose) if taxonomy.feed

        index_page
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
          base_url: "#{index_page.url.rstrip("/")}/#{index_page.paginate_path}/",
        )] if per_page <= 0 || pages.size <= per_page

        total_items = pages.size
        total_pages = [(total_items.to_f / per_page).ceil.to_i, 1].max
        paginated_pages = [] of Content::Pagination::PaginatedPage
        paginator_base_url = "#{index_page.url.rstrip("/")}/#{index_page.paginate_path}/"

        (1..total_pages).each do |page_number|
          start_idx = (page_number - 1) * per_page
          end_idx = [start_idx + per_page, total_items].min
          page_items = pages[start_idx...end_idx]

          has_prev = page_number > 1
          has_next = page_number < total_pages
          prev_url = has_prev ? page_url(index_page.url, page_number - 1, index_page.paginate_path) : nil
          next_url = has_next ? page_url(index_page.url, page_number + 1, index_page.paginate_path) : nil
          first_url = page_url(index_page.url, 1, index_page.paginate_path)
          last_url = page_url(index_page.url, total_pages, index_page.paginate_path)

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
            base_url: paginator_base_url,
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
        page.taxonomy_values(taxonomy.name)
      end

      private def self.apply_template(
        template_content : String?,
        html_content : String,
        page : Models::Section,
        site : Models::Site,
        templates : Hash(String, String),
        paginator : Content::Pagination::PaginatedPage? = nil,
        builder : Core::Build::Builder? = nil,
        global_vars : Hash(String, Crinja::Value)? = nil,
        template_name : String? = nil,
        pagination_seo_links : String = "",
      ) : String
        return html_content unless template_content

        # Determine current URL for this pager if provided
        current_url = if paginator
                        if paginator.page_number == 1
                          page.url
                        else
                          "#{page.url.rstrip("/")}/#{page.paginate_path}/#{paginator.page_number}/"
                        end
                      else
                        page.url
                      end

        b = builder || Core::Build::Builder.new
        b.apply_template(
          template: template_content,
          content: html_content,
          page: page,
          site: site,
          section_list: "",
          toc: "",
          templates: templates,
          pagination: "", # We don't pass pre-rendered pagination here as it is embedded in content? Wait.
          page_url_override: current_url,
          paginator: paginator,
          global_vars: global_vars,
          template_name: template_name,
          pagination_seo_links: pagination_seo_links
        )
      end

      private def self.generate_taxonomy_feed(
        taxonomy : Models::TaxonomyConfig,
        term : String,
        pages : Array(Models::Page),
        site : Models::Site,
        output_dir : String,
        base_url : String,
        verbose : Bool = false,
      )
        # No base_url guard: like the main and section feeds, taxonomy feeds
        # emit with relative URLs when base_url is empty (the user opted in via
        # `feed = true`) rather than being silently dropped.
        feed_output_dir = File.join(output_dir, base_url.lchop("/"))
        Hwaro::Utils::FileSafe.mkdir_p(feed_output_dir)
        feed_title = "#{site.config.title} - #{taxonomy.name.capitalize}: #{term}"

        feed_pages = pages.sort { |a, b| Utils::SortUtils.compare_by_date(a, b) }

        if site.config.feeds.limit > 0
          feed_pages = feed_pages.first(site.config.feeds.limit)
        end

        Content::Seo::Feeds.process_feed(
          feed_pages,
          site.config,
          feed_output_dir,
          "",
          feed_title,
          base_url,
          verbose
        )
      end

      private def self.page_url(base_url : String, page_number : Int32, paginate_path : String = "page") : String
        normalized = base_url.ends_with?("/") ? base_url : "#{base_url}/"
        if page_number == 1
          normalized
        else
          "#{normalized}#{paginate_path}/#{page_number}/"
        end
      end

      private def self.build_term_list(terms : Array(String), base_path : String, base_url : String, slug_map : Hash(String, String)) : String
        String.build do |str|
          str << "<ul class=\"taxonomy-terms\">\n"
          terms.each do |term|
            term_slug = slug_map[term]? || Utils::TextUtils.safe_slugify(term)
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

      # Guard against escaping the output dir, then mkdir + write + log a
      # taxonomy output file. Shared by the single-page and paginated writers.
      private def self.write_to(output_path : String, output_dir : String, content : String, verbose : Bool)
        unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)
          Logger.warn "Skipping taxonomy output outside output directory: #{output_path}"
          return
        end

        Hwaro::Utils::FileSafe.mkdir_p(Path[output_path].dirname)
        Hwaro::Utils::FileSafe.atomic_write(output_path, content)
        Logger.action :create, output_path if verbose
      end

      private def self.write_output(page : Models::Section, output_dir : String, content : String, verbose : Bool = false)
        url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
        output_path = File.join(output_dir, url_path, "index.html")
        write_to(output_path, output_dir, content, verbose)
      end

      private def self.write_paginated_output(page : Models::Section, page_number : Int32, output_dir : String, content : String, verbose : Bool = false, paginate_path : String = "page")
        url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
        output_path = File.join(output_dir, url_path, paginate_path, page_number.to_s, "index.html")
        write_to(output_path, output_dir, content, verbose)
      end
    end
  end
end
