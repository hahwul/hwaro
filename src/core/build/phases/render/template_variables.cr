# Render phase — per-page template variables.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Build template variables hash for Crinja
  private def build_template_variables(
    page : Models::Page,
    site : Models::Site,
    content : String,
    section_list : String,
    toc : String,
    toc_headers : Array(Models::TocHeader) = [] of Models::TocHeader,
    pagination : String = "",
    page_url_override : String? = nil,
    paginator : Content::Pagination::PaginatedPage? = nil,
    global_vars : Hash(String, Crinja::Value)? = nil,
    pagination_seo_links : String = "",
    features : Builder::TemplateVarFeatures? = nil,
  ) : Hash(String, Crinja::Value)
    config = site.config

    # Build page-specific vars into a fresh hash, then merge global_vars
    # at the end.  This is cheaper than global_vars.dup (which copies ~25
    # entries including heavy __all_pages__) because page vars are the
    # smaller set (~50 entries) and we only iterate global_vars once via
    # merge! rather than duplicating it per page.
    vars = {} of String => Crinja::Value

    effective_url = page_url_override || page.url

    # Precompute date strings once to avoid repeated .to_s formatting
    date_str = page.date.try(&.to_s("%Y-%m-%d")) || ""
    updated_str = page.updated.try(&.to_s("%Y-%m-%d")) || ""
    date_crinja = Crinja::Value.new(date_str)

    # Page variables (flat for convenience)
    vars["page_title"] = Crinja::Value.new(page.title)
    vars["page_description"] = Crinja::Value.new(page.description || config.description || "")
    vars["page_url"] = Crinja::Value.new(effective_url)
    vars["page_section"] = Crinja::Value.new(page.section)
    vars["page_date"] = date_crinja
    vars["page_image"] = Crinja::Value.new(page.image || config.og.default_image || "")
    vars["taxonomy_name"] = Crinja::Value.new(page.taxonomy_name || "")
    vars["taxonomy_term"] = Crinja::Value.new(page.taxonomy_term || "")
    default_lang = config.default_language
    page_language = page.language || default_lang
    vars["page_language"] = Crinja::Value.new(page_language)

    # `lang_prefix` is `""` for the default language and `"/<code>"`
    # for every other configured language, so multilingual scaffold
    # templates can write links as `{{ base_url }}{{ lang_prefix }}/posts/`
    # and have them resolve correctly per locale (gh#524).
    lang_prefix = page_language != default_lang && config.multilingual? ? "/#{page_language}" : ""
    vars["lang_prefix"] = Crinja::Value.new(lang_prefix)

    # Versioned docs: `page_version` (the version NAME, read by get_menu to
    # pick the version-scoped menu set) and the global `versions` list,
    # whose root URLs carry this page's language prefix. Both exist only
    # when `[[versions.list]]` is configured.
    versions_enabled = config.versions.enabled?
    if versions_enabled
      vars["page_version"] = Crinja::Value.new(page.version.try(&.name))
      vars["versions"] = Content::Versions.versions_value(config, lang_prefix)
    end

    # Generate permalink only if not already set
    page.generate_permalink(config.base_url) unless page.permalink

    # Reuse cached Crinja arrays for tags/authors/assets/extra/translations
    # (avoids per-page .map allocation)
    cached_page_val = cached_page_crinja_value(page, default_lang)
    cached_raw = cached_page_val.raw.as(Hash)
    tags_crinja = cached_raw["tags"].as(Crinja::Value)
    authors_crinja = cached_raw["authors"].as(Crinja::Value)
    assets_crinja = cached_raw["assets"].as(Crinja::Value)
    extra_crinja = cached_raw["extra"].as(Crinja::Value)
    translations_crinja = cached_raw["translations"].as(Crinja::Value)
    vars["page_translations"] = translations_crinja

    # Reuse cached Crinja::Value for lower/higher pages
    lower_obj = page.lower.try { |l| cached_page_crinja_value(l, default_lang) }
    higher_obj = page.higher.try { |h| cached_page_crinja_value(h, default_lang) }

    # Build ancestors array (cached per section+language — MEMBER pages in
    # the same section AND language share ancestors). The language is part of
    # the key because a multilingual section has per-language ancestors;
    # omitting it served whichever language rendered first to every language
    # (mirrors the section_pages cache key). Section-index pages bypass the
    # cache entirely: their ancestors EXCLUDE themselves (transform.cr) while
    # member pages' ancestors include the section, so sharing the key let the
    # first writer poison the other kind — a section listing itself in its
    # own breadcrumb, or members losing their parent. Each section renders
    # once, so building directly costs nothing.
    ancestors_cache_key = {page.section, page.language}
    ancestors_array = if page.is_a?(Models::Section)
                        build_ancestors_crinja(page)
                      elsif @crinja_caches_frozen
                        if cached = @ancestors_crinja_cache[ancestors_cache_key]?
                          @cache_manager.record_hit("ancestors_crinja")
                          cached
                        else
                          @cache_manager.record_miss("ancestors_crinja")
                          build_ancestors_crinja(page)
                        end
                      else
                        @crinja_cache_mutex.synchronize do
                          if cached = @ancestors_crinja_cache[ancestors_cache_key]?
                            @cache_manager.record_hit("ancestors_crinja")
                            next cached.as(Array(Crinja::Value))
                          end
                          @cache_manager.record_miss("ancestors_crinja")
                          arr = build_ancestors_crinja(page)
                          @ancestors_crinja_cache[ancestors_cache_key] = arr
                          arr
                        end
                      end

    # Page object with all properties
    page_obj = {
      "title"        => Crinja::Value.new(page.title),
      "description"  => Crinja::Value.new(page.description || ""),
      "url"          => Crinja::Value.new(effective_url),
      "section"      => Crinja::Value.new(page.section),
      "date"         => date_crinja,
      "updated"      => Crinja::Value.new(updated_str),
      "image"        => Crinja::Value.new(page.image || ""),
      "draft"        => Crinja::Value.new(page.draft),
      "toc"          => Crinja::Value.new(page.toc),
      "render"       => Crinja::Value.new(page.render),
      "is_index"     => Crinja::Value.new(page.is_index),
      "generated"    => Crinja::Value.new(page.generated),
      "synthesized"  => Crinja::Value.new(page.synthesized?),
      "in_sitemap"   => Crinja::Value.new(page.in_sitemap),
      "language"     => Crinja::Value.new(page_language),
      "translations" => translations_crinja,
      # New properties
      "authors"           => authors_crinja,
      "tags"              => tags_crinja,
      "taxonomies"        => cached_raw["taxonomies"].as(Crinja::Value),
      "assets"            => assets_crinja,
      "extra"             => extra_crinja,
      "summary"           => Crinja::Value.new(page.summary_html || page.effective_summary || ""),
      "summary_truncated" => Crinja::Value.new(page.summary_truncated),
      "word_count"        => Crinja::Value.new(page.word_count),
      "reading_time"      => Crinja::Value.new(page.reading_time),
      "permalink"         => Crinja::Value.new(page.permalink || ""),
      "weight"            => Crinja::Value.new(page.weight),
      "git"               => cached_raw["git"].as(Crinja::Value),
      "in_search_index"   => Crinja::Value.new(page.in_search_index),
      "lower"             => lower_obj || Crinja::Value.new(nil),
      "higher"            => higher_obj || Crinja::Value.new(nil),
      "ancestors"         => Crinja::Value.new(ancestors_array),
      "series"            => Crinja::Value.new(page.series || ""),
      "series_index"      => Crinja::Value.new(page.series_index),
      "series_pages"      => if page.series.nil?
        # Mirror related_posts below: series-less pages (the default) must not
        # acquire the cache mutex just to hand back the same empty array.
        Crinja::Value.new([] of Crinja::Value)
      elsif @crinja_caches_frozen
        if cached_series = page.series.try { |s| @series_crinja_cache[s]? }
          @cache_manager.record_hit("series_crinja")
          cached_series
        else
          @cache_manager.record_miss("series_crinja")
          Crinja::Value.new(page.series_pages.map { |sp|
            cached_page_crinja_value(sp, default_lang)
          })
        end
      else
        @crinja_cache_mutex.synchronize do
          cached_series = page.series.try { |s| @series_crinja_cache[s]? }
          if cached_series
            @cache_manager.record_hit("series_crinja")
            next cached_series
          end
          @cache_manager.record_miss("series_crinja")
          val = Crinja::Value.new(page.series_pages.map { |sp|
            cached_page_crinja_value(sp, default_lang)
          })
          page.series.try { |s| @series_crinja_cache[s] = val }
          val
        end
      end,
      "related_posts" => if page.related_posts.empty?
        # Mirror the early-return that `series_pages` does for series-less
        # pages. Sites without `[related]` enabled (the default) get an
        # empty list on every page, and acquiring the cache mutex 1000+
        # times to hand back the same empty array measurably hurts on big
        # builds.
        Crinja::Value.new([] of Crinja::Value)
      elsif @crinja_caches_frozen
        if cached = @related_posts_crinja_cache[page.path]?
          @cache_manager.record_hit("related_posts_crinja")
          cached
        else
          @cache_manager.record_miss("related_posts_crinja")
          Crinja::Value.new(page.related_posts.map { |rp|
            cached_page_crinja_value(rp, default_lang)
          })
        end
      else
        @crinja_cache_mutex.synchronize do
          if cached = @related_posts_crinja_cache[page.path]?
            @cache_manager.record_hit("related_posts_crinja")
            next cached
          end
          @cache_manager.record_miss("related_posts_crinja")
          val = Crinja::Value.new(page.related_posts.map { |rp|
            cached_page_crinja_value(rp, default_lang)
          })
          @related_posts_crinja_cache[page.path] = val
          val
        end
      end,
    }
    if versions_enabled
      page_obj["version"] = cached_raw["version"].as(Crinja::Value)
      page_obj["version_links"] = cached_raw["version_links"].as(Crinja::Value)
    end
    vars["page"] = Crinja::Value.new(page_obj)

    # Flat variables for new properties
    vars["page_summary"] = Crinja::Value.new(page.summary_html || page.effective_summary || "")
    vars["page_word_count"] = Crinja::Value.new(page.word_count)
    vars["page_reading_time"] = Crinja::Value.new(page.reading_time)
    vars["page_permalink"] = Crinja::Value.new(page.permalink || "")
    vars["page_authors"] = authors_crinja
    vars["page_tags"] = tags_crinja
    vars["page_weight"] = Crinja::Value.new(page.weight)

    # Site variables (flat for convenience)
    # NOTE: site_title, site_description, base_url are now in global_vars
    # (computed once in build_global_vars). We skip them here to avoid
    # redundant Crinja::Value allocations per page.

    # Section variables
    section_title = ""
    section_description = ""
    section_pages_array = [] of Crinja::Value
    current_section = ""

    # Section-specific variables
    subsections_array = [] of Crinja::Value
    section_assets_val = Crinja::Value.new([] of Crinja::Value)
    page_template_var = ""
    paginate_path_var = "page"
    redirect_to_var = ""

    if page.is_a?(Models::Section)
      # For section pages, use the page itself as the section data
      section_title = page.title
      section_description = page.description || ""
      current_section = page.section

      # Section-specific properties
      page_template_var = page.page_template || ""
      paginate_path_var = page.paginate_path
      redirect_to_var = page.redirect_to || ""

      # Build subsections array. `Models::Section#pages` is NEVER populated
      # by the build pipeline (it stays []) — the live page list is the
      # per-section Crinja cache, the same source `get_section(...).pages`
      # uses in build_global_vars. Reading `sub.pages.size` here reported 0
      # for every subsection.
      subsections_array = page.subsections.map do |sub|
        Crinja::Value.new({
          "title"       => Crinja::Value.new(sub.title),
          "description" => Crinja::Value.new(sub.description || ""),
          "url"         => Crinja::Value.new(sub.url),
          "pages_count" => Crinja::Value.new(cached_section_pages_crinja(sub.section, sub.language, site).size),
        })
      end

      # Use the page's assets as section assets
      section_assets_val = assets_crinja
    elsif !page.section.empty?
      # For regular pages, find the parent section via O(1) lookup
      section_page = site.section_for(page.section, page.language)
      if section_page
        section_title = section_page.title
        section_description = section_page.description || ""
        current_section = page.section
        # Use cached section assets to avoid re-allocating per page
        section_assets_val = if @crinja_caches_frozen
                               if cached_arr = @section_assets_crinja_cache[page.section]?
                                 @cache_manager.record_hit("section_assets_crinja")
                                 Crinja::Value.new(cached_arr)
                               else
                                 @cache_manager.record_miss("section_assets_crinja")
                                 Crinja::Value.new(section_page.assets.map { |a| Crinja::Value.new(a) })
                               end
                             else
                               @crinja_cache_mutex.synchronize do
                                 if cached_arr = @section_assets_crinja_cache[page.section]?
                                   @cache_manager.record_hit("section_assets_crinja")
                                   next Crinja::Value.new(cached_arr).as(Crinja::Value)
                                 end
                                 @cache_manager.record_miss("section_assets_crinja")
                                 arr = section_page.assets.map { |a| Crinja::Value.new(a) }
                                 @section_assets_crinja_cache[page.section] = arr
                                 Crinja::Value.new(arr)
                               end
                             end
      end
    end

    if !current_section.empty?
      if paginator
        # Paginated: convert paginator's page subset
        default_lang = config.default_language
        section_pages_array = paginator.pages.map { |p| page_to_crinja_list_value(p, default_lang) }
      elsif features && !features.needs_section_pages
        # The template's closure never mentions `section`, so the O(section
        # size) minus-current copy below can never be observed — on a flat
        # N-page site it was the only super-linear per-page cost (N-1
        # element copies for every page). section_pages_array stays empty.
      else
        # Non-paginated: use per-section cache, then exclude current page.
        # O(1) lookup via the cached url→index map, then build result
        # skipping that slot (pre-sized array avoids realloc).
        all_section, url_index = cached_section_pages_with_index(current_section, page.language, site)
        skip_idx = url_index[page.url]?
        section_pages_array = if skip_idx
                                arr = Array(Crinja::Value).new(all_section.size - 1)
                                all_section.each_with_index { |v, i| arr << v unless i == skip_idx }
                                arr
                              else
                                # NOTE: This is the cached array from @section_pages_crinja_cache.
                                # Safe because downstream only wraps it in Crinja::Value (read-only).
                                # Do NOT mutate (sort!, push, delete, etc.) — it would corrupt the cache.
                                all_section
                              end
      end
    end
    vars["section_title"] = Crinja::Value.new(section_title)
    vars["section_description"] = Crinja::Value.new(section_description)

    # Section object with structured access
    # - section.title, section.description, section.pages (for iteration)
    # - section.list (HTML string, same as section_list for convenience)
    section_obj = {
      "title"       => Crinja::Value.new(section_title),
      "description" => Crinja::Value.new(section_description),
      "pages"       => Crinja::Value.new(section_pages_array),
      "pages_count" => Crinja::Value.new(section_pages_array.size),
      "list"        => Crinja::Value.new(section_list),
      # New section properties
      "subsections"   => Crinja::Value.new(subsections_array),
      "assets"        => section_assets_val,
      "page_template" => Crinja::Value.new(page_template_var),
      "paginate_path" => Crinja::Value.new(paginate_path_var),
      "redirect_to"   => Crinja::Value.new(redirect_to_var),
    }
    vars["section"] = Crinja::Value.new(section_obj)

    # Content and layout variables
    vars["content"] = Crinja::Value.new(content)
    vars["section_list"] = Crinja::Value.new(section_list)

    # TOC variables - both flat and structured access
    # - toc (HTML string for backward compatibility)
    # - toc_obj.html (same HTML in structured form)
    # - toc_obj.headers (array of structured header objects for custom rendering)
    vars["toc"] = Crinja::Value.new(toc)
    toc_obj = {
      "html"    => Crinja::Value.new(toc),
      "headers" => Crinja::Value.new(toc_headers_to_crinja(toc_headers)),
    }
    vars["toc_obj"] = Crinja::Value.new(toc_obj)

    vars["pagination"] = Crinja::Value.new(pagination)
    vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)

    if paginator
      # Reuse section_pages_array already built above for paginator.pages
      paginator_obj = {
        "paginate_by"   => Crinja::Value.new(paginator.per_page),
        "base_url"      => Crinja::Value.new(paginator.base_url),
        "number_pagers" => Crinja::Value.new(paginator.total_pages),
        "first"         => Crinja::Value.new(paginator.first_url),
        "last"          => Crinja::Value.new(paginator.last_url),
        "previous"      => Crinja::Value.new(paginator.prev_url),
        "next"          => Crinja::Value.new(paginator.next_url),
        "pages"         => Crinja::Value.new(section_pages_array),
        "current_index" => Crinja::Value.new(paginator.page_number),
        "total_pages"   => Crinja::Value.new(paginator.total_pages),
      }
      vars["paginator"] = Crinja::Value.new(paginator_obj)

      # Structured pagination object for custom markup in themes
      # Allows: {{ pagination_obj.previous_url }}, {{ pagination_obj.current_page }}, etc.
      pagination_obj_hash = {
        "html"         => Crinja::Value.new(pagination),
        "previous_url" => Crinja::Value.new(paginator.has_prev ? (paginator.prev_url || "") : ""),
        "next_url"     => Crinja::Value.new(paginator.has_next ? (paginator.next_url || "") : ""),
        "first_url"    => Crinja::Value.new(paginator.first_url),
        "last_url"     => Crinja::Value.new(paginator.last_url),
        "current_page" => Crinja::Value.new(paginator.page_number),
        "total_pages"  => Crinja::Value.new(paginator.total_pages),
        "total_items"  => Crinja::Value.new(paginator.total_items),
        "per_page"     => Crinja::Value.new(paginator.per_page),
        "has_previous" => Crinja::Value.new(paginator.has_prev),
        "has_next"     => Crinja::Value.new(paginator.has_next),
      }
      vars["pagination_obj"] = Crinja::Value.new(pagination_obj_hash)
    end

    # NOTE: highlight_css/js/tags and auto_includes_css/js are now in
    # global_vars (computed once in build_global_vars).

    # OG/Twitter tags (page-specific — depend on page title/description/url/image).
    # og_type_override stays unconditional: the JSON-LD block below reads it.
    og_type_override = og_type_for(page, effective_url)
    if features.nil? || features.needs_seo
      # Fall back to the site title when the page itself has no title — most
      # often the homepage, where authors deliberately leave `title = ""` so
      # the section/page heading doesn't duplicate the site name. Without
      # this fallback, og:title and twitter:title render as `content=""`,
      # which breaks link previews (gh issue list, fix #1).
      effective_og_title = page.title.empty? ? config.title : page.title

      # Use page.description if present, otherwise a plain-text rendering of
      # the `<!-- more -->` summary, finally fall back to site description.
      # `plain_summary` strips markup so raw markdown (headings, code fences,
      # literal newlines) never breaks the single-line meta attribute — using
      # `page.summary` directly here dumped the raw chunk into og/twitter
      # tags (gh#491). This gives social cards good per-post text without
      # requiring every author to write a description in frontmatter.
      effective_og_desc = page.description.presence || page.plain_summary || config.description

      og_tags = config.og.og_tags(effective_og_title, effective_og_desc, effective_url, page.image, config.base_url, og_type_override)
      twitter_tags = config.og.twitter_tags(effective_og_title, effective_og_desc, page.image, config.base_url)
      # Mirror the 2-space indent used inside og_tags/twitter_tags so the
      # joined block stays vertically aligned in the rendered HTML.
      og_all_tags = if og_tags.empty?
                      twitter_tags
                    elsif twitter_tags.empty?
                      og_tags
                    else
                      "#{og_tags}\n  #{twitter_tags}"
                    end
      vars["og_tags"] = Crinja::Value.new(og_tags)
      vars["twitter_tags"] = Crinja::Value.new(twitter_tags)
      vars["og_all_tags"] = Crinja::Value.new(og_all_tags)

      # Canonical and Hreflang tags. Pass page_url_override so paginated pages
      # (page/2/ …) self-canonicalize instead of all pointing at page 1, keeping
      # canonical consistent with og:url and rel=prev/next.
      # Older docs versions canonicalize to their LATEST counterpart when it
      # exists (self otherwise) and, with `noindex_old`, carry a robots
      # noindex — appended to `canonical_tag` so every template that emits
      # the canonical gets it without a new variable. A paginated override
      # keeps self-canonicalizing (page/2/ of an old listing is not page/2/
      # of the new one).
      canonical_override = page_url_override
      noindex = false
      if versions_enabled && (page_version = page.version) && !page_version.latest
        if canonical_override.nil? && (latest_link = page.version_links.find { |l| l.latest && l.exists })
          canonical_override = latest_link.url
        end
        noindex = config.versions.noindex_old
      end
      canonical_tag = Content::Seo::Tags.canonical_tag(page, config, canonical_override)
      canonical_tag = "#{canonical_tag}\n  #{Content::Seo::Tags::NOINDEX_TAG}" if noindex
      hreflang_tags = Content::Seo::Tags.hreflang_tags(page, config)
      vars["canonical_tag"] = Crinja::Value.new(canonical_tag)
      vars["hreflang_tags"] = Crinja::Value.new(hreflang_tags)

      # Sibling output-format alternate links (rel=alternate) — one per
      # enabled format (see `[outputs]`), empty when this page has none.
      vars["alternate_output_tags"] = Crinja::Value.new(alternate_output_tags(page, config))

      # Structured SEO object for custom meta tag markup
      canonical_url = Content::Seo::Tags.canonical_url(page, config, canonical_override)
      seo_image = config.og.resolve_image_url(page.image, config.base_url) || ""
      seo_obj = {
        "canonical_url"   => Crinja::Value.new(canonical_url),
        "og_type"         => Crinja::Value.new(og_type_override || config.og.og_type),
        "og_image"        => Crinja::Value.new(seo_image),
        "twitter_card"    => Crinja::Value.new(config.og.twitter_card),
        "twitter_site"    => Crinja::Value.new(config.og.twitter_site || ""),
        "twitter_creator" => Crinja::Value.new(config.og.twitter_creator || ""),
        "fb_app_id"       => Crinja::Value.new(config.og.fb_app_id || ""),
        "hreflang"        => translations_crinja,
      }
      seo_obj["noindex"] = Crinja::Value.new(noindex) if versions_enabled
      vars["seo"] = Crinja::Value.new(seo_obj)
    end

    # JSON-LD structured data.
    #
    # The homepage is a WebSite, not an Article — and because the scaffold
    # homepage ships an empty title, emitting an Article there produced an
    # invalid empty `headline`. Use the WebSite schema for the homepage, and
    # for any other untitled page skip the Article entirely rather than emit
    # one with an empty headline.
    if features.nil? || features.needs_jsonld
      build_jsonld_vars(vars, page, site, config, page_url_override, og_type_override)
    end

    # Merge global vars at the end.  Page-specific keys (written above)
    # take precedence because they were set first; merge! only adds keys
    # that don't already exist when we reverse the direction below.
    gv = global_vars || build_global_vars(site)
    gv.each { |k, v| vars[k] = v unless vars.has_key?(k) }

    # Per-fence copy opt-in probe — NOTE: for pages WITH shortcodes this
    # hash is built as the shortcode pre-render context with content="",
    # so apply_template re-runs the probe against the FINAL rendered
    # content (see inject_per_fence_copy_runtime).
    inject_per_fence_copy_runtime(vars, config, content)

    vars
  end

  # Per-fence copy opt-in (`{copy=true}`) with the global `[highlight]
  # copy` default off: the site-wide `highlight_js` (computed once in
  # build_global_vars) ships no copy runtime, so a page whose rendered
  # body carries an opted-in block appends it here — after the global-vars
  # merge, so the page-level value wins. The probe can't false-positive on
  # fenced documentation examples: the escape pipeline turns their `"` into
  # `&quot;`. With the global flag ON the runtime is already in the global
  # vars. Idempotent: a hash that already carries the snippet (a prebuilt
  # vars hash reused across passes) is left untouched.
  private def inject_per_fence_copy_runtime(
    vars : Hash(String, Crinja::Value),
    config : Models::Config,
    content : String,
  ) : Nil
    return if !config.highlight.enabled || config.highlight.copy
    return unless content.includes?(%(data-copy="true"))
    snippet = Models::HighlightConfig::COPY_SNIPPET
    base_js = vars["highlight_js"]?.try(&.raw).as?(String) || ""
    return if base_js.includes?(snippet)
    js = base_js.empty? ? snippet : "#{base_js}\n#{snippet}"
    vars["highlight_js"] = Crinja::Value.new(js)
    base_css = vars["highlight_css"]?.try(&.raw).as?(String) || ""
    vars["highlight_tags"] = Crinja::Value.new(base_css.empty? ? js : "#{base_css}\n#{js}")
  end
end
