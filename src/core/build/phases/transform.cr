# Phase: Transform — site population, taxonomy, related posts
#
# Handles the transformation phase: populating the site model with
# pages and sections, aggregating authors, computing series groupings,
# computing related posts, and building lookup indices.

module Hwaro::Core::Build::Phases::Transform
  private def execute_transform_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Transform")
    result = @lifecycle.run_phase(Lifecycle::Phase::Transform, ctx) do
      Logger.status_phase("transform")
      # Hooks handle transformation (Markdown → HTML)
    end
    profiler.end_phase
    return result if result != Lifecycle::HookResult::Continue

    site = @site || raise "Site not initialized"
    # Populate site with pages and sections from context
    site.pages = ctx.pages
    site.sections = ctx.sections

    aggregate_site_authors(site)

    # Compute series groupings
    compute_series(site) if site.config.series.enabled

    # Compute related posts based on taxonomy similarity
    compute_related_posts(site) if site.config.related.enabled

    # Build optimized lookup indices
    site.build_lookup_index

    Lifecycle::HookResult::Continue
  end

  # Link lower/higher page navigation for previous/next page links.
  # Builds a flat ordered list following sidebar/TOC order (like mdBook/Docusaurus):
  # section index → section pages → subsection index → subsection pages → ...
  # This enables cross-section navigation following the natural reading order.
  private def link_page_navigation(ctx : Lifecycle::BuildContext)
    # Build sections lookup
    sections_by_path = {} of String => Models::Section
    ctx.sections.each { |s| sections_by_path[s.section] = s }

    # Group pages by section. `ctx.pages` only contains regular pages and
    # page-bundle leaves (`index.md`) — section indexes (`_index.md`) live
    # in `ctx.sections` and are interleaved separately by
    # `flatten_section_tree`. Page bundles set `is_index = true` for URL
    # generation, but for navigation they're ordinary pages within their
    # parent section.
    pages_by_section = {} of String => Array(Models::Page)
    ctx.pages.each do |page|
      section = page.section
      pages_by_section[section] ||= [] of Models::Page
      pages_by_section[section] << page
    end

    # Sort pages within each section using the section's sort_by setting
    pages_by_section.each do |section_name, pages|
      section = sections_by_path[section_name]?
      sort_by = section.try(&.sort_by) || "date"
      reverse = section.try(&.reverse) || false
      sorted = Utils::SortUtils.sort_pages(pages, sort_by, reverse)
      pages_by_section[section_name] = sorted
    end

    # Find top-level sections (no parent) and sort by weight (path tiebreaker
    # so equal weights keep a stable, deterministic reading order).
    top_sections = ctx.sections.select { |s| !s.section.includes?("/") }
    top_sections.sort! { |a, b| compare_sections_by_weight(a, b) }

    # Recursively flatten sections into reading order
    flat_list = [] of Models::Page
    flatten_section_tree(top_sections, sections_by_path, pages_by_section, flat_list)

    # Add any orphan pages not belonging to any section, leading with the
    # site root index so prev/next starts at the homepage.
    section_names = sections_by_path.keys.to_set
    append_orphan_pages(ctx.pages, section_names, flat_list)

    # Link lower (previous) and higher (next) across the entire flat list
    flat_list.each_with_index do |page, idx|
      page.lower = idx > 0 ? flat_list[idx - 1] : nil
      page.higher = idx < flat_list.size - 1 ? flat_list[idx + 1] : nil
    end
  end

  # Weight-then-path ordering shared by the cold build's navigation link and
  # the incremental relink. Both MUST use the same comparator: the relink
  # previously sorted by weight alone, so equal-weight sections could come out
  # in a different order than the full build produced, flipping prev/next
  # links across whole section blocks on serve-mode incremental rebuilds.
  private def compare_sections_by_weight(a : Models::Section, b : Models::Section) : Int32
    cmp = a.weight <=> b.weight
    cmp.zero? ? (a.path <=> b.path) : cmp
  end

  # Append pages that belong to no rendered section to the reading-order list.
  #
  # The site root index (`content/index.md`, whose `section` is "") is the
  # entry point of the reading order, not a trailing page — without this it was
  # pushed to the END, so the book scaffold's prev/next chain wrapped (the home
  # "Introduction" page landed last and the first chapter lost its prev link).
  # Prepend such root index pages; keep every other true orphan in source order
  # at the tail.
  private def append_orphan_pages(
    pages : Array(Models::Page),
    section_names : Set(String),
    flat_list : Array(Models::Page),
  )
    # Membership via a path set — `flat_list.includes?(page)` was a linear
    # scan per page, O(n²) on sites with no `_index.md` sections at all
    # (every page an orphan), and this runs again on every incremental relink.
    seen_paths = flat_list.each_with_object(Set(String).new) { |p, set| set << p.path }
    pages.each do |page|
      next if section_names.includes?(page.section)
      next if seen_paths.includes?(page.path)
      if page.is_index && page.section.empty?
        flat_list.unshift(page)
      else
        flat_list << page
      end
    end
  end

  # Recursively flatten a list of sections into depth-first reading order.
  # For each section: section index (if renderable) → pages → subsections (recursive)
  private def flatten_section_tree(
    sections : Array(Models::Section),
    sections_by_path : Hash(String, Models::Section),
    pages_by_section : Hash(String, Array(Models::Page)),
    result : Array(Models::Page),
  )
    sections.each do |section|
      # Add section index page if it renders
      result << section if section.render

      # Add sorted pages in this section
      if pages = pages_by_section[section.section]?
        pages.each { |p| result << p }
      end

      # Recurse into subsections (sorted by weight)
      if section.subsections.size > 0
        sorted_subsections = section.subsections.sort_by(&.weight)
        flatten_section_tree(sorted_subsections, sections_by_path, pages_by_section, result)
      end
    end
  end

  # Resolve a section by path using the requested language, with the same
  # fallback chain as Site#section_for: exact language → language-neutral
  # (default-language `_index.md`) → configured default language. Keeps
  # single-language sites (language nil everywhere) on the existing behavior.
  private def lookup_ancestor_section(
    map : Hash({String, String?}, Models::Section),
    path : String,
    language : String?,
    default_language : String,
  ) : Models::Section?
    map[{path, language}]? ||
      map[{path, nil}]? ||
      map[{path, default_language}]?
  end

  # Build subsections hierarchy
  private def build_subsections(ctx : Lifecycle::BuildContext)
    default_lang = ctx.site.try(&.config.default_language) || ""

    # Key by {section path, language}. `section` is language-blind (the language
    # suffix lives in the filename basename, stripped before section is computed),
    # so `posts/_index.md` and `posts/_index.ko.md` both have section "posts". A
    # plain `Hash(String, Section)` made the second overwrite the first, so every
    # page's breadcrumb ancestors came from whichever language's _index loaded
    # last — an English post linking to `/ko/posts/`. `||=` mirrors the
    # first-write-wins of Site#build_lookup_index.
    sections_by_path = {} of {String, String?} => Models::Section
    ctx.sections.each { |s| sections_by_path[{s.section, s.language}] ||= s }

    ctx.sections.each do |section|
      path_parts = section.section.split("/")
      next if path_parts.size <= 1

      # Link to the immediate parent section when it exists (same-language first).
      parent_path = path_parts[0..-2].join("/")
      if parent = lookup_ancestor_section(sections_by_path, parent_path, section.language, default_lang)
        parent.add_subsection(section)
      end

      # Build the ancestors chain from every EXISTING ancestor section, even
      # when an intermediate `_index.md` is missing — otherwise a gap in the
      # tree (e.g. `a/_index.md` + `a/b/c/_index.md`, no `a/b/_index.md`) drops
      # all ancestors and the subsection link. Walk only path_parts[0..-2] so a
      # section never becomes its own ancestor.
      current_path = ""
      path_parts[0..-2].each do |part|
        current_path = current_path.empty? ? part : "#{current_path}/#{part}"
        if ancestor = lookup_ancestor_section(sections_by_path, current_path, section.language, default_lang)
          section.ancestors << ancestor
        end
      end
    end

    # Also build ancestors for regular pages, resolved in the page's own language.
    ctx.pages.each do |page|
      next if page.section.empty?

      path_parts = page.section.split("/")
      current_path = ""
      path_parts.each do |part|
        current_path = current_path.empty? ? part : "#{current_path}/#{part}"
        if ancestor = lookup_ancestor_section(sections_by_path, current_path, page.language, default_lang)
          page.ancestors << ancestor
        end
      end
    end
  end

  # Collect assets for each section and page
  private def collect_assets(ctx : Lifecycle::BuildContext)
    content_files = ctx.config.try(&.content_files)

    ctx.sections.each do |section|
      section.collect_assets("content", content_files)
    end

    ctx.pages.each do |page|
      page.collect_assets("content", content_files)
    end
  end

  # Populate site.taxonomies from all pages (lifecycle context variant)
  private def populate_taxonomies(ctx : Lifecycle::BuildContext)
    if site = ctx.site
      rebuild_taxonomies(site, ctx.all_pages)
    end
  end

  # Rebuild site.taxonomies from the given set of pages.
  # Shared by both full-build (via populate_taxonomies) and incremental build.
  private def rebuild_taxonomies(site : Models::Site, pages : Array(Models::Page))
    site.taxonomies.clear

    pages.each do |page|
      page.taxonomies.each do |name, terms|
        site.taxonomies[name] ||= {} of String => Array(Models::Page)
        terms.each do |term|
          site.taxonomies[name][term] ||= [] of Models::Page
          site.taxonomies[name][term] << page
        end
      end

      # "authors" (and any future configured taxonomy whose terms live on a
      # dedicated Page property rather than in page.taxonomies — see
      # NON_TAXONOMY_ARRAY_KEYS in markdown.cr) is not merged into page.taxonomies
      # the way "tags" is, so it is missing here. Add it from taxonomy_values so
      # the render-phase site.taxonomies matches what the generator writes —
      # otherwise get_taxonomy("authors") is empty at render and get_taxonomy_url
      # falls back to undisambiguated slugs that miss colliding author pages.
      each_property_backed_taxonomy_term(page, site) do |name, term|
        site.taxonomies[name] ||= {} of String => Array(Models::Page)
        site.taxonomies[name][term] ||= [] of Models::Page
        site.taxonomies[name][term] << page
      end
    end

    # Sort pages in taxonomies in-place (default by date)
    site.taxonomies.each_value do |terms|
      terms.each_key do |term|
        terms[term] = Utils::SortUtils.sort_pages(terms[term], "date", false)
      end
    end
  end

  # Yield each {name, term} a page carries via a taxonomy whose terms live on
  # a dedicated Page property (authors — see Page#taxonomy_values) rather
  # than in page.taxonomies. ONE implementation drives rebuild_taxonomies,
  # update_taxonomies_incremental, and snapshot_page_taxonomies — an
  # asymmetry between those three is exactly how serve-mode taxonomy
  # staleness arises (a term the snapshot missed is never removed, a term
  # the add-side missed never appears).
  private def each_property_backed_taxonomy_term(page : Models::Page, site : Models::Site, & : String, String ->)
    site.config.taxonomies.each do |tax|
      name = tax.name
      next if name.strip.empty?
      next if page.taxonomies.has_key?(name) # already carried by page.taxonomies
      page.taxonomy_values(name).each do |term|
        next if term.strip.empty?
        yield name, term
      end
    end
  end

  # Snapshot a page's taxonomy assignments BEFORE re-parsing, including
  # taxonomies whose terms live on dedicated Page properties (authors) that
  # page.taxonomies doesn't carry. update_taxonomies_incremental's removal
  # step reads this snapshot — without the property-backed terms, a page
  # whose `authors` changed kept its old author-term membership forever.
  protected def snapshot_page_taxonomies(page : Models::Page, site : Models::Site) : Hash(String, Array(String))
    snapshot = page.taxonomies.transform_values(&.dup)
    each_property_backed_taxonomy_term(page, site) do |name, term|
      (snapshot[name] ||= [] of String) << term
    end
    snapshot
  end

  # Incremental taxonomy update: only remove/add entries for changed pages.
  # Returns the set of affected {taxonomy_name, term} pairs. Tuples rather
  # than "name:term" strings: a taxonomy name containing ":" would make the
  # joined form ambiguous to split back apart, silently skipping that term's
  # re-sort below.
  private def update_taxonomies_incremental(
    site : Models::Site,
    changed_pages : Array(Models::Page),
    old_taxonomies_snapshot : Hash(String, Hash(String, Array(String))),
  ) : Set({String, String})
    affected_tax_keys = Set({String, String}).new

    changed_pages.each do |page|
      page_path = page.path

      # 1. Remove old assignments from snapshot
      if old_tax = old_taxonomies_snapshot[page_path]?
        old_tax.each do |name, terms|
          tax_terms = site.taxonomies[name]?
          next unless tax_terms
          terms.each do |term|
            if term_pages = tax_terms[term]?
              term_pages.reject! { |p| p.path == page_path }
              affected_tax_keys << {name, term}
              # Clean up empty term
              tax_terms.delete(term) if term_pages.empty?
            end
          end
          # Clean up empty taxonomy when all terms have been removed
          site.taxonomies.delete(name) if tax_terms.empty?
        end
      end

      # 2. Add new assignments from re-parsed page
      page.taxonomies.each do |name, terms|
        site.taxonomies[name] ||= {} of String => Array(Models::Page)
        terms.each do |term|
          site.taxonomies[name][term] ||= [] of Models::Page
          site.taxonomies[name][term] << page
          affected_tax_keys << {name, term}
        end
      end

      # Property-backed taxonomies ("authors" — see rebuild_taxonomies) don't
      # live in page.taxonomies, so the loop above misses them and a serve-mode
      # edit to `authors` frontmatter never reached site.taxonomies until the
      # next full build.
      each_property_backed_taxonomy_term(page, site) do |name, term|
        site.taxonomies[name] ||= {} of String => Array(Models::Page)
        site.taxonomies[name][term] ||= [] of Models::Page
        site.taxonomies[name][term] << page
        affected_tax_keys << {name, term}
      end
    end

    # 3. Re-sort only affected terms
    affected_tax_keys.each do |(name, term)|
      if pages_list = site.taxonomies[name]?.try(&.[term]?)
        site.taxonomies[name][term] = Utils::SortUtils.sort_pages(pages_list, "date", false)
      end
    end

    affected_tax_keys
  end

  # Re-link lower/higher navigation for the entire site.
  # Since navigation is now cross-section (flat), any change requires a full relink.
  # Re-link lower/higher across the whole global reading order and RETURN the set
  # of pages whose lower/higher pointer actually changed, so the incremental
  # rebuild can re-render exactly those. The `affected_sections` arg is no longer
  # used to scope the relink (the reading order is global), but the changed-set
  # return is what callers need: a section `_index.md` weight/sort_by/reverse edit
  # reorders an entire BLOCK of pages, flipping prev/next on many pages that are
  # neither the changed page nor its immediate neighbors.
  private def relink_navigation_for_sections(
    site : Models::Site,
    affected_sections : Set(String),
  ) : Set(Models::Page)
    # Build a BuildContext-compatible structure for reuse
    sections_by_path = {} of String => Models::Section
    site.sections.each { |s| sections_by_path[s.section] = s }

    pages_by_section = {} of String => Array(Models::Page)
    site.pages.each do |page|
      section = page.section
      pages_by_section[section] ||= [] of Models::Page
      pages_by_section[section] << page
    end

    pages_by_section.each do |section_name, pages|
      section = sections_by_path[section_name]?
      sort_by = section.try(&.sort_by) || "date"
      reverse = section.try(&.reverse) || false
      pages_by_section[section_name] = Utils::SortUtils.sort_pages(pages, sort_by, reverse)
    end

    top_sections = site.sections.select { |s| !s.section.includes?("/") }
    top_sections.sort! { |a, b| compare_sections_by_weight(a, b) }

    flat_list = [] of Models::Page
    flatten_section_tree(top_sections, sections_by_path, pages_by_section, flat_list)

    section_names = sections_by_path.keys.to_set
    append_orphan_pages(site.pages, section_names, flat_list)

    # Snapshot the old prev/next before re-linking so we can report exactly which
    # pages had a neighbor change (compared by file path — unique per page).
    old = {} of String => {String?, String?}
    flat_list.each { |p| old[p.path] = {p.lower.try(&.path), p.higher.try(&.path)} }

    flat_list.each_with_index do |page, idx|
      page.lower = idx > 0 ? flat_list[idx - 1] : nil
      page.higher = idx < flat_list.size - 1 ? flat_list[idx + 1] : nil
    end

    changed = Set(Models::Page).new
    flat_list.each do |page|
      prev = old[page.path]
      if page.lower.try(&.path) != prev[0] || page.higher.try(&.path) != prev[1]
        changed << page
      end
    end
    changed
  end

  # Recompute series only for series that contain changed pages.
  # Includes old_series_names so that series a page has left are also recomputed.
  # Returns the set of affected series names.
  private def recompute_series_for_pages(
    site : Models::Site,
    changed_pages : Array(Models::Page),
    old_series_names : Hash(String, String?) = {} of String => String?,
  ) : Set(String)
    affected_series = Set(String).new

    # Include current series from changed pages
    changed_pages.each do |page|
      if name = page.series
        affected_series << name
      end
    end

    # Include old series names (page may have left a series)
    old_series_names.each_value do |name|
      affected_series << name if name
    end

    return affected_series if affected_series.empty?

    # Rebuild groups only for affected series
    groups = {} of String => Array(Models::Page)
    site.pages.each do |page|
      next if page.draft || page.unpublished || !page.render
      if name = page.series
        next unless affected_series.includes?(name)
        (groups[name] ||= [] of Models::Page) << page
      end
    end

    assign_series_groups(groups)

    # Clear series data for pages whose series became empty
    affected_series.each do |series_name|
      next if groups.has_key?(series_name)
      site.pages.each do |page|
        if page.series == series_name
          page.series_index = 0
          page.series_pages = [] of Models::Page
        end
      end
    end

    affected_series
  end

  # Recompute related posts only for changed pages and pages that previously
  # referenced them. Returns the set of page paths that were updated.
  private def recompute_related_posts_for_pages(
    site : Models::Site,
    changed_pages : Array(Models::Page),
    removed_paths : Set(String) = Set(String).new,
  ) : Set(String)
    config = site.config.related
    return Set(String).new unless config.enabled

    taxonomy_names = config.taxonomies
    limit = config.limit
    all_pages = site.pages.reject { |p| p.draft || p.unpublished || p.is_index || p.generated || !p.render }

    # Build inverted index first (needed for both candidate discovery and scoring)
    inverted, page_lookup = build_related_index(all_pages, taxonomy_names)

    # Collect paths of pages that need related_posts recomputed:
    # 1. Changed pages themselves
    # 2. Pages that previously referenced a changed OR REMOVED page
    # 3. Pages sharing any taxonomy term with changed pages (may become newly related)
    changed_paths = changed_pages.map(&.path).to_set
    pages_to_update = Set(String).new(changed_paths)

    # A page turned draft/future/expired is removed from site.pages, so it is
    # neither a changed page nor in the inverted index — but pages that listed it
    # as a related post still link to a now-deleted output. Seed discovery with
    # the removed paths so those referrers are found and recomputed (the removed
    # page is not in the index, so scoring correctly drops it).
    discovery_paths = removed_paths.empty? ? changed_paths : (changed_paths | removed_paths)
    all_pages.each do |page|
      if page.related_posts.any? { |rp| discovery_paths.includes?(rp.path) }
        pages_to_update << page.path
      end
    end

    # Include pages sharing taxonomy terms with changed pages
    changed_pages.each do |page|
      taxonomy_names.each do |tax_name|
        values = page.taxonomy_values(tax_name)
        inv_tax = inverted[tax_name]?
        next unless inv_tax
        values.each do |term|
          if candidates = inv_tax[term]?
            candidates.each { |path| pages_to_update << path }
          end
        end
      end
    end

    # Recompute only for affected pages
    pages_to_update.each do |page_path|
      page = page_lookup[page_path]?
      next unless page

      scores = Hash(String, Int32).new(0)
      taxonomy_names.each do |tax_name|
        values = page.taxonomy_values(tax_name)
        inv_tax = inverted[tax_name]?
        next unless inv_tax
        values.each do |term|
          if candidates = inv_tax[term]?
            candidates.each do |other_path|
              next if other_path == page.path
              scores[other_path] += 1
            end
          end
        end
      end

      if scores.empty?
        page.related_posts = [] of Models::Page
        next
      end

      page.related_posts = scores.to_a
        .select { |path, _| page_lookup[path]?.try(&.language) == page.language }
        .sort_by! { |_, s| -s }
        .first(limit)
        .map { |path, _| page_lookup[path] }
    end

    pages_to_update
  end

  # Aggregate authors from pages and data
  private def aggregate_site_authors(site : Models::Site)
    site.authors.clear

    # Temporary storage to build author data
    temp_authors = {} of String => NamedTuple(
      name: String,
      pages: Array(Models::Page),
      extra: Hash(String, Crinja::Value))

    # 1. Collect authors from all pages. Skip drafts/generated to match the
    # /authors/ taxonomy generator (build_taxonomy_index skips both); otherwise
    # under `--drafts` site.authors would list draft posts the generated author
    # page omits — two views of the same author disagreeing.
    site.pages.each do |page|
      next if page.draft || page.unpublished || page.generated
      page.authors.each do |author_id|
        # Normalize ID: lower case, stripped
        id = author_id.strip.downcase

        unless temp_authors.has_key?(id)
          temp_authors[id] = {
            name:  author_id, # Default name is the ID as it appeared first
            pages: [] of Models::Page,
            extra: {} of String => Crinja::Value,
          }
        end
        temp_authors[id][:pages] << page
      end
    end

    # 2. Enrich with data from site.data["authors"]
    # We expect site.data["authors"] to be a Hash(String, Crinja::Value)
    # where keys match author IDs
    if authors_data = site.data["authors"]?
      temp_authors.each_key do |id|
        author_info = authors_data[id]
        next if author_info.raw.nil?

        # Normalize Crinja hash entries to {String, Crinja::Value} pairs
        pairs = [] of {String, Crinja::Value}
        if info_hash = author_info.raw.as?(Hash(Crinja::Value, Crinja::Value))
          info_hash.each { |k_val, v| pairs << {k_val.to_s, v} }
        elsif info_hash = author_info.raw.as?(Hash(String, Crinja::Value))
          info_hash.each { |k, v| pairs << {k, v} }
        end

        pairs.each do |k, v|
          if k == "name"
            current = temp_authors[id]
            temp_authors[id] = {name: v.to_s, pages: current[:pages], extra: current[:extra]}
          else
            temp_authors[id][:extra][k] = v
          end
        end
      end
    end

    # 3. Convert to Crinja Values and store in site.authors
    temp_authors.each do |id, data|
      # Sort pages by date descending
      sorted_pages = Utils::SortUtils.sort_pages(data[:pages], "date", true)

      page_values = sorted_pages.map do |p|
        # Expose the same common leaf fields a section/term page list provides,
        # so a post-card partial reused over `author.pages` renders the same as
        # over `section.pages` instead of silently blanking. (series_index is
        # computed after this phase, and permalink lazily during render, so both
        # are intentionally omitted.)
        Crinja::Value.new({
          "title"        => Crinja::Value.new(p.title),
          "url"          => Crinja::Value.new(p.url),
          "date"         => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
          "description"  => Crinja::Value.new(p.description || ""),
          "image"        => Crinja::Value.new(p.image || ""),
          "summary"      => Crinja::Value.new(p.summary_html || p.effective_summary || ""),
          "tags"         => Crinja::Value.new(p.tags.map { |t| Crinja::Value.new(t) }),
          "reading_time" => Crinja::Value.new(p.reading_time),
          "word_count"   => Crinja::Value.new(p.word_count),
          "language"     => Crinja::Value.new(p.language || site.config.default_language),
        })
      end

      # Construct the final author object
      author_hash = {} of String => Crinja::Value
      author_hash["key"] = Crinja::Value.new(id)
      author_hash["name"] = Crinja::Value.new(data[:name])
      author_hash["pages"] = Crinja::Value.new(page_values)

      # Merge extra data
      data[:extra].each do |k, v|
        author_hash[k] = v
      end

      site.authors[id] = Crinja::Value.new(author_hash)
    end
  end

  # Sort each series group by weight/date/title and assign series_index and
  # series_pages. A single-post series gets empty series_pages so the
  # template's `page.series_pages` guard skips the orphan series-nav box.
  private def assign_series_groups(groups : Hash(String, Array(Models::Page)))
    groups.each do |_name, pages|
      sorted = pages.sort_by do |p|
        {p.series_weight, p.date || Time::UNIX_EPOCH, p.title}
      end

      sorted.each_with_index do |page, idx|
        page.series_index = idx + 1
        page.series_pages = sorted.size > 1 ? sorted : ([] of Models::Page)
      end
    end
  end

  # Group pages by series name and assign series_index, series_pages.
  # Pages within a series are sorted by series_weight, then date, then title.
  private def compute_series(site : Models::Site)
    groups = {} of String => Array(Models::Page)

    site.pages.each do |page|
      next if page.draft || page.unpublished || !page.render
      if name = page.series
        (groups[name] ||= [] of Models::Page) << page
      end
    end

    assign_series_groups(groups)
  end

  # Build the taxonomy inverted index ({tax_name => {term => [page_path]}}) and a
  # path->page lookup for the given candidate pages. Shared by the full and
  # incremental related-posts computations.
  private def build_related_index(pages : Array(Models::Page), taxonomy_names : Array(String)) : {Hash(String, Hash(String, Array(String))), Hash(String, Models::Page)}
    inverted = {} of String => Hash(String, Array(String))
    page_lookup = {} of String => Models::Page

    pages.each do |page|
      page_lookup[page.path] = page
      taxonomy_names.each do |tax_name|
        values = page.taxonomy_values(tax_name)
        values.each do |term|
          inv_tax = inverted[tax_name]? || (inverted[tax_name] = {} of String => Array(String))
          arr = inv_tax[term]? || (inv_tax[term] = [] of String)
          arr << page.path
        end
      end
    end

    {inverted, page_lookup}
  end

  # Compute related posts for each page based on shared taxonomy terms.
  # Pages with more shared terms are ranked higher.
  private def compute_related_posts(site : Models::Site)
    config = site.config.related
    taxonomy_names = config.taxonomies
    limit = config.limit
    return if limit <= 0
    pages = site.pages.reject { |p| p.draft || p.unpublished || p.is_index || p.generated || !p.render }

    # Build inverted index: {taxonomy_name => {term => Array(page_path)}}
    # This avoids the O(N²) pairwise comparison
    inverted, page_lookup = build_related_index(pages, taxonomy_names)

    pages.each do |page|
      # Count co-occurrences via inverted index: O(terms * avg_pages_per_term).
      # Filter by language during accumulation — cross-language candidates are
      # discarded from the final output anyway, so skipping them here produces
      # identical results while reducing work for multilingual sites.
      scores = Hash(String, Int32).new(0)
      page_lang = page.language
      taxonomy_names.each do |tax_name|
        values = page.taxonomy_values(tax_name)
        inv_tax = inverted[tax_name]?
        next unless inv_tax
        values.each do |term|
          if candidates = inv_tax[term]?
            candidates.each do |other_path|
              next if other_path == page.path
              # page_lookup[other_path] is guaranteed present: the inverted
              # index is populated from the same `pages` iteration above.
              next unless page_lookup[other_path].language == page_lang
              scores[other_path] += 1
            end
          end
        end
      end

      next if scores.empty?

      # Bounded top-k selection — equivalent to `.sort_by { -s }.first(limit)`
      # but O(n*k) instead of O(n log n) with fewer allocations. Ties break by
      # scores-hash insertion order (which mirrors pages/taxonomy iteration),
      # matching a stable descending sort. Optimal when limit is small
      # (default 5); parity with sort near limit ≈ log₂(n).
      top = [] of {String, Int32}
      scores.each do |path, score|
        idx = 0
        while idx < top.size && score <= top[idx][1]
          idx += 1
        end
        next if idx >= limit
        top.insert(idx, {path, score})
        top.pop if top.size > limit
      end

      page.related_posts = top.map { |path, _| page_lookup[path] }
    end
  end
end
