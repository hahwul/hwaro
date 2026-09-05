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

  private def filter_changed_pages(pages : Array(Models::Page), output_dir : String, cache : Cache, templates : Hash(String, String), site : Models::Site, page_set_fp : String = "", section_set_fp : String = "") : Array(Models::Page)
    page_set_changed = cache.page_set_changed?(page_set_fp)
    section_set_changed = cache.section_set_changed?(section_set_fp)
    listing_memo = {} of String => Tuple(Bool, Bool)
    pages.select do |page|
      # A synthesized page has no source file to fingerprint and records no
      # cache entry (see record_page_cache_entry) — it is always dirty, so
      # skip computing its template/asset hashes just to find that out.
      next true if page.synthesized?
      source_path, output_path = cache_paths_for(page, output_dir)
      fmt_paths = format_output_paths(page, output_dir, effective_output_formats(page, site.config))
      next true if cache.changed?(source_path, output_path || "", page.cascade_fingerprint, page_template_hash(page, templates, site), extra_outputs: fmt_paths, assets_hash: page_assets_hash(page), git_hash: page_git_hash(page))
      # Page's own source is unchanged: only re-render it if a set it depends on
      # changed. Skip the (cheap) marker scan entirely when nothing moved.
      next false unless page_set_changed || section_set_changed
      entry = determine_template(page, templates, site)
      pdep, sdep = (listing_memo[entry]? || (listing_memo[entry] = listing_template_deps(entry, templates)))
      # A section index renders its section's page list even via {{ section.list }}
      # (no template marker), so treat every Section as page-set dependent.
      page_dep = pdep || page.is_a?(Models::Section)
      (page_dep && page_set_changed) || (sdep && section_set_changed)
    end
  end

  # Scan a page's resolved template-closure SOURCE for global-iteration markers.
  # Returns {depends_on_page_set, depends_on_section_set}. With dependency
  # tracking off, conservatively scans all templates.
  private def listing_template_deps(entry_template : String, templates : Hash(String, String)) : Tuple(Bool, Bool)
    sources = if deps = @template_deps
                deps.closure(entry_template).compact_map { |n| templates[n]? }
              else
                templates.values
              end
    blob = sources.join("\n")
    {PAGE_SET_MARKERS.any? { |m| blob.includes?(m) }, SECTION_SET_MARKERS.any? { |m| blob.includes?(m) }}
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
    if (memo = @listing_source_union_memo) && @listing_source_union_memo_key == templates.object_id
      return memo
    end
    result = compute_listing_source_union(templates)
    @listing_source_union_memo_key = templates.object_id
    @listing_source_union_memo = result
    result
  end

  private def compute_listing_source_union(templates : Hash(String, String)) : String
    deps = @template_deps
    unless deps
      # Tracking off: listing_template_deps already scans every template, so
      # a page-set marker anywhere makes the whole set the listing surface.
      blob = templates.values.join("\n")
      relevant = PAGE_SET_MARKERS.any? { |m| blob.includes?(m) } ||
                 SECTION_SET_MARKERS.any? { |m| blob.includes?(m) }
      return relevant ? blob : ""
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
    pages.each do |p|
      fp_value(digest, p.path)
      fp_value(digest, p.url)
      fp_value(digest, p.title)
      fp_value(digest, p.description || "")
      fp_value(digest, (p.date.try(&.to_unix) || 0_i64).to_s)
      fp_value(digest, (p.updated.try(&.to_unix) || 0_i64).to_s)
      fp_value(digest, p.weight.to_s)
      fp_value(digest, p.draft ? "1" : "0")
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
    digest.final.hexstring
  end

  # Fingerprint the section set — the metadata nav/menus and section-set
  # consumers render: identity fields plus `date`, `sort_by`, `reverse`,
  # `transparent`, `paginate` and the section's bundle assets, all of which
  # the `site.sections`/`get_section()` Crinja hash exposes.
  # No `fields` parameter: that hash exposes no `extra` key at all, so a
  # section's `[extra]` is unreachable from any section-set listing.
  # Fingerprinting it could only ever cause spurious invalidation, never
  # fix staleness.
  private def compute_section_set_fingerprint(sections : Array(Models::Section)) : String
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
      fp_value(digest, s.paginate.try(&.to_s) || "-")
      fp_list(digest, s.assets.sort)
      fp_menus(digest, s.menus)
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
    hash = deps.closure_hash(entry_template, deps.shortcodes_used_in(page.raw_content))

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
    cache.update(source_path, output_path, page.cascade_fingerprint, page_template_hash(page, templates, site), output_paths: fmt_paths, assets_hash: page_assets_hash(page), git_hash: page_git_hash(page))
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
