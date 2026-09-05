# Render phase — site-wide template variables.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Public accessor so callers that render many pages through one Builder
  # (e.g. taxonomy generation) can compute the shared, site-wide template vars
  # ONCE and thread them into apply_template, instead of rebuilding the whole
  # set — iterating every page/section and re-hashing static assets — per page.
  # The Render phase's global template vars when this builder already computed
  # them (also reused by the Write phase's 404 page), otherwise built fresh.
  # NOTE: the render-phase vars honor the run's cache_busting option, which
  # the old fresh-Builder taxonomy path silently ignored (always true) —
  # taxonomy pages now match the rest of the build under --no-cache-busting.
  def render_global_vars_or_build(site : Models::Site) : Hash(String, Crinja::Value)
    @render_global_vars || global_template_vars(site)
  end

  def global_template_vars(site : Models::Site, cache_busting : Bool = true) : Hash(String, Crinja::Value)
    build_global_vars(site, cache_busting)
  end

  private def build_global_vars(site : Models::Site, cache_busting : Bool = true) : Hash(String, Crinja::Value)
    config = site.config
    vars = {} of String => Crinja::Value

    # Hidden variables for get_page/get_section/get_taxonomy functions
    # These are prefixed with __ to indicate they're internal
    default_lang = config.default_language
    all_pages_array = Array(Crinja::Value).new(site.pages.size)
    pages_by_path = Hash(String, Crinja::Value).new

    site.pages.each do |p|
      # Reuse cached per-page Crinja::Value to avoid redundant allocations
      # (same cache is used by section page lists and paginator)
      page_val = cached_page_crinja_value(p, default_lang)
      all_pages_array << page_val

      # Build O(1) lookup map
      # Use ||= to preserve first-match behavior (consistent with linear search)
      pages_by_path[p.path] ||= page_val
      pages_by_path[p.url] ||= page_val

      # Handle URL without trailing slash for flexible matching
      if p.url.ends_with?("/") && p.url.size > 1
        pages_by_path[p.url.rstrip("/")] ||= page_val
      end
    end

    vars["__all_pages__"] = Crinja::Value.new(all_pages_array)
    vars["__pages_by_path__"] = Crinja::Value.new(pages_by_path)

    all_sections_array = [] of Crinja::Value
    sections_by_key = {} of String => Crinja::Value

    # `Section#pages` is the model property and is *not* populated by the
    # build pipeline — it stays `[]`. The live page list lives in
    # `site.pages_for_section(name, language)`. Compute the page array
    # once per section so `get_section(...).pages` and `.pages_count`
    # match what `section.html` would render. Also stash the live result
    # so the second pass can copy `pages_count` into each parent's
    # subsection entry.
    section_data_by_path = {} of String => {pages: Array(Crinja::Value), hash: Hash(String, Crinja::Value)}

    site.sections.each do |s|
      # Reuse the sorted-per-sort_by cached list so `get_section(...).pages`
      # returns the same order as `section.pages` inside section templates —
      # the raw `pages_for_section` list is discovery-ordered, which made a
      # homepage "featured" loop disagree with the section listing.
      section_pages = cached_section_pages_crinja(s.section, s.language, site)
      hash = {
        "path"               => Crinja::Value.new(s.path),
        "name"               => Crinja::Value.new(s.section),
        "top_level"          => Crinja::Value.new(!s.section.includes?("/")),
        "title"              => Crinja::Value.new(s.title),
        "description"        => Crinja::Value.new(s.description || ""),
        "url"                => Crinja::Value.new(s.url),
        "date"               => Crinja::Value.new(s.date.try(&.to_s("%Y-%m-%d")) || ""),
        "draft"              => Crinja::Value.new(s.draft),
        "is_index"           => Crinja::Value.new(s.is_index),
        "language"           => Crinja::Value.new(s.language || default_lang),
        "weight"             => Crinja::Value.new(s.weight),
        "transparent"        => Crinja::Value.new(s.transparent),
        "sort_by"            => Crinja::Value.new(s.sort_by || ""),
        "reverse"            => Crinja::Value.new(s.reverse || false),
        "paginate"           => Crinja::Value.new(s.paginate || 0),
        "pagination_enabled" => Crinja::Value.new(s.pagination_enabled),
        "pages"              => Crinja::Value.new(section_pages),
        "pages_count"        => Crinja::Value.new(section_pages.size),
        "assets"             => Crinja::Value.new(s.assets.map { |a| Crinja::Value.new(a) }),
        "subsections"        => Crinja::Value.new([] of Crinja::Value),
      } of String => Crinja::Value
      hash["version"] = Content::Versions.page_version_value(s, config) if config.versions.enabled?
      section_val = Crinja::Value.new(hash)
      section_data_by_path[s.path] = {pages: section_pages, hash: hash}
      all_sections_array << section_val

      # Build O(1) lookup map for get_section() — match by path, name, and URL
      sections_by_key[s.path] ||= section_val
      sections_by_key[s.section] ||= section_val unless s.section.empty?
      sections_by_key[s.url] ||= section_val
    end

    # Second pass: link each section's `subsections` to its children so
    # `get_section("posts").subsections` returns the same data shape as
    # the parent. Iterates `site.sections` (not `site.pages`) because
    # only Section objects carry the `subsections` chain.
    site.sections.each do |s|
      next if s.subsections.empty?
      data = section_data_by_path[s.path]?
      next unless data
      subs_array = data[:hash]["subsections"].raw.as(Array)
      s.subsections.each do |child|
        if child_data = section_data_by_path[child.path]?
          subs_array << Crinja::Value.new(child_data[:hash])
        end
      end
    end

    vars["__all_sections__"] = Crinja::Value.new(all_sections_array)
    vars["__sections_by_key__"] = Crinja::Value.new(sections_by_key)

    # Build taxonomies hash for get_taxonomy function. Term slugs are
    # disambiguated with the SAME helper the taxonomy generator uses, so a
    # collision (e.g. "C++"/"C#" → "c") yields unique slugs that match the
    # written term-page paths. __taxonomy_slugs__ exposes the term→slug map so
    # get_taxonomy_url() can resolve a single term without recomputing the map.
    multilingual = config.multilingual?
    taxonomies_hash = {} of String => Crinja::Value
    taxonomy_slugs = {} of String => Crinja::Value
    # {language => {taxonomy => {term => slug}}} for the LANGUAGE-PREFIXED term
    # pages (`/ko/tags/foo/`) the taxonomy generator writes for every non-default
    # language that enables the taxonomy. Without this, `get_taxonomy_url` on a
    # Korean page emitted the root `/tags/foo/` — which for a term that appears
    # only in Korean content was never written at all (a hard 404 on the built-in
    # blog scaffold's tag pills), and for a shared term pointed readers at the
    # English listing. Only populated for languages that actually enable the
    # taxonomy, so the lookup can never invent a page the generator skipped.
    taxonomy_lang_slugs = {} of String => Crinja::Value
    lang_taxonomy_names = {} of String => Array(String)
    if multilingual
      config.languages.each do |code, lang_cfg|
        next if code == default_lang
        next if lang_cfg.taxonomies.empty?
        lang_taxonomy_names[code] = lang_cfg.taxonomies
      end
    end
    # Accumulated as plain hashes and converted to Crinja::Value once at the end —
    # round-tripping through Crinja::Value per insert would re-wrap the inner hash
    # each time and keep only the last term.
    lang_slug_maps = {} of String => Hash(String, Hash(String, String))
    site.taxonomies.each do |name, terms|
      # Disambiguate over the SAME term set the taxonomy generator uses to write
      # pages — build_taxonomy_index counts only non-draft, non-generated pages.
      # Under `--drafts`, the render-phase site.taxonomies (rebuild_taxonomies)
      # also carries draft-only terms; including them here would let a draft term
      # steal a base slug and shift a published term to a `-N` slug the generator
      # never wrote, breaking its get_taxonomy link. Normal builds are already
      # draft-free, so this filter is a no-op there.
      written_terms = terms.compact_map do |term, term_pages|
        term if term_pages.any? { |p| !p.draft && !p.generated }
      end
      slug_map = Utils::TextUtils.disambiguated_slugs(written_terms)
      term_slug_values = {} of String => Crinja::Value
      # Term order matches the taxonomy's `terms_sort_by` as the ROOT index
      # page applies it: "name" = alphabetical (also the default for
      # unconfigured taxonomy names), "count" = page count descending,
      # name-ascending tiebreak. Counts here are site-wide (all languages,
      # like the root index); per-language index pages sort by their own
      # language-filtered counts and may order differently — get_taxonomy
      # is a site-wide view, so the root rule is the right parity target.
      tax_cfg = config.taxonomies.find { |t| t.name == name }
      sorted_term_names = if tax_cfg.try(&.terms_sort_by) == "count"
                            terms.keys.sort! do |a, b|
                              cmp = terms[b].size <=> terms[a].size
                              cmp == 0 ? (a <=> b) : cmp
                            end
                          else
                            terms.keys.sort!
                          end
      terms_array = sorted_term_names.map do |term|
        term_pages = terms[term]
        term_pages_array = term_pages.map do |tp|
          cached_page_crinja_value(tp, default_lang)
        end
        # A ROOT term page (what get_taxonomy_url targets) is written only when
        # the term has a non-draft page in the default language; on a
        # multilingual site a term that exists only in a non-default language
        # gets no root page, so exposing its disambiguated `-N` slug would point
        # at a 404. Only publish disambiguated slugs for terms with a root page;
        # others fall back to safe_slugify (the pre-centralization behavior).
        has_root = term_pages.any? do |p|
          next false if p.draft || p.generated
          !multilingual || (p.language || default_lang) == default_lang
        end
        slug = (has_root ? slug_map[term]? : nil) || Utils::TextUtils.safe_slugify(term)
        term_slug_values[term] = Crinja::Value.new(slug) if has_root

        # Record the term under every non-default language that (a) enables this
        # taxonomy and (b) has a publishable page carrying the term — exactly the
        # two conditions under which generate_taxonomies_for_language writes
        # `/<lang>/<taxonomy>/<slug>/`. The generator disambiguates over the same
        # term set, so `slug_map[term]` is the slug it used.
        unless lang_taxonomy_names.empty?
          lang_taxonomy_names.each do |code, names|
            next unless names.includes?(name)
            next unless term_pages.any? do |p|
                          !p.draft && !p.generated && (p.language || default_lang) == code
                        end
            per_lang = lang_slug_maps[code] ||= {} of String => Hash(String, String)
            tax_map = per_lang[name] ||= {} of String => String
            tax_map[term] = slug_map[term]? || slug
          end
        end
        Crinja::Value.new({
          "name"  => Crinja::Value.new(term),
          "slug"  => Crinja::Value.new(slug),
          "pages" => Crinja::Value.new(term_pages_array),
          "count" => Crinja::Value.new(term_pages.size),
        })
      end
      taxonomies_hash[name] = Crinja::Value.new({
        "name"  => Crinja::Value.new(name),
        "items" => Crinja::Value.new(terms_array),
      })
      taxonomy_slugs[name] = Crinja::Value.new(term_slug_values)
    end
    lang_slug_maps.each do |code, per_lang|
      tax_values = {} of String => Crinja::Value
      per_lang.each do |tax_name, term_slugs|
        term_values = {} of String => Crinja::Value
        term_slugs.each { |term, s| term_values[term] = Crinja::Value.new(s) }
        tax_values[tax_name] = Crinja::Value.new(term_values)
      end
      taxonomy_lang_slugs[code] = Crinja::Value.new(tax_values)
    end
    vars["__taxonomies__"] = Crinja::Value.new(taxonomies_hash)
    vars["__taxonomy_slugs__"] = Crinja::Value.new(taxonomy_slugs)
    vars["__taxonomy_lang_slugs__"] = Crinja::Value.new(taxonomy_lang_slugs)

    # Menus: config [[menus.*]]-declared entries + front-matter menus/menu
    # registrations, resolved into one tree per language. `__menus__` backs
    # `get_menu()` (template.cr), which picks the CURRENT page's language
    # with a default-language fallback; `site.menus` below is always the
    # default language's set (site_obj has no per-page language context).
    menus_by_lang = Content::Menus.build(config, site.pages, site.sections)
    menus_crinja = {} of String => Crinja::Value
    menus_by_lang.each do |lang, menus|
      lang_hash = {} of String => Crinja::Value
      menus.each do |menu_name, entries|
        lang_hash[menu_name] = Crinja::Value.new(entries.map { |e| menu_entry_to_crinja(e, config, pages_by_path) })
      end
      menus_crinja[lang] = Crinja::Value.new(lang_hash)
    end
    vars["__menus__"] = Crinja::Value.new(menus_crinja)

    # Per-version menu sets ({version name => {lang => menus}}) for pages
    # inside a `[[versions.list]]` directory — get_menu picks the set named
    # by `page_version`. Only built on versioned sites.
    if config.versions.enabled?
      menus_by_version = {} of String => Crinja::Value
      config.versions.list.each do |version|
        per_lang = {} of String => Crinja::Value
        Content::Menus.build(config, site.pages, site.sections, version).each do |lang, menus|
          lang_hash = {} of String => Crinja::Value
          menus.each do |menu_name, entries|
            lang_hash[menu_name] = Crinja::Value.new(entries.map { |e| menu_entry_to_crinja(e, config, pages_by_path) })
          end
          per_lang[lang] = Crinja::Value.new(lang_hash)
        end
        menus_by_version[version.name] = Crinja::Value.new(per_lang)
      end
      vars["__menus_v__"] = Crinja::Value.new(menus_by_version)
    end

    # Site object with full data
    site_obj = {
      "title"       => Crinja::Value.new(config.title),
      "description" => Crinja::Value.new(config.description || ""),
      "base_url"    => Crinja::Value.new(config.base_url),
      "pages"       => Crinja::Value.new(all_pages_array),
      "sections"    => Crinja::Value.new(all_sections_array),
      "taxonomies"  => Crinja::Value.new(taxonomies_hash),
      "data"        => Crinja::Value.new(site.data),
      "authors"     => Crinja::Value.new(site.authors),
      "menus"       => menus_crinja[default_lang]? || Crinja::Value.new({} of String => Crinja::Value),
    }
    vars["site"] = Crinja::Value.new(site_obj)

    # Site-wide constant variables — computed once, shared across all pages
    # (These were previously recomputed in build_template_variables for every page)
    vars["site_title"] = Crinja::Value.new(config.title)
    vars["site_description"] = Crinja::Value.new(config.description || "")
    vars["base_url"] = Crinja::Value.new(config.base_url)

    # Cache busting (content hash of local CSS/JS files)
    cache_bust = cache_busting ? compute_cache_bust(config) : ""

    # Highlight tags
    vars["highlight_css"] = Crinja::Value.new(config.highlight.css_tag(cache_bust))
    vars["highlight_js"] = Crinja::Value.new(config.highlight.js_tag(cache_bust))
    vars["highlight_tags"] = Crinja::Value.new(config.highlight.tags(cache_bust))

    # `use_cdn = false` emits <script src="/assets/js/highlight.min.js"> (+ css),
    # but Hwaro doesn't ship those files — if the user hasn't placed them under
    # static/assets/ the references 404 and highlighting silently breaks. Warn
    # once per build (build_global_vars runs once) so it isn't a silent footgun.
    warn_missing_local_highlight_assets(config)

    # Math (KaTeX/MathJax) and Mermaid renderer scripts. When `math = true`
    # or `mermaid = true` is set in config, the markdown processor emits the
    # right wrapper markup but without these script tags the browser sees
    # only literal TeX / DOT source. Templates can pull them in via
    # `{{ math_tags }}` and `{{ mermaid_tags }}`; the default header partials
    # include them so the feature flags work out of the box.
    vars["math_tags"] = Crinja::Value.new(config.markdown.math_tags)
    vars["mermaid_tags"] = Crinja::Value.new(config.markdown.mermaid_tags)

    # PWA wiring. `[pwa] enabled = true` writes manifest.json + sw.js into
    # the output, but neither does anything until a page links the manifest
    # and registers the service worker. `{{ pwa_tags }}` carries both (plus
    # a theme-color meta); it resolves to "" while [pwa] is disabled, so
    # headers can include it unconditionally — same contract as math_tags.
    vars["pwa_tags"] = Crinja::Value.new(pwa_tags(config))

    # Auto includes
    vars["auto_includes_css"] = Crinja::Value.new(config.auto_includes.css_tags(config.base_url, cache_bust))
    vars["auto_includes_js"] = Crinja::Value.new(config.auto_includes.js_tags(config.base_url, cache_bust))
    vars["auto_includes"] = Crinja::Value.new(config.auto_includes.all_tags(config.base_url, cache_bust))

    # JSON-LD: site-wide WebSite and Organization schemas
    vars["jsonld_website"] = Crinja::Value.new(Content::Seo::JsonLd.website(config))
    vars["jsonld_organization"] = Crinja::Value.new(Content::Seo::JsonLd.organization(config, config.og.default_image))

    # Time-related variables (fixed per build, not per page)
    now = Time.local
    vars["current_year"] = Crinja::Value.new(now.year)
    vars["current_date"] = Crinja::Value.new(now.to_s("%Y-%m-%d"))
    vars["current_datetime"] = Crinja::Value.new(now.to_s("%Y-%m-%d %H:%M:%S"))

    # i18n translations (available to {{ "key" | t }} filter)
    unless @i18n_translations.empty?
      i18n_hash = {} of Crinja::Value => Crinja::Value
      @i18n_translations.each do |lang, entries|
        entries_hash = {} of Crinja::Value => Crinja::Value
        entries.each do |key, value|
          entries_hash[Crinja::Value.new(key)] = Crinja::Value.new(value)
        end
        i18n_hash[Crinja::Value.new(lang)] = Crinja::Value.new(entries_hash)
      end
      vars["_i18n_translations"] = Crinja::Value.new(i18n_hash)
    end
    vars["_i18n_default_language"] = Crinja::Value.new(config.default_language)

    vars
  end

  # Converts a resolved menu `Entry` (see `Content::Menus`) to the Crinja
  # hash templates iterate over: `{name, url, href, identifier, weight,
  # external, children, page}`. `href` is `with_base_path(url)` for internal
  # entries (so links work under a subpath deploy) and the untouched `url`
  # for external ones; `url` itself stays bare and root-relative so it's
  # directly comparable to `page.url` (see the `active_path` filter).
  # `page` resolves the entry's registering page/section via the SAME
  # `__pages_by_path__` map `get_page`/internal-link-resolution use — a
  # section's `_index.md` isn't in that map (it's page-only), so a menu
  # entry registered on a section resolves `page` to `nil`.
  private def menu_entry_to_crinja(entry : Content::Menus::Entry, config : Models::Config, pages_by_path : Hash(String, Crinja::Value)) : Crinja::Value
    page_value = entry.page_path.try { |pp| pages_by_path[pp]? }
    Crinja::Value.new({
      "name"       => Crinja::Value.new(entry.name),
      "url"        => Crinja::Value.new(entry.url),
      "href"       => Crinja::Value.new(entry.external ? entry.url : config.with_base_path(entry.url)),
      "identifier" => Crinja::Value.new(entry.identifier),
      "weight"     => Crinja::Value.new(entry.weight),
      "external"   => Crinja::Value.new(entry.external),
      "children"   => Crinja::Value.new(entry.children.map { |c| menu_entry_to_crinja(c, config, pages_by_path) }),
      "page"       => page_value || Crinja::Value.new(nil),
    })
  end
end
