# Phase: Transform — site population, taxonomy, related posts
#
# Handles the transformation phase: populating the site model with
# pages and sections, aggregating authors, computing series groupings,
# computing related posts, and building lookup indices.

module Hwaro::Core::Build::Phases::Transform
  private def execute_transform_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Transform")
    result = @lifecycle.run_phase(Lifecycle::Phase::Transform, ctx) do
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

  # Link lower/higher page navigation for previous/next page links
  private def link_page_navigation(ctx : Lifecycle::BuildContext)
    # Group pages by section
    pages_by_section = {} of String => Array(Models::Page)

    ctx.pages.each do |page|
      next if page.is_index
      section = page.section
      pages_by_section[section] ||= [] of Models::Page
      pages_by_section[section] << page
    end

    # For each section, sort pages and link lower/higher
    pages_by_section.each do |section_name, pages|
      # Find section to get sort_by setting
      section = ctx.sections.find { |s| s.section == section_name }
      sort_by = section.try(&.sort_by) || "date"
      reverse = section.try(&.reverse) || false

      # Sort pages
      sorted = Utils::SortUtils.sort_pages(pages, sort_by, reverse)

      # Link lower (previous) and higher (next)
      sorted.each_with_index do |page, idx|
        page.lower = idx > 0 ? sorted[idx - 1] : nil
        page.higher = idx < sorted.size - 1 ? sorted[idx + 1] : nil
      end
    end
  end

  # Build subsections hierarchy
  private def build_subsections(ctx : Lifecycle::BuildContext)
    sections_by_path = {} of String => Models::Section
    ctx.sections.each { |s| sections_by_path[s.section] = s }

    ctx.sections.each do |section|
      path_parts = section.section.split("/")
      next if path_parts.size <= 1

      # Find parent section
      parent_path = path_parts[0..-2].join("/")
      if parent = sections_by_path[parent_path]?
        parent.add_subsection(section)

        # Build ancestors chain
        current_path = ""
        path_parts[0..-2].each do |part|
          current_path = current_path.empty? ? part : "#{current_path}/#{part}"
          if ancestor = sections_by_path[current_path]?
            section.ancestors << ancestor
          end
        end
      end
    end

    # Also build ancestors for regular pages
    ctx.pages.each do |page|
      next if page.section.empty?

      path_parts = page.section.split("/")
      current_path = ""
      path_parts.each do |part|
        current_path = current_path.empty? ? part : "#{current_path}/#{part}"
        if ancestor = sections_by_path[current_path]?
          page.ancestors << ancestor
        end
      end
    end
  end

  # Collect assets for each section and page
  private def collect_assets(ctx : Lifecycle::BuildContext)
    ctx.sections.each do |section|
      section.collect_assets("content")
    end

    ctx.pages.each do |page|
      page.collect_assets("content")
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
    end

    # Sort pages in taxonomies in-place (default by date)
    site.taxonomies.each_value do |terms|
      terms.each_key do |term|
        terms[term] = Utils::SortUtils.sort_pages(terms[term], "date", false)
      end
    end
  end

  # Incremental taxonomy update: only remove/add entries for changed pages.
  # Returns the set of affected "taxonomy_name:term" keys for cache invalidation.
  private def update_taxonomies_incremental(
    site : Models::Site,
    changed_pages : Array(Models::Page),
    old_taxonomies_snapshot : Hash(String, Hash(String, Array(String))),
  ) : Set(String)
    affected_tax_keys = Set(String).new

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
              affected_tax_keys << "#{name}:#{term}"
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
          affected_tax_keys << "#{name}:#{term}"
        end
      end
    end

    # 3. Re-sort only affected terms
    affected_tax_keys.each do |key|
      parts = key.split(":", 2)
      name = parts[0]
      term = parts[1]
      if pages_list = site.taxonomies[name]?.try(&.[term]?)
        site.taxonomies[name][term] = Utils::SortUtils.sort_pages(pages_list, "date", false)
      end
    end

    affected_tax_keys
  end

  # Re-link lower/higher navigation only for sections that contain changed pages.
  private def relink_navigation_for_sections(
    site : Models::Site,
    affected_sections : Set(String),
  )
    affected_sections.each do |section_name|
      section_pages = site.pages_by_section[section_name]?
      next unless section_pages

      non_index_pages = section_pages.reject(&.is_index)
      next if non_index_pages.empty?

      section = site.sections_by_name[section_name]?
      sort_by = section.try(&.sort_by) || "date"
      reverse = section.try(&.reverse) || false

      sorted = Utils::SortUtils.sort_pages(non_index_pages, sort_by, reverse)

      sorted.each_with_index do |page, idx|
        page.lower = idx > 0 ? sorted[idx - 1] : nil
        page.higher = idx < sorted.size - 1 ? sorted[idx + 1] : nil
      end
    end
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
      next if page.draft || !page.render
      if name = page.series
        next unless affected_series.includes?(name)
        (groups[name] ||= [] of Models::Page) << page
      end
    end

    groups.each do |_name, pages|
      sorted = pages.sort_by do |p|
        {p.series_weight, p.date || Time::UNIX_EPOCH, p.title}
      end

      sorted.each_with_index do |page, idx|
        page.series_index = idx + 1
        page.series_pages = sorted
      end
    end

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
  ) : Set(String)
    config = site.config.related
    return Set(String).new unless config.enabled

    taxonomy_names = config.taxonomies
    limit = config.limit
    all_pages = site.pages.reject { |p| p.draft || p.is_index || p.generated || !p.render }

    # Build inverted index first (needed for both candidate discovery and scoring)
    inverted = {} of String => Hash(String, Array(String))
    page_lookup = {} of String => Models::Page

    all_pages.each do |page|
      page_lookup[page.path] = page
      taxonomy_names.each do |tax_name|
        values = page.taxonomies[tax_name]? || (tax_name == "tags" ? page.tags : [] of String)
        values.each do |term|
          inv_tax = inverted[tax_name]? || (inverted[tax_name] = {} of String => Array(String))
          arr = inv_tax[term]? || (inv_tax[term] = [] of String)
          arr << page.path
        end
      end
    end

    # Collect paths of pages that need related_posts recomputed:
    # 1. Changed pages themselves
    # 2. Pages that previously referenced a changed page
    # 3. Pages sharing any taxonomy term with changed pages (may become newly related)
    changed_paths = changed_pages.map(&.path).to_set
    pages_to_update = Set(String).new(changed_paths)

    all_pages.each do |page|
      if page.related_posts.any? { |rp| changed_paths.includes?(rp.path) }
        pages_to_update << page.path
      end
    end

    # Include pages sharing taxonomy terms with changed pages
    changed_pages.each do |page|
      taxonomy_names.each do |tax_name|
        values = page.taxonomies[tax_name]? || (tax_name == "tags" ? page.tags : [] of String)
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
        values = page.taxonomies[tax_name]? || (tax_name == "tags" ? page.tags : [] of String)
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

    # 1. Collect authors from all pages
    site.pages.each do |page|
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
        Crinja::Value.new({
          "title"       => Crinja::Value.new(p.title),
          "url"         => Crinja::Value.new(p.url),
          "date"        => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
          "description" => Crinja::Value.new(p.description || ""),
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

  # Group pages by series name and assign series_index, series_pages.
  # Pages within a series are sorted by series_weight, then date, then title.
  private def compute_series(site : Models::Site)
    groups = {} of String => Array(Models::Page)

    site.pages.each do |page|
      next if page.draft || !page.render
      if name = page.series
        (groups[name] ||= [] of Models::Page) << page
      end
    end

    groups.each do |_name, pages|
      sorted = pages.sort_by do |p|
        {p.series_weight, p.date || Time::UNIX_EPOCH, p.title}
      end

      sorted.each_with_index do |page, idx|
        page.series_index = idx + 1
        page.series_pages = sorted
      end
    end
  end

  # Compute related posts for each page based on shared taxonomy terms.
  # Pages with more shared terms are ranked higher.
  private def compute_related_posts(site : Models::Site)
    config = site.config.related
    taxonomy_names = config.taxonomies
    limit = config.limit
    pages = site.pages.reject { |p| p.draft || p.is_index || p.generated || !p.render }

    # Build inverted index: {taxonomy_name => {term => Array(page_path)}}
    # This avoids the O(N²) pairwise comparison
    inverted = {} of String => Hash(String, Array(String))
    page_lookup = {} of String => Models::Page

    pages.each do |page|
      page_lookup[page.path] = page
      taxonomy_names.each do |tax_name|
        values = page.taxonomies[tax_name]? || (tax_name == "tags" ? page.tags : [] of String)
        values.each do |term|
          inv_tax = inverted[tax_name]? || (inverted[tax_name] = {} of String => Array(String))
          arr = inv_tax[term]? || (inv_tax[term] = [] of String)
          arr << page.path
        end
      end
    end

    pages.each do |page|
      # Count co-occurrences via inverted index: O(terms * avg_pages_per_term)
      scores = Hash(String, Int32).new(0)
      taxonomy_names.each do |tax_name|
        values = page.taxonomies[tax_name]? || (tax_name == "tags" ? page.tags : [] of String)
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

      next if scores.empty?

      # Filter by language and build result
      page.related_posts = scores.to_a
        .select { |path, _| page_lookup[path]?.try(&.language) == page.language }
        .sort_by! { |_, s| -s }
        .first(limit)
        .map { |path, _| page_lookup[path] }
    end
  end
end
