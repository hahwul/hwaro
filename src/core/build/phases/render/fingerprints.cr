# Render phase — incremental-build fingerprints (page/section sets, template hashes, cache entries).
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Markers in a page's resolved template closure that mean it renders content
  # derived from the global page/section set, so it must re-render when that set
  # changes (not only when its own source changes).
  PAGE_SET_MARKERS    = ["site.pages", "__all_pages__", ".pages", "paginate", "site.taxonomies", "__taxonomies__", "get_taxonomy", "site.menus", "get_menu", "__menus__", "version_links", "versions"]
  SECTION_SET_MARKERS = ["site.sections", "__all_sections__", "get_section", "site.menus", "get_menu", "__menus__"]

  # The same markers split into the PROJECTIONS of the page set they actually
  # read. `filter_changed_pages` already distinguishes two (pages vs
  # sections); the serve watch path needs it finer.
  #
  # Why only there: a nav partial in the shared base layout puts `get_menu` in
  # EVERY page's closure, and `{{ get_taxonomy_url(...) }}` tag pills put
  # `get_taxonomy` in every post's. Gating those on the BROAD page-set digest
  # answers "re-render the whole site" for any metadata edit — fine for a
  # cached full build, which re-renders the union anyway, and fatal for a dev
  # server's save→reload loop. Each class below is paired with a digest of
  # exactly what it reads (see compute_menu_set_fingerprint /
  # compute_taxonomy_slug_fingerprint), so a nav only re-renders when a menu
  # entry moves and a tag pill only when the term set does.
  MENU_SET_MARKERS = ["site.menus", "get_menu", "__menus__"]
  # `get_taxonomy_url(kind:, term:)` resolves one term→slug from the
  # disambiguated map; it never touches a term's pages. `get_taxonomy` does,
  # which is why the lookahead keeps them apart — plain `includes?` cannot,
  # since one name is a prefix of the other.
  TAXONOMY_URL_MARKER = "get_taxonomy_url"
  GET_TAXONOMY_RE     = /get_taxonomy(?!_url)/

  LISTING_PAGE_MARKERS    = PAGE_SET_MARKERS - MENU_SET_MARKERS
  LISTING_SECTION_MARKERS = SECTION_SET_MARKERS - MENU_SET_MARKERS

  # `get_page(path="about.md")` reads ONE other page. With a literal path
  # that page is known up front, so a reader depends on it alone (the
  # per-page relations hash on `--cache`, the lookup projection in serve)
  # rather than on the whole page set — a footer printing the about page's
  # title sits in every page's closure. A call whose argument is not a
  # literal can read any page, and only that falls back to the page-set gate.
  GET_PAGE_CALL_RE    = /\bget_page\s*\(/
  GET_PAGE_LITERAL_RE = /\bget_page\s*\(\s*(?:path\s*=\s*)?(?:"([^"]*)"|'([^']*)')\s*\)/

  # Which page-set projections one page's template closure reads.
  record ListingSetDeps,
    page : Bool,
    section : Bool,
    menu : Bool,
    taxonomy_slug : Bool,
    lookup : Bool

  # Projection scan of one closure source blob for the serve fan-out. Same
  # closure (and same tracking-off fallback) as `listing_template_deps`,
  # split by projection — see the marker constants above.
  private def listing_set_deps_for(blob : String) : ListingSetDeps
    ListingSetDeps.new(
      page: LISTING_PAGE_MARKERS.any? do |marker|
        marker == "get_taxonomy" ? GET_TAXONOMY_RE.matches?(blob) : blob.includes?(marker)
      end || dynamic_get_page?(blob),
      section: LISTING_SECTION_MARKERS.any? { |marker| blob.includes?(marker) },
      menu: MENU_SET_MARKERS.any? { |marker| blob.includes?(marker) },
      taxonomy_slug: blob.includes?(TAXONOMY_URL_MARKER),
      lookup: !get_page_targets(blob).empty?,
    )
  end

  private def listing_closure_blob(entry_template : String, templates : Hash(String, String)) : String
    closure_blob([entry_template], templates)
  end

  # Source union of the closures of `roots`. With dependency tracking off,
  # every template.
  private def closure_blob(roots : Enumerable(String), templates : Hash(String, String)) : String
    deps = @template_deps
    return templates.values.join("\n") unless deps
    names = Set(String).new
    roots.each { |root| names.concat(deps.closure(root)) }
    names.compact_map { |n| templates[n]? }.join("\n")
  end

  # A `get_page` call whose argument is not a string literal: it can read
  # any page, so its template depends on the whole page set.
  private def dynamic_get_page?(blob : String) : Bool
    return false unless blob.includes?("get_page")
    blob.scan(GET_PAGE_CALL_RE).size > blob.scan(GET_PAGE_LITERAL_RE).size
  end

  # The literal `get_page` paths in a closure blob, sorted and unique.
  private def get_page_targets(blob : String) : Array(String)
    return [] of String unless blob.includes?("get_page")
    targets = [] of String
    blob.scan(GET_PAGE_LITERAL_RE) { |m| targets << (m[1]? || m[2]? || "") }
    targets.uniq!.sort!
  end

  # Template reads of a page's RELATIONS — values `build_template_variables`
  # takes from OTHER pages for this one: prev/next (`page.lower`/`.higher`),
  # the series list and position, related posts, the translation switcher
  # (`page.translations`, and the hreflang tags built from it) and the
  # breadcrumb (`page.ancestors`, and the JSON-LD breadcrumb built from it).
  # `.lower` is matched as an attribute so the `| lower` filter is not one.
  RELATION_NEIGHBOR_RE         = /\.(?:lower|higher)\b|\[\s*["'](?:lower|higher)["']\s*\]/
  RELATION_SERIES_MARKERS      = ["series_pages", "series_index"]
  RELATION_RELATED_MARKER      = "related_posts"
  RELATION_TRANSLATION_MARKERS = ["translations", "hreflang"]
  RELATION_ANCESTOR_MARKERS    = ["ancestors", "jsonld"]
  RELATION_BACKLINKS_MARKER    = "backlinks"

  # `@/path.md` internal links in raw content (Markdown destination, raw
  # `href="@/…"`, reference definition). Stops where the resolver's own
  # match stops (`#`, `?`, a quote) and at Markdown/HTML delimiters. An
  # angle-bracket destination (`<@/a b.md>`) may hold spaces and runs to its
  # `>` (group 1); the bare form is group 2.
  INTERNAL_LINK_TARGET_RE = /<@\/([^>\n#?]+)|@\/([^\s()"'#?<>\[\]]+)/

  # A content-derived field or `[extra]` read straight off a relation —
  # `page.higher.summary`, `get_page(path="x").extra.badge` — where the
  # receiver is an attribute or a call result, so the `<receiver>.<field>`
  # patterns above (which need a bare word receiver) cannot see it.
  CHAINED_CONTENT_DERIVED_RE = /(?:\.(?:lower|higher)|\))\s*(?:\.\s*(?:summary(?:_truncated)?|word_count|reading_time)\b|\[\s*["'](?:summary(?:_truncated)?|word_count|reading_time)["'])/
  CHAINED_EXTRA_RE           = /(?:\.(?:lower|higher)|\))\s*(?:\.\s*extra\b|\[\s*["']extra["'])/

  # Which relations one page's template closure reads (see the markers above),
  # and which optional page fields it reads off them (`fields`).
  record RelationDeps,
    neighbors : Bool,
    series : Bool,
    related : Bool,
    translations : Bool,
    ancestors : Bool,
    get_page_targets : Array(String),
    fields : Builder::ListingPageFields,
    # Folded only under `[content] backlinks` (see page_relations_hash),
    # so it stays out of `reads_any?`.
    backlinks : Bool = false do
    def reads_any? : Bool
      neighbors || series || related || translations || ancestors || !get_page_targets.empty?
    end
  end

  # Everything the cache and the serve fan-out want to know about what a
  # page's templates read from other pages, from one closure scan.
  record PageTemplateScan,
    page_set : Bool,
    section_set : Bool,
    listing : ListingSetDeps,
    relations : RelationDeps

  # Scan the closure a page actually renders through: its entry template,
  # the shortcode templates its content calls (a shortcode renders with the
  # page's full context, so a `recent()` shortcode looping `site.pages` is a
  # listing as much as a template loop is), and its output-format templates.
  # Scanning the entry template alone missed both. Memoized by those roots.
  protected def page_template_scan(page : Models::Page, templates : Hash(String, String), site : Models::Site) : PageTemplateScan
    roots = [determine_template(page, templates, site)]
    page_shortcode_templates(page).to_a.sort!.each { |sc| roots << sc }
    effective_output_formats(page, site.config).each do |fmt|
      roots << determine_format_template(page, fmt, templates, site)
    end
    key = roots.join('|')

    @page_template_scan_mutex.synchronize do
      unless @page_template_scan_memo_key.same?(templates)
        @page_template_scan_memo.clear
        @page_template_scan_memo_key = templates
      end
      if cached = @page_template_scan_memo[key]?
        return cached
      end
    end

    blob = closure_blob(roots, templates)
    page_dep, section_dep = listing_set_flags(blob)
    scan = PageTemplateScan.new(
      page_set: page_dep,
      section_set: section_dep,
      listing: listing_set_deps_for(blob),
      relations: RelationDeps.new(
        neighbors: blob.matches?(RELATION_NEIGHBOR_RE),
        series: RELATION_SERIES_MARKERS.any? { |m| blob.includes?(m) },
        related: blob.includes?(RELATION_RELATED_MARKER),
        translations: RELATION_TRANSLATION_MARKERS.any? { |m| blob.includes?(m) },
        ancestors: RELATION_ANCESTOR_MARKERS.any? { |m| blob.includes?(m) },
        get_page_targets: get_page_targets(blob),
        fields: relation_page_fields(blob),
        backlinks: blob.includes?(RELATION_BACKLINKS_MARKER),
      ),
    )
    @page_template_scan_mutex.synchronize do
      @page_template_scan_memo[key] = scan if @page_template_scan_memo_key.same?(templates)
    end
    scan
  end

  # The optional page fields (`[extra]`, excerpt/word count/reading time) a
  # closure reads off a page OTHER than the one it renders. Same receiver
  # rules as the listing union (see `reads_other_page_field?`), plus the
  # chained reads off a relation. Folding them unconditionally made a body
  # edit — which moves only the content-derived fields — re-render every
  # neighbour, and a section body edit every page under it.
  private def relation_page_fields(blob : String) : Builder::ListingPageFields
    rebound = blob.matches?(REBINDS_SELF_RE)
    Builder::ListingPageFields.new(
      extra: blob.matches?(CHAINED_EXTRA_RE) ||
             reads_other_page_field?(blob, EXTRA_ATTR_RE, EXTRA_INDEX_RE, EXTRA_ARG_RE, rebound),
      content_derived: blob.matches?(CHAINED_CONTENT_DERIVED_RE) ||
                       reads_other_page_field?(blob, CONTENT_DERIVED_ATTR_RE,
                         CONTENT_DERIVED_INDEX_RE, CONTENT_DERIVED_ARG_RE, rebound),
    )
  end

  # Shortcode templates (`shortcodes/<name>`) the page's content calls,
  # included text counted (`page_scan_texts`). Empty without a dependency
  # graph — the closure scan then reads every template anyway.
  private def page_shortcode_templates(page : Models::Page) : Set(String)
    deps = @template_deps
    return Set(String).new unless deps
    texts = page_scan_texts(page)
    key = texts.last
    @page_template_hash_mutex.synchronize do
      if (memo = @page_shortcodes_memo[page.path]?) && memo[0].same?(key) && memo[1].same?(deps)
        return memo[2]
      end
    end
    used = Set(String).new
    texts.each { |text| used.concat(deps.shortcodes_used_in(text)) }
    @page_template_hash_mutex.synchronize { @page_shortcodes_memo[page.path] = {key, deps, used} }
    used
  end

  private def filter_changed_pages(pages : Array(Models::Page), output_dir : String, cache : Cache, templates : Hash(String, String), site : Models::Site, page_set_fp : String = "", section_set_fp : String = "") : Array(Models::Page)
    page_set_changed = cache.page_set_changed?(page_set_fp)
    section_set_changed = cache.section_set_changed?(section_set_fp)
    # `@/` link targets resolve against every page and section, exactly as
    # the render's InternalLinkResolver pass does.
    link_targets = build_pages_by_path(site)
    clear_filter_relations_hashes
    # Resolved once for the static-collision gate below; nil (the common warm
    # build, where no static file changed) skips the gate entirely.
    static_cwd = static_copies_recorded? ? Dir.current : nil
    pages.select do |page|
      # A synthesized page has no source file to fingerprint and records no
      # cache entry (see record_page_cache_entry) — it is always dirty, so
      # skip computing its template/asset hashes just to find that out.
      next true if page.synthesized?
      source_path, output_path = cache_paths_for(page, output_dir)
      fmt_paths = format_output_paths(page, output_dir, effective_output_formats(page, site.config))
      # Taken for every page, including the ones a gate below re-renders
      # regardless, so each recorded entry carries the comparison-time value.
      relations_hash = filter_relations_hash(page, templates, site, link_targets)
      # The static copy in the Initialize phase wrote a file this page owns (a
      # `static/` path that collides with the page's URL). A cold build lets
      # the render overwrite it; skipping the page here left the static bytes
      # published in its place.
      #
      # `derived_paths` matters as much as the page's own output: an `aliases`
      # redirect stub and a section's `/page/N/` pagination pages are written
      # ONLY by a render, so `static/legacy/index.html` beside
      # `aliases = ["/legacy/"]` replaced the stub outright on every warm
      # build. The cache entry is the only record of those paths.
      if cwd = static_cwd
        next true if output_path && static_copied_output?(output_path, cwd)
        next true if fmt_paths.any? { |path| static_copied_output?(path, cwd) }
        next true if cache.derived_paths_for(source_path).any? { |path| static_copied_output?(path, cwd) }
      end
      next true if cache.changed?(source_path, output_path || "", page.cascade_fingerprint, page_template_hash(page, templates, site), extra_outputs: fmt_paths, assets_hash: page_assets_hash(page), git_hash: page_git_hash(page), relations_hash: relations_hash)
      # Page's own source is unchanged: only re-render it if a set it depends on
      # changed. Skip the (cheap) marker scan entirely when nothing moved.
      next false unless page_set_changed || section_set_changed
      scan = page_template_scan(page, templates, site)
      pdep, sdep = scan.page_set, scan.section_set
      # A section index renders its section's page list even via {{ section.list }}
      # (no template marker), so treat every Section as page-set dependent.
      # That list also carries its child SECTIONS (and `section.subsections`
      # prints them), so a retitled child `_index.md` — a section-set move —
      # must re-render the parent too, the root `_index.md` included.
      page_dep = pdep || page.is_a?(Models::Section)
      section_dep = sdep || page.is_a?(Models::Section)
      (page_dep && page_set_changed) || (section_dep && section_set_changed)
    end
  end

  # Scan a page's resolved template-closure SOURCE for global-iteration markers.
  # Returns {depends_on_page_set, depends_on_section_set}. With dependency
  # tracking off, conservatively scans all templates.
  private def listing_template_deps(entry_template : String, templates : Hash(String, String)) : Tuple(Bool, Bool)
    listing_set_flags(listing_closure_blob(entry_template, templates))
  end

  private def listing_set_flags(blob : String) : Tuple(Bool, Bool)
    {PAGE_SET_MARKERS.any? { |m| blob.includes?(m) } || dynamic_get_page?(blob),
     SECTION_SET_MARKERS.any? { |m| blob.includes?(m) }}
  end

  # Receivers that name the CURRENT page (or site-level config), never
  # another page in a listing. A read off one of these moves only when that
  # page itself changes, and the page already re-renders on its own account.
  SELF_RECEIVERS = {"page", "section", "site", "config"}

  # A listing reads a field off ANOTHER page: `p.summary`, `item.word_count`,
  # `post.extra.badge`, `p["summary"]`, or `sort(attribute="word_count")`.
  #
  # The shape matters as much as the name. Matching bare words against raw
  # template source scored a literal `<summary>` disclosure tag and a
  # `class="extra-info"` as field reads, which silently turned `--cache` from
  # "re-render the edited page" into "re-render every listing on every edit".
  # Requiring `<receiver>.<field>` (or the bracket/`attribute=` spellings)
  # keeps prose and markup out of the match.
  CONTENT_DERIVED_ATTR_RE  = /(?<![\w.])(\w+)\.(?:summary(?:_truncated)?|word_count|reading_time)\b/
  CONTENT_DERIVED_INDEX_RE = /(?<![\w.])(\w+)\[\s*["'](?:summary(?:_truncated)?|word_count|reading_time)["']\s*\]/
  CONTENT_DERIVED_ARG_RE   = /attribute\s*=\s*["'](?:summary(?:_truncated)?|word_count|reading_time)\b/
  EXTRA_ATTR_RE            = /(?<![\w.])(\w+)\.extra\b/
  EXTRA_INDEX_RE           = /(?<![\w.])(\w+)\[\s*["']extra["']\s*\]/
  EXTRA_ARG_RE             = /attribute\s*=\s*["']extra\b/

  # Anything that rebinds `page`/`section` to a DIFFERENT page, in which case
  # a `page.`-qualified read is a read off another page after all. Covers the
  # loop (including tuple unpacking, where the binding is followed by a comma
  # rather than `in`), `set`, `with`, and macro parameters — a `card(page)`
  # macro is one of the most common listing idioms there is.
  REBINDS_SELF_RE = /\bfor\s+[^%{}]*\b(?:page|section)\b[^%{}]*\bin\b|\bset\s+(?:page|section)\s*=|\bwith\s+[^%{}]*\b(?:page|section)\s*=|\bmacro\s+\w+\s*\([^)]*\b(?:page|section)\b/

  # Source union of every template that renders a global set (page OR
  # section). Empty when no template iterates either.
  #
  # Gating on `page_dep || section_dep` matters: the result also decides what
  # the SECTION fingerprint covers, and a nav that reads only `site.sections`
  # scores `{false, true}` — it never entered the union, so a site whose only
  # listing is a section nav saw no fields at all.
  #
  # Memoized per template set: this walks every template's closure and the
  # render phase asks for it on every build, cached or not.
  private def listing_source_union(templates : Hash(String, String)) : String
    if (memo = @listing_source_union_memo) && @listing_source_union_memo_key.same?(templates)
      return memo
    end
    result = compute_listing_source_union(templates)
    # The KEY holds the hash itself, not its `object_id`. An id is only an
    # address: the previous snapshot is unreachable the moment
    # `load_templates` swaps in a new one, and a collected snapshot's address
    # can be handed straight back to the replacement — at which point a
    # serve-session template reload would read the PREVIOUS set's union and
    # decide cache invalidation from templates that no longer exist. Keeping
    # a reference makes the identity unforgeable (and pins exactly one dead
    # snapshot, which the next reload releases).
    @listing_source_union_memo_key = templates
    @listing_source_union_memo = result
    result
  end

  private def compute_listing_source_union(templates : Hash(String, String)) : String
    deps = @template_deps
    unless deps
      # Tracking off: listing_template_deps already scans every template, so
      # a page-set marker anywhere makes the whole set the listing surface.
      blob = templates.values.join("\n")
      page_dep, section_dep = listing_set_flags(blob)
      return (page_dep || section_dep) ? blob : ""
    end

    seen = Set(String).new
    String.build do |io|
      templates.each_key do |name|
        page_dep, section_dep = listing_template_deps(name, templates)
        next unless page_dep || section_dep
        deps.closure(name).each do |dep|
          next unless seen.add?(dep)
          templates[dep]?.try { |src| io << src << '\n' }
        end
      end
    end
  end

  # Decide which optional page fields the page-set fingerprint must cover for
  # THIS site (see Builder::ListingPageFields).
  private def listing_page_fields(templates : Hash(String, String)) : Builder::ListingPageFields
    blob = listing_source_union(templates)
    return Builder::ListingPageFields.new(false, false) if blob.empty?

    rebound = blob.matches?(REBINDS_SELF_RE)
    Builder::ListingPageFields.new(
      extra: reads_other_page_field?(blob, EXTRA_ATTR_RE, EXTRA_INDEX_RE, EXTRA_ARG_RE, rebound),
      content_derived: reads_other_page_field?(blob, CONTENT_DERIVED_ATTR_RE,
        CONTENT_DERIVED_INDEX_RE, CONTENT_DERIVED_ARG_RE, rebound),
    )
  end

  # True when some listing template reads the field off a page OTHER than the
  # one being rendered — either through a non-self receiver, through a
  # `attribute="..."` filter argument (always a read over a collection), or
  # through any receiver at all once `page`/`section` has been rebound.
  private def reads_other_page_field?(blob : String, attr_re : Regex, index_re : Regex,
                                      arg_re : Regex, rebound : Bool) : Bool
    return true if blob.matches?(arg_re)
    {attr_re, index_re}.each do |re|
      blob.scan(re) do |match|
        receiver = match[1]
        return true if rebound || !SELF_RECEIVERS.includes?(receiver)
      end
    end
    false
  end

  # Fingerprint a page's `[extra]` table for the set fingerprints.
  #
  # Length-prefixed through DigestUtils, like `compute_config_hash` and
  # `compute_templates_hash`, so adjacent fields cannot spell the same byte
  # stream: plain `k=v;` concatenation made `{"a" => "b;c=d"}` and
  # `{"a" => "b", "c" => "d"}` identical, hiding that `[extra]` edit from every
  # listing. Nested hashes are sorted at every level, so re-ordering keys
  # inside `[extra.foo]` no longer busts the fingerprint spuriously.
  private def extra_fp(extra : Hash(String, Models::ExtraValue)) : String
    digest = Digest::MD5.new
    digest_extra_hash(digest, extra)
    digest.final.hexstring
  end

  private def digest_extra_hash(digest : ::Digest, hash : Hash(String, Models::ExtraValue)) : Nil
    Utils::DigestUtils.update_length_prefixed(digest, "h#{hash.size}")
    hash.keys.sort!.each do |key|
      Utils::DigestUtils.update_length_prefixed(digest, key)
      digest_extra_value(digest, hash[key])
    end
  end

  private def digest_extra_value(digest : ::Digest, value : Models::ExtraValue) : Nil
    case value
    when Hash
      digest_extra_hash(digest, value)
    when Array
      Utils::DigestUtils.update_length_prefixed(digest, "a#{value.size}")
      value.each { |item| digest_extra_value(digest, item) }
    else
      Utils::DigestUtils.update_length_prefixed(digest, value.to_s)
    end
  end

  # Fingerprint the global page set — the content-page metadata that listing
  # pages render (membership, urls, titles, dates, updated, weights, draft,
  # toc, section, image, series, authors, tags, bundle assets).
  #
  # `fields` widens the digest to cover `[extra]` and the content-derived
  # values (`summary`, `word_count`, `reading_time`) when the site's listing
  # templates actually read them. Without that, editing a post's body or its
  # `[extra]` re-rendered only the post itself: every listing showing its
  # excerpt, word count or badge kept the previous build's value forever.
  # Every field is folded length-prefixed (see DigestUtils), and every
  # list/map is size-prefixed, so adjacent values can never alias across
  # boundaries: the previous bare `,`/`;`/`=` joins made `tags = ["a,b"]`
  # and `tags = ["a", "b"]` fingerprint identically, hiding the edit from
  # every listing.
  private def compute_page_set_fingerprint(pages : Array(Models::Page), fields : Builder::ListingPageFields) : String
    digest = Digest::MD5.new
    pages.each { |p| fp_page(digest, p, fields) }
    digest.final.hexstring
  end

  # One page's contribution to the page-set fingerprint — also how the
  # relations hash folds each page another page renders a piece of.
  private def fp_page(digest : ::Digest, p : Models::Page, fields : Builder::ListingPageFields) : Nil
    fp_value(digest, p.path)
    fp_value(digest, p.url)
    fp_value(digest, p.title)
    fp_value(digest, p.description || "")
    fp_value(digest, (p.date.try(&.to_unix) || 0_i64).to_s)
    fp_value(digest, (p.updated.try(&.to_unix) || 0_i64).to_s)
    fp_value(digest, p.weight.to_s)
    fp_value(digest, p.draft ? "1" : "0")
    # `render` decides whether the page writes a file at all, and a page
    # turning `render = false` renders NOTHING — so `pages_rendered` stays 0
    # and `generate_outputs_unchanged?` skipped the SEO pass, leaving the
    # page in sitemap.xml / rss.xml / search.json / llms.txt until an
    # unrelated edit. It belongs to the set's identity for the same reason
    # `draft` does.
    fp_value(digest, p.render ? "1" : "0")
    fp_value(digest, p.toc ? "1" : "0")
    fp_value(digest, p.section)
    fp_value(digest, p.image || "")
    fp_value(digest, p.series || "")
    fp_list(digest, p.authors)
    fp_list(digest, p.tags)
    fp_list(digest, p.assets.sort)
    # Listings can read `p.git.*` directly (not only the `updated` it feeds),
    # so a new commit must move the set fingerprint; folded only when
    # present so disabled sites keep their pre-feature digest.
    fp_value(digest, page_git_hash(p)) if p.git
    fp_value(digest, "t#{p.taxonomies.size}")
    p.taxonomies.keys.sort!.each do |k|
      fp_value(digest, k)
      fp_list(digest, p.taxonomies[k])
    end
    fp_menus(digest, p.menus)
    # Version membership drives `version_links` on OTHER pages (a new
    # counterpart flips `exists`), so it is part of the set identity.
    # Only emitted on versioned sites — unversioned fingerprints stay
    # byte-identical to previous releases.
    if version = p.version
      fp_value(digest, "v:#{version.name}")
    end
    fp_value(digest, extra_fp(p.extra)) if fields.extra
    if fields.content_derived
      fp_value(digest, p.summary || "")
      fp_value(digest, p.auto_summary || "")
      fp_value(digest, p.summary_truncated ? "1" : "0")
      fp_value(digest, p.word_count.to_s)
      fp_value(digest, p.reading_time.to_s)
    end
  end

  # Fingerprint the section set — the metadata nav/menus and section-set
  # consumers render: identity fields plus `date`, `sort_by`, `reverse`,
  # `transparent`, `paginate` and the section's bundle assets, all of which
  # the `site.sections`/`get_section()` Crinja hash exposes.
  # No `fields` parameter: that hash exposes no `extra` key at all, so a
  # section's `[extra]` is unreachable from any section-set listing.
  # Fingerprinting it could only ever cause spurious invalidation, never
  # fix staleness.
  #
  # `auto_sections_menu` (`[menus] auto_sections` is on) also folds the
  # other gates that menu applies to a section; off, the digest keeps its
  # old value so existing caches stay warm.
  private def compute_section_set_fingerprint(sections : Array(Models::Section), auto_sections_menu : Bool = false) : String
    digest = Digest::MD5.new
    sections.each do |s|
      fp_value(digest, s.path)
      fp_value(digest, s.url)
      fp_value(digest, s.title)
      fp_value(digest, s.description || "")
      fp_value(digest, (s.date.try(&.to_unix) || 0_i64).to_s)
      fp_value(digest, s.draft ? "1" : "0")
      fp_value(digest, s.weight.to_s)
      fp_value(digest, s.sort_by || "-")
      reverse = s.reverse
      fp_value(digest, reverse.nil? ? "-" : (reverse ? "1" : "0"))
      fp_value(digest, s.transparent ? "1" : "0")
      if auto_sections_menu
        fp_value(digest, s.render ? "1" : "0")
        fp_value(digest, s.unpublished ? "1" : "0")
        fp_value(digest, s.redirect_to || "")
      end
      fp_value(digest, s.paginate.try(&.to_s) || "-")
      fp_list(digest, s.assets.sort)
      fp_menus(digest, s.menus)
    end
    digest.final.hexstring
  end

  # Fingerprint the MENU projection of the page set: everything
  # `Content::Menus.build` reads off content when it assembles
  # `site.menus` / `get_menu`.
  #
  # Far narrower than the page set — only pages that carry a `[menu]`
  # registration contribute, and only through the fields an entry is built
  # from (`reg.name || p.title`, `p.url`, plus the gates `Menus.build`
  # applies: `render`, language, version). A page gaining or losing a
  # registration changes the number of folded entries, so membership moves
  # too. Config `[[menus.*]]` entries are not folded: a config edit forces a
  # full rebuild before this is ever consulted. With `[menus] auto_sections`
  # every top-level section feeds the menu, registered or not.
  private def compute_menu_set_fingerprint(site : Models::Site) : String
    digest = Digest::MD5.new
    auto_sections = !site.config.menus_auto_sections.nil?
    (site.pages + site.sections).each do |p|
      if auto_sections && p.is_a?(Models::Section) && Content::Menus.top_level_dir(p.section, p.version)
        fp_value(digest, p.path)
        fp_value(digest, p.url)
        fp_value(digest, p.title)
        fp_value(digest, p.weight.to_s)
        fp_value(digest, p.excluded_from_listings? || p.transparent ? "1" : "0")
        fp_value(digest, p.redirect_to || "")
        fp_value(digest, p.language || "")
        fp_value(digest, p.version.try(&.name) || "")
      end
      next if p.menus.empty?
      fp_value(digest, p.path)
      fp_value(digest, p.url)
      fp_value(digest, p.title)
      fp_value(digest, p.render ? "1" : "0")
      fp_value(digest, p.language || "")
      fp_value(digest, p.version.try(&.name) || "")
      fp_menus(digest, p.menus)
    end
    digest.final.hexstring
  end

  # Fingerprint the TAXONOMY-SLUG projection: the term→slug map
  # `get_taxonomy_url` resolves against (`__taxonomy_slugs__` /
  # `__taxonomy_lang_slugs__` in build_global_vars).
  #
  # Those maps are disambiguated over the terms that actually get a page
  # written, so the inputs are the term names per taxonomy plus, per term,
  # which languages have a non-draft, non-generated page carrying it. A post's
  # title or body can move neither, which is the point: tag pills sit in every
  # post's template and must not drag the whole site into a re-render.
  private def compute_taxonomy_slug_fingerprint(site : Models::Site) : String
    digest = Digest::MD5.new
    site.taxonomies.keys.sort!.each do |name|
      fp_value(digest, name)
      terms = site.taxonomies[name]
      term_names = terms.keys.sort!
      fp_list(digest, term_names)
      term_names.each do |term|
        languages = terms[term].compact_map do |p|
          p.draft || p.generated ? nil : (p.language || "")
        end
        fp_list(digest, languages.uniq!.sort!)
      end
    end
    digest.final.hexstring
  end

  # Length-prefixed field fold for the set fingerprints (one scheme with
  # every other fingerprint site — see DigestUtils).
  private def fp_value(digest : ::Digest, value : String) : Nil
    Utils::DigestUtils.update_length_prefixed(digest, value)
  end

  # Size-prefixed, element-length-prefixed list fold: `["a,b"]` and
  # `["a", "b"]` must digest differently.
  private def fp_list(digest : ::Digest, values : Array(String)) : Nil
    Utils::DigestUtils.update_length_prefixed(digest, "a#{values.size}")
    values.each { |v| Utils::DigestUtils.update_length_prefixed(digest, v) }
  end

  # Front-matter menu registrations for the set fingerprints. Any field
  # change (including a page newly gaining/losing a registration) must bust
  # the cache for pages whose template calls `get_menu` / `site.menus`.
  private def fp_menus(digest : ::Digest, menus : Hash(String, Models::MenuRegistration)) : Nil
    Utils::DigestUtils.update_length_prefixed(digest, "m#{menus.size}")
    menus.keys.sort!.each do |k|
      reg = menus[k]
      fp_value(digest, k)
      fp_value(digest, reg.name || "-")
      fp_value(digest, reg.weight.try(&.to_s) || "-")
      fp_value(digest, reg.parent || "-")
      fp_value(digest, reg.identifier || "-")
    end
  end

  # Template closure fingerprint stored in this page's cache entry. With
  # dependency tracking off (config, or a dynamic include in the graph),
  # returns the whole-site templates checksum — matching the previous
  # invalidate-everything behavior.
  #
  # Memoized per page for the duration of a build: cached builds need this
  # twice per page (filter_changed_pages, then cache.update after render)
  # and the shortcode scan walks the full raw content per shortcode
  # template. A racy duplicate computation is harmless — both fibers store
  # the same deterministic value.
  protected def page_template_hash(page : Models::Page, templates : Hash(String, String), site : Models::Site) : String
    deps = @template_deps
    return @global_templates_hash unless @per_page_template_hash && deps

    @page_template_hash_mutex.synchronize do
      if cached = @page_template_hash_memo[page.path]?
        return cached
      end
    end

    entry_template = determine_template(page, templates, site)
    hash = deps.closure_hash(entry_template, page_shortcode_templates(page))

    # Fold each enabled output format's own template closure into the hash so
    # editing e.g. templates/page.json.jinja invalidates the pages that
    # render it, even though their entry (HTML) template is untouched. Pages
    # with no formats take this branch's empty-array fast path and keep the
    # exact hash a build without the feature would compute.
    formats = effective_output_formats(page, site.config)
    unless formats.empty?
      formats.each do |fmt|
        fmt_template = determine_format_template(page, fmt, templates, site)
        hash = "#{hash}+#{deps.closure_hash(fmt_template)}"
      end
    end

    # Hook templates aren't part of the {% include %}/{% extends %} closure
    # graph (they're invoked from Markdown rendering, not template
    # rendering), so fold their fingerprint in here — otherwise editing
    # templates/hooks/render-*.html wouldn't invalidate any page's
    # --cache entry while per-page template hashing is active.
    if reg = Content::Processors::RenderHooks.registry
      hash = "#{hash}+hooks:#{reg.fingerprint}"
    end

    @page_template_hash_mutex.synchronize { @page_template_hash_memo[page.path] = hash }
    hash
  end

  # Record this page's post-render cache entry. No-op when the cache is
  # disabled (the default build).
  #
  # The `cache.enabled?` guard wraps ARGUMENT evaluation, not just the
  # `cache.update` call: computing page_template_hash costs a shortcode-regex
  # scan over the raw content plus an MD5 per page, so it must be skipped
  # entirely when the cache is off.
  #
  # A collision loser gets NO cache entry: its output file holds the
  # winner's bytes, and recording it as up-to-date would let
  # filter_changed_pages skip the page forever — even after the collision
  # is resolved and it becomes the rightful writer.
  private def record_page_cache_entry(page : Models::Page, cache : Cache, templates : Hash(String, String), site : Models::Site, output_dir : String)
    # Alias stubs and `/page/N/` pagination files the render just wrote (see
    # `@page_derived_outputs`): taken on every render, cache or not, so the
    # serve builder can prune what a later render stops writing. Sorted so a
    # re-render in a different fiber order can't make the entry look changed.
    derived = take_page_derived_outputs(page.path).sort!
    return unless cache.enabled?
    # A `[[content.generate]]` page has no source file to stat or hash —
    # `cache.update` would raise on the missing path. Skipping keeps it
    # always-dirty under --cache, which is also correct: its content moves
    # with `site.data`, whose digest already invalidates the global config
    # hash, not with any per-file fingerprint.
    return if page.synthesized?
    return if collision_suppressed?(page, page.url)
    source_path, output_path = cache_paths_for(page, output_dir)
    # No output file was written for an escaping page, so recording it as
    # up-to-date would let filter_changed_pages skip it forever.
    return unless output_path
    fmt_paths = format_output_paths(page, output_dir, effective_output_formats(page, site.config))
    relations_hash = @page_template_hash_mutex.synchronize { @filter_relations_hashes.delete(page.path) } ||
                     page_relations_hash(page, templates, site, @pages_by_path || build_pages_by_path(site))
    cache.update(source_path, output_path, page.cascade_fingerprint, page_template_hash(page, templates, site), output_paths: fmt_paths, assets_hash: page_assets_hash(page), git_hash: page_git_hash(page), derived_paths: derived, relations_hash: relations_hash)
  end

  # `page_relations_hash` as of the cache comparison, remembered so the
  # entry recorded after the render stores the same value the next build's
  # comparison computes (see @filter_relations_hashes).
  private def filter_relations_hash(page : Models::Page, templates : Hash(String, String), site : Models::Site, link_targets : Hash(String, Models::Page)) : String
    hash = page_relations_hash(page, templates, site, link_targets)
    @page_template_hash_mutex.synchronize { @filter_relations_hashes[page.path] = hash }
    hash
  end

  # Drop the hashes of pages the render skipped, so a later serve rebuild
  # of one cannot record a value from this earlier pass.
  private def clear_filter_relations_hashes : Nil
    @page_template_hash_mutex.synchronize { @filter_relations_hashes.clear }
  end

  # Fingerprint of what this page renders from OTHER pages (see
  # CacheEntry#relations_hash). "" when it renders nothing of them, so such
  # pages compare equal to legacy entries.
  #
  # Only the relations the page's template closure actually reads are
  # folded, and of each related page only what the closure can print: the
  # page-set fields, plus `[extra]`/excerpts when the closure reads them off
  # another page (RelationDeps#fields), and for ancestors just the title and
  # URL a breadcrumb shows. A template without `page.lower` must not
  # re-render because a neighbour was retitled, and one printing only
  # neighbour titles must not re-render because a neighbour's body changed. `@/` links are folded from the content itself,
  # target path plus the URL it resolves to ("" while unresolved, so the
  # page also re-renders once the missing target appears).
  protected def page_relations_hash(page : Models::Page, templates : Hash(String, String), site : Models::Site, link_targets : Hash(String, Models::Page)) : String
    rel = page_template_scan(page, templates, site).relations
    links = internal_link_targets(page)
    backlinks = rel.backlinks && site.config.backlinks
    wikilinks = wikilink_resolutions(page)
    return "" if !rel.reads_any? && links.empty? && !backlinks && wikilinks.empty?

    digest = Digest::MD5.new
    if rel.neighbors
      fp_value(digest, "n")
      fp_relation(digest, page.lower, rel.fields)
      fp_relation(digest, page.higher, rel.fields)
    end
    if rel.series
      fp_value(digest, "s#{page.series_index}")
      fp_value(digest, "a#{page.series_pages.size}")
      page.series_pages.each { |p| fp_relation(digest, p, rel.fields) }
    end
    if rel.related
      fp_value(digest, "r#{page.related_posts.size}")
      page.related_posts.each { |p| fp_relation(digest, p, rel.fields) }
    end
    if rel.translations
      fp_value(digest, "t#{page.translations.size}")
      page.translations.each do |t|
        fp_value(digest, t.code)
        fp_value(digest, t.url)
        fp_value(digest, t.title)
        fp_value(digest, t.is_current ? "1" : "0")
        fp_value(digest, t.is_default ? "1" : "0")
      end
    end
    if rel.ancestors
      fp_value(digest, "c#{page.ancestors.size}")
      # `page.ancestors` and the JSON-LD breadcrumb expose nothing but each
      # ancestor's title and URL (build_ancestors_crinja).
      page.ancestors.each do |a|
        fp_value(digest, a.path)
        fp_value(digest, a.url)
        fp_value(digest, a.title)
      end
    end
    unless rel.get_page_targets.empty?
      fp_value(digest, "g#{rel.get_page_targets.size}")
      rel.get_page_targets.each do |target|
        fp_value(digest, target)
        fp_relation(digest, resolve_get_page_target(target, site), rel.fields)
      end
    end
    unless links.empty?
      fp_value(digest, "l#{links.size}")
      links.each do |target|
        fp_value(digest, target)
        fp_value(digest, Content::Processors::InternalLinkResolver.page_for(link_targets, target).try(&.url) || "")
      end
    end
    # B lists A when A links to B: A adding or dropping the link, or A's
    # listed fields moving, re-renders B.
    fp_backlinks(digest, page, rel.fields) if backlinks
    # What each wikilink resolves to ("" while unresolved), like `@/` above.
    unless wikilinks.empty?
      fp_value(digest, "w#{wikilinks.size}")
      wikilinks.each { |value| fp_value(digest, value) }
    end
    digest.final.hexstring
  end

  # Fingerprint the LOOKUP projection for the serve fan-out: the pages the
  # site's literal `get_page(path=...)` calls return (see GET_PAGE_LITERAL_RE).
  # "" when no template makes one. `fields` as for the relations hash.
  private def compute_get_page_lookup_fingerprint(site : Models::Site, targets : Array(String), fields : Builder::ListingPageFields) : String
    return "" if targets.empty?
    digest = Digest::MD5.new
    targets.each do |target|
      fp_value(digest, target)
      fp_relation(digest, resolve_get_page_target(target, site), fields)
    end
    digest.final.hexstring
  end

  private def fp_relation(digest : ::Digest, page : Models::Page?, fields : Builder::ListingPageFields) : Nil
    unless page
      fp_value(digest, "-")
      return
    end
    fp_value(digest, "+")
    fp_page(digest, page, fields)
    fp_value(digest, page.language || "")
  end

  # The page `get_page(path: target)` returns — same lookup order as the
  # template function (content path, URL, URL without its trailing slash,
  # then `/<path minus .md>/`), over `site.pages` only.
  private def resolve_get_page_target(target : String, site : Models::Site) : Models::Page?
    site.pages.find { |p| p.path == target || p.url == target || (p.url.size > 1 && p.url.ends_with?('/') && p.url.rstrip('/') == target) } ||
      begin
        alt = "/#{target.chomp(".markdown").chomp(".md")}/"
        site.pages.find { |p| p.path == alt || p.url == alt }
      end
  end

  # The `@/` link targets in a page's content (included text counted),
  # sorted and unique.
  private def internal_link_targets(page : Models::Page) : Array(String)
    targets = [] of String
    page_scan_texts(page).each do |text|
      next unless Utils::ByteScan.includes?(text, "@/")
      text.scan(INTERNAL_LINK_TARGET_RE) { |m| targets << (m[1]? || m[2]) }
    end
    targets.uniq!.sort!
  end

  private def fp_backlinks(digest : ::Digest, page : Models::Page, fields : Builder::ListingPageFields) : Nil
    fp_value(digest, "b#{page.backlinks.size}")
    page.backlinks.each { |p| fp_relation(digest, p, fields) }
  end

  # `target=resolution` for each distinct wikilink in a page's content
  # (raw, and include-expanded, so a transcluded note's links count too):
  # the linked page's path and URL, or an embed's file URL. Empty unless
  # `[markdown] wikilinks`.
  private def wikilink_resolutions(page : Models::Page) : Array(String)
    return [] of String unless index = @wikilink_index
    values = Set(String).new
    page_scan_texts(page).each do |text|
      Content::Processors::Wikilinks.each_link(text, math: site_math?) do |link|
        next unless link.is_a?(Content::Processors::Wikilinks::Link)
        next if link.target.empty?
        resolved = if link.image?
                     index.resolve_file(link.target, page) || ""
                   else
                     index.resolve(link.target, page).try { |t| "#{t.path} #{t.url}" } ||
                       (index.resolve_file(link.target, page) if link.file?) || ""
                   end
        values << "#{link.embed ? '!' : ' '}#{link.target}=#{resolved}"
      end
    end
    values.to_a.sort!
  end

  # Fingerprint of the page's `[git]` metadata (see CacheEntry#git_hash):
  # the commit id plus both timestamps, which is everything `page.git` and
  # the `updated`/`date` fallbacks can render. "" when the page carries no
  # git info so disabled sites and legacy entries compare equal.
  private def page_git_hash(page : Models::Page) : String
    return "" unless git = page.git
    "#{git.hash}:#{git.lastmod.to_unix}:#{git.first_commit.to_unix}"
  end

  # Fingerprint of a page bundle's colocated asset names (see
  # CacheEntry#assets_hash). Sorted and length-prefixed; "" for pages with
  # no assets so legacy cache entries (which default to "") don't force a
  # one-time rebuild of every asset-less page.
  private def page_assets_hash(page : Models::Page) : String
    return "" if page.assets.empty?
    digest = Digest::MD5.new
    page.assets.sort.each { |a| Utils::DigestUtils.update_length_prefixed(digest, a) }
    digest.final.hexstring
  end
end
