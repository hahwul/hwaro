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
require "../utils/errors"
require "../utils/logger"
require "../utils/path_utils"
require "../utils/text_utils"
require "../utils/sort_utils"
require "../content/pagination/renderer"

module Hwaro
  module Content
    class Taxonomies
      def self.generate(site : Models::Site, output_dir : String, templates : Hash(String, String), verbose : Bool = false, builder : Core::Build::Builder? = nil) : Array(Models::Section)
        # A caller-supplied builder may have run an earlier pass into this
        # same output directory (the serve session's builder); it removes
        # what that pass wrote and this one no longer does. See
        # `Builder#track_taxonomy_outputs`.
        return generate_untracked(site, output_dir, templates, verbose, builder) unless builder
        builder.track_taxonomy_outputs(output_dir) do
          generate_untracked(site, output_dir, templates, verbose, builder)
        end
      end

      private def self.generate_untracked(site : Models::Site, output_dir : String, templates : Hash(String, String), verbose : Bool, builder : Core::Build::Builder?) : Array(Models::Section)
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

        # Term `_index.md` files the parse phase matched to a term page
        # (match_term_metadata), by that page's URL.
        term_meta = site.sections.select(&.term_metadata).index_by(&.url)

        # Collect every generated taxonomy index/term page (each a
        # Models::Section) so the caller can register them into the page set
        # the SEO generators read. Without this, taxonomy pages are written to
        # disk but never reach the sitemap/feeds/search/llms inputs, so
        # `taxonomy.sitemap` / `taxonomy.feed` had no effect.
        collected = [] of Models::Section

        spaces = term_spaces(config, site.pages, site.taxonomies)
        # Every index and term URL this pass writes: a term file's alias must
        # not replace one of them with a redirect.
        taxonomy_urls = Set(String).new
        unless term_meta.empty?
          spaces.each do |space|
            taxonomy_urls << "#{space.lang_prefix}/#{space.taxonomy.name}/"
            space.index_terms.each { |term| taxonomy_urls << "#{space.lang_prefix}/#{space.taxonomy.name}/#{space.slug_map[term]}/" }
          end
        end
        spaces.each do |space|
          generate_term_space(space, site, output_dir, templates, builder, verbose, global_vars, collected, term_meta, taxonomy_urls)
        end

        collected
      end

      # One taxonomy in one output space (the root, or `/<lang>/`): the terms
      # it writes pages for and their slugs. ONE computation feeds both the
      # generator and `match_term_metadata`, so a term `_index.md` is headless
      # exactly when its term page is written.
      record TermSpace,
        taxonomy : Models::TaxonomyConfig,
        language : String?,
        lang_prefix : String,
        terms_map : Hash(String, Array(Models::Page)),
        index_terms : Array(String),
        slug_map : Hash(String, String)

      # `root_map` is the site-wide term index (`term_index`, which the
      # generator keeps on `site.taxonomies`).
      private def self.term_spaces(config : Models::Config, pages : Array(Models::Page), root_map : Hash(String, Hash(String, Array(Models::Page))), honor_suppressed : Bool = true) : Array(TermSpace)
        spaces = [] of TermSpace

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

        add_term_spaces(spaces, root_taxonomies, config, honor_suppressed, language: root_language, lang_prefix: "", root_map: root_map)

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
            # No early exit on an empty map: like the root, a configured
            # taxonomy writes its (empty) index so `/<lang>/tags/` links
            # never 404 on a site with no terms yet.
            lang_taxonomies = build_language_taxonomies(pages, config, lang_cfg.taxonomies, honor_suppressed)

            lang_taxonomy_configs = config.taxonomies.select { |t| lang_cfg.taxonomies.includes?(t.name) }
            add_term_spaces(spaces, lang_taxonomy_configs, config, honor_suppressed, language: lang_code, lang_prefix: "/#{lang_code}", lang_taxonomies: lang_taxonomies)
          end
        end

        spaces
      end

      private def self.add_term_spaces(
        spaces : Array(TermSpace),
        taxonomies : Array(Models::TaxonomyConfig),
        config : Models::Config,
        honor_suppressed : Bool,
        language : String?,
        lang_prefix : String,
        root_map : Hash(String, Hash(String, Array(Models::Page)))? = nil,
        lang_taxonomies : Hash(String, Hash(String, Array(Models::Page)))? = nil,
      ) : Nil
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
                        # A page the render phase refused to write stays in
                        # site.taxonomies (a later serve pass may hand its URL
                        # back) but off the term pages and feeds.
                        root_terms = root_map.try { |map| map[taxonomy.name]? } || {} of String => Array(Models::Page)
                        if honor_suppressed
                          root_terms.transform_values(&.reject(&.output_suppressed)).reject! { |_, pgs| pgs.empty? }
                        else
                          root_terms
                        end
                      end

          # Only list terms whose term pages are actually written for this
          # language, so the index never links to a term page that the
          # language-filtered loop below skips (dead /tags/<term>/ links).
          index_terms = if language
                          terms_map.select { |_term, pgs| pgs.any? { |p| (p.language || config.default_language) == language } }.keys
                        else
                          terms_map.keys
                        end
          # Assign each term a UNIQUE slug shared by both the index links and
          # the term-page file paths. Distinct terms can slugify identically
          # (e.g. "C++"/"C#" → "c", "Hello World"/"hello-world" → "hello-world");
          # without disambiguation the second term page overwrites the first's
          # index.html and the index emits two links to the same URL. The same
          # helper backs the get_taxonomy / get_taxonomy_url template functions
          # (via build_global_vars) so their links match these written paths.
          #
          # Disambiguated over the terms this output space actually writes
          # (`index_terms`), not every language's: `/tags/` and `/ko/tags/`
          # never share a directory, so a Korean-only `Zeta` must not push the
          # English `zeta` to `/tags/zeta-2/`.
          slug_map = Utils::TextUtils.disambiguated_slugs(index_terms)
          spaces << TermSpace.new(taxonomy, language, lang_prefix, terms_map, index_terms, slug_map)
        end
      end

      # Generate taxonomy index + terms for one output space.
      private def self.generate_term_space(
        space : TermSpace,
        site : Models::Site,
        output_dir : String,
        templates : Hash(String, String),
        builder : Core::Build::Builder,
        verbose : Bool,
        global_vars : Hash(String, Crinja::Value),
        collected : Array(Models::Section),
        term_meta : Hash(String, Models::Section),
        taxonomy_urls : Set(String),
      )
        taxonomy, language, lang_prefix = space.taxonomy, space.language, space.lang_prefix
        terms_map, index_terms, slug_map = space.terms_map, space.index_terms, space.slug_map

        base_path = "#{lang_prefix}/#{taxonomy.name}/"
        index_page = build_taxonomy_index_page(taxonomy, base_path)
        if language
          index_page.language = language
        end

        # A term too long to be a path segment is shortened (and digest-
        # suffixed) rather than crashing the build — but that moves its
        # published URL, so it must never be silent. This is the one place
        # the term set is enumerated once per taxonomy per build, so the
        # warning belongs here and not in `safe_slugify`, which runs per
        # link.
        index_terms.each do |term|
          next unless Utils::TextUtils.slug_truncated?(term)
          Logger.warn "Taxonomy term #{term.inspect} is too long for a path segment — its URL was shortened to /#{taxonomy.name}/#{slug_map[term]? || Utils::TextUtils.safe_slugify(term)}/. Shorten the term in the front matter of the pages that use it."
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

          slug = slug_map[term]
          meta = term_meta.empty? ? nil : term_meta["#{lang_prefix}/#{taxonomy.name}/#{slug}/"]?
          collected << render_taxonomy_term(taxonomy, term, filtered_pages, templates, site, output_dir, builder, verbose, global_vars, slug, lang_prefix: lang_prefix, language: language, meta: meta, taxonomy_urls: taxonomy_urls)
        end
      end

      # True for `content/<taxonomy>/<dir>/_index[.<lang>].md` with
      # `<taxonomy>` a configured taxonomy: a file that MAY describe a term
      # page (gh#891). Only `match_term_metadata` decides whether it does;
      # doctor, which builds nothing, uses this alone to stay quiet about
      # such files. `content/<taxonomy>/_index.md` (the taxonomy index) is
      # never a candidate.
      def self.term_metadata_path?(relative_path : String, config : Models::Config) : Bool
        parts = Path[relative_path].parts
        parts.size == 3 && parts[2].starts_with?("_index.") && config.taxonomies.any? { |t| t.name == parts[0] }
      end

      # A term `_index.md` matched to the generated term page at `url`;
      # `shadowed_by` is the file that won the same page (nil for the winner).
      record TermFile, url : String, shadowed_by : String?

      # The candidate files (`term_metadata_path?`) that would publish at the
      # URL (NFC) of a term page this build writes: the directory is the
      # term's slug in the file's language — `content/tags/rust-lang/_index.md`
      # for `/tags/rust-lang/`, `content/tags/c-2/_index.md` for a
      # disambiguated `/tags/c-2/`, `_index.ko.md` for `/ko/tags/<slug>/` —
      # and no `path` or `[permalinks]` rule moved it elsewhere. Keyed by
      # section path. A matched file describes that term page instead of
      # publishing a page of its own (Builder#mark_term_metadata); every other
      # candidate stays an ordinary section, exactly as before. When several
      # files match one page (`_index.md` beside `_index.markdown`),
      # `_index.md` wins, else the first path; the others are reported and
      # not published.
      def self.match_term_metadata(pages : Array(Models::Page), sections : Array(Models::Section), config : Models::Config) : Hash(String, TermFile)
        result = {} of String => TermFile
        candidates = sections.select { |s| term_metadata_path?(s.path, config) }
        return result if candidates.empty?

        urls = Set(String).new
        # `pages` already leaves out the pages that lose their URL
        # (Builder#match_term_files), so the stored `output_suppressed` —
        # unset on a cold build, the last pass's on a serve one — is ignored.
        term_spaces(config, pages, term_index(pages, config), honor_suppressed: false).each do |space|
          space.index_terms.each do |term|
            urls << "#{space.lang_prefix}/#{space.taxonomy.name}/#{space.slug_map[term]}/"
          end
        end

        winners = {} of String => String
        # A plain `_index.md` first, then path order.
        candidates.sort_by { |s| {File.basename(s.path) == "_index.md" ? 0 : 1, s.path} }.each do |section|
          url = section.url.ascii_only? ? section.url : section.url.unicode_normalize(:nfc)
          next unless urls.includes?(url)
          winner = winners[url]?
          winners[url] = section.path unless winner
          result[section.path] = TermFile.new(url, winner)
        end
        result
      end

      # Order the index page's terms list per the taxonomy's `terms_sort_by`:
      # "name" (default) is alphabetical ascending, ignoring case; "count" is page count
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
        Utils::SortUtils.sort_term_names(terms, taxonomy.terms_sort_by == "count") do |term|
          pages = terms_map[term]? || [] of Models::Page
          language ? pages.count { |p| (p.language || default_language) == language } : pages.size
        end
      end

      # Build per-language taxonomy maps from the already-aggregated site.taxonomies,
      # but only using pages that belong to the given language.
      private def self.build_language_taxonomies(pages : Array(Models::Page), config : Models::Config, enabled_taxonomy_names : Array(String), honor_suppressed : Bool = true) : Hash(String, Hash(String, Array(Models::Page)))
        result = {} of String => Hash(String, Array(Models::Page))

        pages.each do |page|
          next if page.excluded_from_listings?
          next unless config.versions.in_taxonomies?(page)
          # Set by the render phase for pages it refused to write (URL
          # traverses out of the output dir): the term page would link a
          # 404 and the term feed would advertise it.
          next if honor_suppressed && page.output_suppressed

          enabled_taxonomy_names.each do |tax_name|
            values = page.taxonomy_values(tax_name)
            next if values.empty?

            # `uniq`: a term repeated in one page's front matter lists the page once.
            values.uniq.each do |term|
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
        sort_taxonomy_pages(result, config)

        result
      end

      private def self.build_taxonomy_index(site : Models::Site)
        site.taxonomies.clear
        term_index(site.pages, site.config).each { |name, terms| site.taxonomies[name] = terms }
      end

      # Every configured taxonomy's terms → their pages, over the pages a term
      # page lists.
      private def self.term_index(pages : Array(Models::Page), config : Models::Config) : Hash(String, Hash(String, Array(Models::Page)))
        index = {} of String => Hash(String, Array(Models::Page))

        pages.each do |page|
          next if page.excluded_from_listings?
          # `[versions] taxonomies = "latest"` (default): only the latest
          # version (plus unversioned content) populates term pages.
          next unless config.versions.in_taxonomies?(page)

          config.taxonomies.each do |taxonomy|
            name = taxonomy.name
            next if name.strip.empty?

            values = page.taxonomy_values(name)
            next if values.empty?

            # `uniq`: a term repeated in one page's front matter lists the page once.
            values.uniq.each do |term|
              next if term.strip.empty?

              terms = index[name]? || begin
                index[name] = {} of String => Array(Models::Page)
                index[name]
              end

              list = terms[term]? || begin
                terms[term] = [] of Models::Page
                terms[term]
              end

              list << page
            end
          end
        end

        sort_taxonomy_pages(index, config)
        index
      end

      # Sort every term's page list per its taxonomy's sort_by/reverse
      # (date-desc for taxonomies not in the config). ONE implementation
      # serves both the generator (populate_taxonomies) and the render
      # phase's rebuild_taxonomies (transform.cr) — per-term ordering
      # drifting between the written pages and get_taxonomy is exactly the
      # bug class this shared helper prevents.
      def self.sort_taxonomy_pages(taxonomies : Hash(String, Hash(String, Array(Models::Page))), config : Models::Config)
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
        write_output(page, output_dir, final_html, verbose, builder)
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
        meta : Models::Section? = nil,
        taxonomy_urls : Set(String) = Set(String).new,
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
        # The term's `_index.md` (see match_term_metadata): its values win,
        # and its body — rendered by the render pass (Builder#render_term_bodies)
        # — is the `term_content` template variable; `content` stays the
        # generated page list templates already print. Its aliases redirect
        # here, written and claimed like the page itself.
        if meta
          index_page.title = meta.title unless meta.untitled?
          index_page.description = meta.description
          index_page.image = meta.image
          index_page.extra = meta.extra
          index_page.content = meta.content
          builder.write_term_aliases(meta, site, output_dir, verbose, taxonomy_urls)
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

          final_html = apply_template(template_content, html_content, index_page, site, templates, paginated_page, builder: builder, global_vars: global_vars, template_name: template_name, pagination: pagination_html, pagination_seo_links: seo_links)

          if paginated_page.page_number == 1
            write_output(index_page, output_dir, final_html, verbose, builder)
          else
            write_paginated_output(index_page, paginated_page.page_number, output_dir, final_html, verbose, index_page.paginate_path, builder)
          end
        end

        generate_taxonomy_feed(taxonomy, term, index_page.title, pages, site, output_dir, base_url, verbose, templates, builder, language) if taxonomy.feed

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
        pagination : String = "",
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
          # Also appended to `content` (the term list), which templates
          # have always printed; `pagination` serves custom listings.
          pagination: pagination,
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
        title : String,
        pages : Array(Models::Page),
        site : Models::Site,
        output_dir : String,
        base_url : String,
        verbose : Bool = false,
        templates : Hash(String, String)? = nil,
        builder : Core::Build::Builder? = nil,
        language : String? = nil,
      )
        # No base_url guard on emission: like the main and section feeds,
        # taxonomy feeds emit with relative URLs when base_url is empty.
        # Directory still goes through the shared feed path guard so a
        # traversal-shaped term/URL can't escape the public tree.
        feed_output_dir = Content::Seo::Feeds.feed_output_dir_for(output_dir, base_url)
        return unless feed_output_dir
        # The term page's title: "Tags: rust" unless its `_index.md` names it.
        feed_title = "#{site.config.title} - #{title}"
        # Same reason as the term page: nothing else records that this feed is
        # still wanted, so a removed term left `tags/<slug>/rss.xml` behind.
        # Like section and language feeds, a term feed always takes the
        # default name for `[feeds] type` — `[feeds] filename` names only the
        # main feed — so this is the "" that `process_feed` gets below.
        builder.try(&.claim_generated_output(
          File.join(feed_output_dir, Content::Seo::Feeds.safe_feed_filename("", site.config.feeds.type))
        ))

        # No caller-side sort/limit: process_feed itself sorts date-desc
        # (SortUtils.compare_by_date) and applies feeds.limit. Dedupe by URL
        # so collision losers (not written as HTML) never appear in the feed,
        # and keep `redirect_to` stubs out like every other feed does. Older
        # versions follow `[versions] feeds`, not `taxonomies`, as in every
        # other feed.
        versions = site.config.versions
        Content::Seo::Feeds.process_feed(
          Content::Seo::Feeds.dedupe_by_output_url(pages.select { |p| p.published_content? && versions.in_feeds?(p) }),
          site.config,
          feed_output_dir,
          "",
          feed_title,
          base_url,
          verbose,
          Content::Seo::Feeds.feed_language(site.config, language),
          templates: templates,
          renderer: builder.try(&.feed_template_renderer),
          kind: "taxonomy",
          taxonomy: taxonomy.name,
          term: term
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
      private def self.write_to(output_path : String, output_dir : String, content : String, verbose : Bool, builder : Core::Build::Builder? = nil)
        unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)
          Logger.warn "Skipping taxonomy output outside output directory: #{output_path}"
          return
        end

        # The taxonomy page keeps the path it always took — sites put a
        # `content/tags/_index.md` there to get the section into menus, and
        # still expect the generated term index — but replacing an authored
        # page (Builder#page_output_owner) is no longer silent: sitemap, feeds
        # and search still advertise that page's URL.
        if owner = builder.try(&.page_output_owner(output_path, output_dir))
          Logger.warn "Taxonomy page #{output_path} replaces content page '#{owner}', which publishes the same path. Rename that page (slug/path) or the taxonomy term to keep both."
        end

        # No content file backs a taxonomy page, so nothing else records that
        # this build still wants it. Claiming it lets the Finalize phase
        # delete the term pages a previous `--cache` build left behind when
        # its last post was deleted (the output directory survives a warm
        # build, and this generator only ever writes the terms that exist).
        builder.try(&.claim_generated_output(output_path))

        if builder && output_path.ends_with?(".html")
          content = builder.privacy_rewrite(content)
        end

        begin
          Hwaro::Utils::FileSafe.mkdir_p(Path[output_path].dirname)
          Hwaro::Utils::FileSafe.atomic_write(output_path, content)
          builder.try(&.record_html_stats(content))
        rescue ex : File::Error
          # Term slugs are unbounded (a pasted phrase in `tags` becomes a
          # 300-character directory name), so this writer is where a term the
          # filesystem cannot represent surfaces — ENAMETOOLONG. Unclassified
          # the File::Error escaped the `taxonomy:generate` hook and the CLI
          # blamed an internal hwaro fault (exit 70) for what is a content
          # problem the author can fix in front matter. Everything else
          # (permissions, full disk) stays an IO error.
          # Windows reports a path past MAX_PATH as not-found or invalid-name,
          # never ENAMETOOLONG; judge the length there instead, of the path
          # Windows sees (absolute, in UTF-16 units).
          too_long = {% if flag?(:windows) %} File.expand_path(output_path).to_utf16.size >= 260 {% else %} ex.os_error == Errno::ENAMETOOLONG {% end %}
          raise Hwaro::HwaroError.new(
            code: too_long ? Hwaro::Errors::HWARO_E_CONTENT : Hwaro::Errors::HWARO_E_IO,
            message: "Failed to write taxonomy page #{output_path.inspect}: #{ex.message}",
            hint: too_long ? "A taxonomy term is too long for this filesystem — shorten the term in the front matter of the pages that use it." : nil,
            cause: ex,
          )
        end
        Logger.action :create, output_path if verbose
      end

      # Refuse-outright, like every other writer (see
      # `PathUtils.split_safe_segments`): sanitize-and-join would relocate the
      # page onto the shortened path instead of skipping it. Reachable only if
      # a term ever escapes `safe_slugify`, but every writer family must answer
      # this question the same way.
      private def self.write_output(page : Models::Section, output_dir : String, content : String, verbose : Bool = false, builder : Core::Build::Builder? = nil)
        segments, refused = Utils::PathUtils.split_safe_segments(page.url.lchop("/"))
        if refused
          Logger.warn "Skipping taxonomy page #{page.url.inspect}: a path segment would escape the output directory."
          return
        end
        output_path = File.join(output_dir, segments.join("/"), "index.html")
        write_to(output_path, output_dir, content, verbose, builder)
      end

      private def self.write_paginated_output(page : Models::Section, page_number : Int32, output_dir : String, content : String, verbose : Bool = false, paginate_path : String = "page", builder : Core::Build::Builder? = nil)
        segments, refused = Utils::PathUtils.split_safe_segments(page.url.lchop("/"))
        return if refused
        output_path = File.join(output_dir, segments.join("/"), paginate_path, page_number.to_s, "index.html")
        write_to(output_path, output_dir, content, verbose, builder)
      end
    end
  end
end
