# Render phase — cached Crinja values for pages, sections and ancestors.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Unified Page→Crinja::Value conversion with per-page caching.
  # Avoids repeated conversion of the same Page across build_global_vars,
  # section page lists, and paginator rendering.  The cached value contains
  # a superset of fields needed by all consumers.
  private def cached_page_crinja_value(p : Models::Page, default_language : String) : Crinja::Value
    if @crinja_caches_frozen
      if cached = @page_crinja_value_cache[p.path]?
        @cache_manager.record_hit("page_crinja_value")
        return cached
      end
      # Rare by construction (prewarm covers every page the fan-out reads):
      # compute without caching — writing here would race other readers.
      @cache_manager.record_miss("page_crinja_value")
      return build_page_crinja_value(p, default_language)
    end

    @crinja_cache_mutex.synchronize do
      if cached = @page_crinja_value_cache[p.path]?
        @cache_manager.record_hit("page_crinja_value")
        next cached.as(Crinja::Value)
      end
      @cache_manager.record_miss("page_crinja_value")
      val = build_page_crinja_value(p, default_language)
      @page_crinja_value_cache[p.path] = val
      val
    end
  end

  private def build_page_crinja_value(p : Models::Page, default_language : String) : Crinja::Value
    translations = p.translations.map do |t|
      Crinja::Value.new({
        "code"       => Crinja::Value.new(t.code),
        "url"        => Crinja::Value.new(t.url),
        "title"      => Crinja::Value.new(t.title),
        "is_current" => Crinja::Value.new(t.is_current),
        "is_default" => Crinja::Value.new(t.is_default),
      })
    end
    hash = {
      "path"              => Crinja::Value.new(p.path),
      "title"             => Crinja::Value.new(p.title),
      "description"       => Crinja::Value.new(p.description || ""),
      "url"               => Crinja::Value.new(p.url),
      "date"              => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
      "image"             => Crinja::Value.new(p.image || ""),
      "section"           => Crinja::Value.new(p.section),
      "draft"             => Crinja::Value.new(p.draft),
      "toc"               => Crinja::Value.new(p.toc),
      "render"            => Crinja::Value.new(p.render),
      "is_index"          => Crinja::Value.new(p.is_index),
      "generated"         => Crinja::Value.new(p.generated),
      "synthesized"       => Crinja::Value.new(p.synthesized?),
      "in_sitemap"        => Crinja::Value.new(p.in_sitemap),
      "language"          => Crinja::Value.new(p.language || default_language),
      "translations"      => Crinja::Value.new(translations),
      "weight"            => Crinja::Value.new(p.weight),
      "summary"           => Crinja::Value.new(p.summary_html || p.effective_summary || ""),
      "summary_truncated" => Crinja::Value.new(p.summary_truncated),
      "word_count"        => Crinja::Value.new(p.word_count),
      "reading_time"      => Crinja::Value.new(p.reading_time),
      # Leaf fields a full page_obj also exposes, so iterated lists
      # (section.pages / site.pages / term.pages) match the documented Page
      # shape. Only PAGE-LOCAL fields are cached here. `permalink` is omitted
      # (computed lazily per-page during render), and `series_index` is
      # omitted because it is recomputed from OTHER pages in the series — a
      # cross-page value @page_crinja_value_cache cannot keep fresh on the
      # incremental `serve` path, where only the changed page is invalidated.
      "updated"         => Crinja::Value.new(p.updated.try(&.to_s("%Y-%m-%d")) || ""),
      "git"             => git_crinja_for(p),
      "in_search_index" => Crinja::Value.new(p.in_search_index),
      "series"          => Crinja::Value.new(p.series || ""),
      "tags"            => Crinja::Value.new(p.tags.map { |t| Crinja::Value.new(t) }),
      "authors"         => Crinja::Value.new(p.authors.map { |a| Crinja::Value.new(a) }),
      "taxonomies"      => taxonomies_crinja_for(p),
      "assets"          => Crinja::Value.new(p.assets.map { |a| Crinja::Value.new(a) }),
      "extra"           => Crinja::Value.new(
        p.extra.each_with_object({} of String => Crinja::Value) { |(k, v), h|
          h[k] = Utils::CrinjaUtils.from_extra(v)
        }),
    } of String => Crinja::Value
    # `page.version` / `page.version_links` exist only on versioned sites
    # (`[[versions.list]]`), so unversioned page objects keep their exact
    # key set (a `page | tojson` dump stays byte-identical).
    if (cfg = @config) && cfg.versions.enabled?
      hash["version"] = Content::Versions.page_version_value(p, cfg)
      hash["version_links"] = Content::Versions.version_links_value(p)
    end
    Crinja::Value.new(hash)
  end

  # `page.git` as templates see it: a mapping of the commit fields, or nil
  # (renders empty, `{% if page.git %}` is false) when the page has no
  # history. `lastmod`/`first_commit` are Time values so `| date(format=…)`
  # formats them and comparisons work; their `to_s` keeps the author's
  # UTC offset.
  private def git_crinja_for(page : Models::Page) : Crinja::Value
    return Crinja::Value.new(nil) unless git = page.git
    Crinja::Value.new({
      "hash"         => Crinja::Value.new(git.hash),
      "short_hash"   => Crinja::Value.new(git.short_hash),
      "lastmod"      => Crinja::Value.new(git.lastmod),
      "first_commit" => Crinja::Value.new(git.first_commit),
      "author_name"  => Crinja::Value.new(git.author_name),
      "author_email" => Crinja::Value.new(git.author_email),
    })
  end

  private def build_ancestors_crinja(page : Models::Page) : Array(Crinja::Value)
    page.ancestors.map do |ancestor|
      Crinja::Value.new({
        "title" => Crinja::Value.new(ancestor.title),
        "url"   => Crinja::Value.new(ancestor.url),
      })
    end
  end

  # Fill every Crinja value cache the render fan-out can read, so the frozen
  # (mutex-free) fast paths never miss on a default build. build_global_vars
  # already converted every site page, taxonomy term page, and per-section
  # page list; this covers the remainder: the rendered pages themselves
  # (section objects are pages_to_build entries but not site.pages entries),
  # per-section ancestors and assets, series lists, and related posts.
  #
  # Runs single-threaded before the workers spawn, so it writes the caches
  # directly. Iterating pages in render order reproduces the sequential
  # first-writer-wins winner for the shared per-section keys — under MT the
  # old lazy fill was render-order racy; this makes it deterministic and
  # equal to the single-threaded result.
  private def prewarm_crinja_caches(site : Models::Site, pages : Array(Models::Page))
    default_lang = site.config.default_language

    pages.each do |page|
      cached_page_crinja_value(page, default_lang)

      # Member pages sharing {section, language} have identical ancestors,
      # so one cache entry serves them all. Section-index pages must NOT
      # share it: their ancestors exclude themselves (transform.cr), so a
      # shared key either put a section into its own breadcrumb or stripped
      # the section from every member page — whichever prewarmed first won.
      # Sections bypass the cache (see build_template_variables): each one
      # renders exactly once, so caching buys nothing.
      unless page.is_a?(Models::Section)
        ancestors_key = {page.section, page.language}
        unless @ancestors_crinja_cache.has_key?(ancestors_key)
          @ancestors_crinja_cache[ancestors_key] = build_ancestors_crinja(page)
        end
      end

      unless page.section.empty?
        # The shared per-section list + url index read by non-paginated pages.
        cached_section_pages_with_index(page.section, page.language, site)

        if !page.is_a?(Models::Section) && !@section_assets_crinja_cache.has_key?(page.section)
          if section_page = site.section_for(page.section, page.language)
            @section_assets_crinja_cache[page.section] = section_page.assets.map { |a| Crinja::Value.new(a) }
          end
        end
      end

      if series_name = page.series
        unless @series_crinja_cache.has_key?(series_name)
          @series_crinja_cache[series_name] = Crinja::Value.new(page.series_pages.map { |sp|
            cached_page_crinja_value(sp, default_lang)
          })
        end
      end

      unless page.related_posts.empty? || @related_posts_crinja_cache.has_key?(page.path)
        @related_posts_crinja_cache[page.path] = Crinja::Value.new(page.related_posts.map { |rp|
          cached_page_crinja_value(rp, default_lang)
        })
      end
    end
  end

  # Per-page taxonomy terms as `{ name => [terms] }` so templates can read
  # `page.taxonomies.tech` (or iterate `w.taxonomies.<name>` in section
  # lists). `tags`/`authors` live on dedicated model fields rather than in
  # `Page#taxonomies`, so mirror `taxonomy_values`' special-casing — an
  # explicit `[taxonomies] tags = […]` entry still wins.
  private def taxonomies_crinja_for(p : Models::Page) : Crinja::Value
    h = p.taxonomies.each_with_object({} of String => Crinja::Value) do |(k, v), acc|
      acc[k] = Crinja::Value.new(v.map { |t| Crinja::Value.new(t) })
    end
    h["tags"] = Crinja::Value.new(p.tags.map { |t| Crinja::Value.new(t) }) unless h.has_key?("tags")
    h["authors"] = Crinja::Value.new(p.authors.map { |a| Crinja::Value.new(a) }) unless h.has_key?("authors")
    Crinja::Value.new(h)
  end

  # Convert a Page to a Crinja::Value hash for use in section page lists and paginator.
  # Delegates to the cached unified conversion to avoid redundant allocations.
  private def page_to_crinja_list_value(p : Models::Page, default_language : String) : Crinja::Value
    cached_page_crinja_value(p, default_language)
  end

  # Get (or build and cache) the sorted Crinja::Value array for a section's pages.
  # The cache stores the full sorted list; callers should filter current_page themselves if needed.
  private def cached_section_pages_crinja(
    section_name : String,
    language : String?,
    site : Models::Site,
  ) : Array(Crinja::Value)
    cache_key = {section_name, language}
    if @crinja_caches_frozen
      if cached = @section_pages_crinja_cache[cache_key]?
        @cache_manager.record_hit("section_pages_crinja")
        return cached
      end
      @cache_manager.record_miss("section_pages_crinja")
      return build_section_pages_crinja(section_name, language, site)
    end

    @crinja_cache_mutex.synchronize do
      if cached = @section_pages_crinja_cache[cache_key]?
        @cache_manager.record_hit("section_pages_crinja")
        next cached.as(Array(Crinja::Value))
      end
      @cache_manager.record_miss("section_pages_crinja")
      arr = build_section_pages_crinja(section_name, language, site)
      @section_pages_crinja_cache[cache_key] = arr
      @section_pages_url_index_cache[cache_key] = build_section_pages_url_index(arr)
      arr
    end
  end

  private def build_section_pages_crinja(
    section_name : String,
    language : String?,
    site : Models::Site,
  ) : Array(Crinja::Value)
    pages = site.pages_for_section(section_name, language)

    # Use section's sort_by setting if available, otherwise sort by date
    # (newest first) — the SAME default the paginator (paginator.cr) and the
    # prev/next navigation (transform.cr) use, and the one the docs promise.
    # A "title" fallback here made `get_section(...).pages` and member-page
    # `section.pages` disagree with the section template's own listing order.
    section = site.section_for(section_name, language)
    sort_by = section.try(&.sort_by) || "date"
    reverse = section.try(&.reverse) || false
    pages = Utils::SortUtils.sort_pages(pages, sort_by, reverse)

    default_lang = site.config.default_language
    pages.map { |p| page_to_crinja_list_value(p, default_lang) }
  end

  # The cached section list plus its url→index map, for O(1) current-page
  # exclusion. Both caches are filled and invalidated together under
  # @crinja_cache_mutex (reentrant), so the index is rebuilt here only as
  # a defensive fallback.
  private def cached_section_pages_with_index(
    section_name : String,
    language : String?,
    site : Models::Site,
  ) : {Array(Crinja::Value), Hash(String, Int32)}
    cache_key = {section_name, language}
    if @crinja_caches_frozen
      arr = cached_section_pages_crinja(section_name, language, site)
      if index = @section_pages_url_index_cache[cache_key]?
        return {arr, index}
      end
      return {arr, build_section_pages_url_index(arr)}
    end

    @crinja_cache_mutex.synchronize do
      arr = cached_section_pages_crinja(section_name, language, site)
      index = @section_pages_url_index_cache[cache_key]?
      unless index
        index = build_section_pages_url_index(arr)
        @section_pages_url_index_cache[cache_key] = index
      end
      {arr, index}
    end
  end

  # First occurrence wins, mirroring the Array#index scan this replaces.
  private def build_section_pages_url_index(pages : Array(Crinja::Value)) : Hash(String, Int32)
    index = Hash(String, Int32).new(initial_capacity: pages.size)
    pages.each_with_index do |value, i|
      raw = value.raw
      next unless raw.is_a?(Hash)
      if url = raw["url"]?
        key = url.to_s
        index[key] = i unless index.has_key?(key)
      end
    end
    index
  end

  # Build a lookup map from content path → Page for internal link resolution.
  private def build_pages_by_path(site : Models::Site) : Hash(String, Models::Page)
    map = {} of String => Models::Page
    site.pages.each { |p| map[p.path] ||= p }
    site.sections.each { |s| map[s.path] ||= s }
    map
  end
end
