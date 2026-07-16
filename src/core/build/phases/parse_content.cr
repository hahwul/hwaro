# Phase: ParseContent — frontmatter parsing (sequential/parallel)
#
# Handles parsing content files: reading files, extracting frontmatter,
# building page metadata, filtering drafts/expired pages, linking
# navigation, building subsections, collecting assets, and populating
# taxonomies.

module Hwaro::Core::Build::Phases::ParseContent
  private def execute_parse_content_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("ParseContent")
    result = @lifecycle.run_phase(Lifecycle::Phase::ParseContent, ctx) do
      Logger.status_phase("parse")
      # Default parsing if no hooks registered
      unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeParseContent)
        parse_content_default(ctx)
      end
    end
    profiler.end_phase
    return result if result != Lifecycle::HookResult::Continue

    # Link multilingual translations between pages/sections (for language switchers)
    if config = ctx.config
      Content::Multilingual.link_translations!(ctx.all_pages, config)
    end

    # Build subsections first (needed for flat navigation ordering)
    build_subsections(ctx)
    # Link lower/higher page navigation
    link_page_navigation(ctx)
    collect_assets(ctx)
    populate_taxonomies(ctx)

    # Render <!-- more --> summaries with the body's pipeline now that every
    # page's URL is final (internal-link resolution) — and before Transform,
    # which bakes summary_html into Crinja page values.
    if (site = @site) && (templates = @templates)
      render_page_summaries(ctx.all_pages, site, templates, ctx.options.highlight && site.config.highlight.enabled)
    end

    Lifecycle::HookResult::Continue
  end

  # Render each page's `<!-- more -->` summary through the same sub-pipeline
  # as the body: shortcodes → configured Markdown (extensions, safe mode,
  # emoji) → placeholder replacement → internal-link resolution. Rendering
  # the raw chunk with bare Markdown.render leaked literal `{{ … }}` syntax
  # into list pages / feeds / meta descriptions and silently dropped
  # tables, footnotes, and emoji the body renders fine.
  #
  # Runs single-fiber between the parse fan-out and Transform. Site
  # relationships (taxonomies, related posts) are not assembled yet, so a
  # summary shortcode that queries them sees pre-Transform state — fine for
  # the presentational shortcodes summaries realistically contain.
  # `link_targets` is the page set internal `@/` links may point at —
  # defaults to `pages`, which is correct for the full build (all pages) but
  # must be passed explicitly by incremental callers that re-render only a
  # subset. It can't come from `site.pages`: Transform populates that AFTER
  # this runs in the full build (`site.pages = ctx.pages`, transform.cr).
  private def render_page_summaries(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    use_highlight : Bool,
    link_targets : Array(Models::Page) = pages,
  )
    md_config = site.config.markdown
    pages_by_path : Hash(String, Models::Page)? = nil

    pages.each do |page|
      summary_md = page.extract_summary
      next unless summary_md

      shortcode_results = {} of String => String
      processed = if content_may_contain_shortcodes?(summary_md)
                    context = build_template_variables(page, site, "", "", "")
                    process_shortcodes_jinja(summary_md, templates, context, shortcode_results)
                  else
                    summary_md
                  end

      html, _ = Processor::Markdown.render(processed, use_highlight, md_config.safe, md_config.lazy_loading, md_config.emoji, markdown_config: md_config)
      html = replace_shortcode_placeholders(html, shortcode_results)

      pbp = (pages_by_path ||= begin
        map = {} of String => Models::Page
        link_targets.each { |p| map[p.path] ||= p }
        map
      end)
      html = Content::Processors::InternalLinkResolver.resolve(html, pbp, page.path, site.config.base_url)
      html = Content::Processors::InternalLinkResolver.prefix_root_relative_links(html, site.config.base_url)

      page.summary_html = html
    rescue ex
      # A broken shortcode in a summary must not abort the whole parse
      # phase — fall back to the plain-Markdown rendering and let the
      # body render surface the real error with full diagnostics.
      Logger.debug "Summary render failed for #{page.path}: #{ex.message}"
      fallback, _ = Processor::Markdown.render(summary_md.to_s, markdown_config: md_config)
      page.summary_html = fallback
    end
  end

  # Default parsing when no hooks are registered.
  # File reads and frontmatter parsing are parallelized using fibers to
  # overlap I/O waits across many files.  Each fiber operates on a
  # distinct Page object so there are no data races.
  private def parse_content_default(ctx : Lifecycle::BuildContext)
    pages = ctx.all_pages
    parallel = ctx.options.parallel && pages.size > 1

    if parallel
      parse_content_parallel(pages)
    else
      parse_content_sequential(pages)
    end

    # Apply section [cascade] defaults to descendants before draft/expiry
    # filtering so cascaded `draft` participates in the filters, and before
    # populate_taxonomies so cascaded tags/taxonomies are aggregated.
    # Sections the AfterReadContent hook already filtered out (draft/expired
    # _index files) still cascade to their descendants — include them.
    apply_cascades(ctx.all_pages, ctx.sections + ctx.excluded_cascade_sections)

    # Single-pass filtering: remove parse-failed, draft, and expired pages.
    # Combines multiple reject! calls into one pass per array to avoid
    # repeated traversals, and calls invalidate_all_pages_cache at most once.
    include_drafts = ctx.options.drafts
    filter_expired = !ctx.options.include_expired
    filter_future = !ctx.options.include_future
    now = Time.utc
    soon = now + 7.days

    # Warn about pages expiring soon (before filtering)
    if filter_expired
      ctx.pages.each do |p|
        if exp = p.expires
          if exp > now && exp <= soon
            Logger.warn "Page '#{p.path}' expires on #{exp.to_s("%Y-%m-%d")} (within 7 days)"
          end
        end
      end
    end

    pages_before = ctx.pages.size
    sections_before = ctx.sections.size
    failed_count = 0
    draft_count = 0
    expired_count = 0
    future_count = 0

    # Stamp the publication window on every page before filtering: pages
    # admitted via --include-future / --include-expired keep unpublished=true
    # so sitemap/feeds/search/llms and generated listings can exclude them,
    # mirroring the --drafts contract (preview renders, artifacts don't leak).
    ctx.pages.each(&.refresh_unpublished!(now))
    ctx.sections.each(&.refresh_unpublished!(now))

    filter = ->(p : Models::Page) do
      if p.parse_failed
        failed_count += 1
        true
      elsif !include_drafts && p.draft
        draft_count += 1
        true
      elsif filter_expired && (p.expires.try { |e| e <= now } || false)
        expired_count += 1
        true
      elsif filter_future && (p.date.try { |d| d > now } || false)
        future_count += 1
        true
      else
        false
      end
    end

    ctx.pages.reject!(&filter)
    ctx.sections.reject!(&filter)

    total_removed = (pages_before - ctx.pages.size) + (sections_before - ctx.sections.size)
    if total_removed > 0
      ctx.invalidate_all_pages_cache
    end

    # The skipped total feeds the receipt's "parse … N skipped" emphasis; the
    # per-reason breakdown stays available under --verbose. Parse errors remain
    # a warning regardless, since they signal broken content.
    ctx.stats.pages_skipped = draft_count + future_count + expired_count
    Logger.warn "  #{failed_count} page(s) skipped due to parse errors." if failed_count > 0
    if ctx.options.verbose
      Logger.info "  #{draft_count} page(s) skipped (draft) — excluded from sitemap, feeds & search by default." if draft_count > 0
      Logger.info "  #{future_count} page(s) skipped (future-dated)." if future_count > 0
      Logger.info "  Excluded #{expired_count} expired page#{"s" if expired_count > 1}" if expired_count > 0
    end

    # Show included draft content paths when --drafts flag is used
    if include_drafts
      draft_pages = ctx.all_pages.select(&.draft)
      if draft_pages.size > 0
        max_url_len = draft_pages.max_of(&.url.size)
        pad = {max_url_len, 24}.max
        Logger.info "Including #{draft_pages.size} draft(s):"
        draft_pages.each do |p|
          Logger.info "  #{p.url.ljust(pad)} <- content/#{p.path}"
        end
      end
    end
  end

  # Template lookups are keyed by extension-stripped names ("section", not
  # "section.html"), but users coming from Zola write `template = "section.html"`
  # in frontmatter. Strip the known template extensions here so both spellings
  # resolve to the same template.
  private def normalize_template_name(name : String?) : String?
    name.try(&.sub(Builder::TEMPLATE_EXTENSION_REGEX, ""))
  end

  # Parse a single page: read file, parse frontmatter, assign properties
  private def parse_single_page(page : Models::Page)
    source_path = File.join("content", page.path)
    return unless File.exists?(source_path)

    raw_content = File.read(source_path)
    data = Processor::Markdown.parse(raw_content, source_path)

    page.title = data[:title]
    page.description = data[:description]
    page.image = data[:image]
    page.raw_content = data[:content]
    page.draft = data[:draft]
    page.template = normalize_template_name(data[:template])
    page.in_sitemap = data[:in_sitemap]
    page.toc = data[:toc]
    page.date = data[:date]
    page.updated = data[:updated]
    page.render = data[:render]
    page.slug = data[:slug]
    page.custom_path = data[:custom_path]
    page.aliases = data[:aliases]
    page.tags = data[:tags]
    page.taxonomies = data[:taxonomies]
    page.menus = data[:menus]
    page.front_matter_keys = data[:front_matter_keys]
    page.taxonomy_name = nil
    page.taxonomy_term = nil

    # New fields assignment
    page.authors = data[:authors]
    page.extra = data[:extra]
    page.in_search_index = data[:in_search_index]
    page.insert_anchor_links = data[:insert_anchor_links]
    page.weight = data[:weight]

    # Expiry support
    page.expires = data[:expires]

    # Series support
    page.series = data[:series]
    page.series_weight = data[:series_weight]

    # Redirect support — applies to both regular pages and sections
    page.redirect_to = data[:redirect_to]

    # Calculate word count and reading time
    page.calculate_word_count
    page.calculate_reading_time

    # Extract the <!-- more --> summary chunk (raw markdown) onto the model.
    # Rendering to HTML happens in render_page_summaries after the parse
    # fan-out — it needs every page's final URL (internal links) and the
    # body's full pipeline (shortcodes, markdown extensions, emoji), none of
    # which are available while pages are still being parsed in parallel.
    page.extract_summary

    if page.is_a?(Models::Section)
      page.transparent = data[:transparent]
      page.generate_feeds = data[:generate_feeds]
      page.paginate = data[:paginate]
      page.pagination_enabled = data[:pagination_enabled]
      page.sort_by = data[:sort_by]
      page.reverse = data[:reverse]
      page.page_template = normalize_template_name(data[:page_template])
      page.paginate_path = data[:paginate_path]
      page.cascade = data[:cascade]
    elsif !data[:cascade].empty?
      Logger.warn "#{page.path}: [cascade] is only honored on section _index files — ignored."
    end

    # Calculate URL
    calculate_page_url(page)
  end

  private def parse_content_sequential(pages : Array(Models::Page))
    pages.each do |page|
      parse_single_page(page)
    rescue ex : Hwaro::HwaroError
      # Classified frontmatter errors (HWARO_E_CONTENT) must abort the
      # build so scripts and CI see a stable exit code, rather than
      # silently skipping the offending page.
      raise ex
    rescue ex
      page.parse_failed = true
      Logger.warn "Failed to parse #{page.path}: #{ex.message}"
    end
  end

  # Parallel file reading + frontmatter parsing using fibers.
  # Each fiber works on a distinct Page object so mutations are safe.
  # File.read yields the fiber, allowing other fibers to proceed with
  # their I/O — this overlaps disk reads and significantly reduces
  # wall-clock time for large numbers of content files.
  private def parse_content_parallel(pages : Array(Models::Page))
    config = ParallelConfig.new(enabled: true)
    worker_count = config.calculate_workers(pages.size)

    done = Channel(Nil).new(pages.size)
    work_queue = Channel(Models::Page).new(pages.size)

    # Enqueue all pages
    pages.each { |page| work_queue.send(page) }
    work_queue.close

    # Track the first classified frontmatter error seen by any worker so
    # the build can abort deterministically after draining the queue.
    classified_error : Hwaro::HwaroError? = nil
    error_mutex = Mutex.new

    # Spawn workers
    worker_count.times do
      spawn do
        while page = work_queue.receive?
          begin
            parse_single_page(page)
          rescue ex : Hwaro::HwaroError
            error_mutex.synchronize do
              classified_error ||= ex
            end
            page.parse_failed = true
          rescue ex
            page.parse_failed = true
            Logger.warn "Failed to parse #{page.path}: #{ex.message}"
          ensure
            # Must run even if a rescue handler raises: a missing send leaves
            # the `pages.size.times { done.receive }` wait below one short and
            # the build hangs instead of surfacing the error.
            done.send(nil)
          end
        end
      end
    end

    # Wait for all pages to finish
    pages.size.times { done.receive }

    # Surface the first classified frontmatter error now that all workers
    # have drained. We prefer this over re-raising inside the worker fiber
    # so the build aborts predictably after the parallel phase completes.
    if err = classified_error
      raise err
    end
  end

  # Front-matter keys a section [cascade] may set on descendants. URL-affecting
  # keys (slug, path, aliases) are excluded: URLs are computed during parsing,
  # before cascades apply, so cascading them would silently not affect URLs.
  CASCADABLE_KEYS = Set{
    "template", "draft", "render", "toc", "insert_anchor_links",
    "in_sitemap", "in_search_index", "tags", "taxonomies", "authors", "extra",
  }

  # Apply section [cascade] tables to descendant pages and sections.
  # Deeper cascades override shallower ones; a page's own front matter
  # (tracked via front_matter_keys) always wins.
  private def apply_cascades(all_pages : Array(Models::Page), sections : Array(Models::Section))
    cascade_map = build_cascade_map(sections)
    # Keep the pre-filter map for incremental passes: sections filtered out
    # later (draft/expired _index) still cascade to their descendants, and
    # reusing the map avoids re-warning about non-cascadable keys per save.
    @cascade_map = cascade_map
    return if cascade_map.empty?

    all_pages.each do |page|
      apply_cascade_to(page, cascade_map)
    end
  end

  # Build {directory, language} => validated cascade map from sections.
  protected def build_cascade_map(sections : Array(Models::Section)) : Hash(Tuple(String, String), Hash(String, Models::ExtraValue))
    map = {} of Tuple(String, String) => Hash(String, Models::ExtraValue)
    sections.each do |section|
      next if section.cascade.empty?

      validated = {} of String => Models::ExtraValue
      section.cascade.each do |key, value|
        if CASCADABLE_KEYS.includes?(key)
          validated[key] = value
        else
          Logger.warn "#{section.path}: cascade key '#{key}' is not cascadable — ignored. Cascadable keys: #{CASCADABLE_KEYS.join(", ")}"
        end
      end
      next if validated.empty?

      dir = Path[section.path].dirname.to_s
      dir = "" if dir == "."
      map[{dir, effective_cascade_language(section)}] = validated
    end
    map
  end

  # Merge ancestor cascades (root → leaf) for `page` and apply the values the
  # page did not set itself. Also stamps `page.cascade_fingerprint` so the
  # build cache invalidates descendants when a parent cascade changes.
  protected def apply_cascade_to(page : Models::Page, cascade_map : Hash(Tuple(String, String), Hash(String, Models::ExtraValue)))
    merged = merged_cascade_for(page, cascade_map)
    page.cascade_fingerprint = merged.empty? ? "" : cascade_fingerprint(merged)
    return if merged.empty?

    merged.each do |key, value|
      case key
      when "extra", "taxonomies"
        # Table keys merge per-subkey even when the page declares its own
        # table — page subkeys win, cascaded subkeys fill the gaps.
      else
        next if page.front_matter_keys.includes?(key)
      end

      case key
      when "template"
        if name = value.as?(String)
          page.template = normalize_template_name(name)
        end
      when "draft"
        value.as?(Bool).try { |b| page.draft = b }
      when "render"
        value.as?(Bool).try { |b| page.render = b }
      when "toc"
        value.as?(Bool).try { |b| page.toc = b }
      when "insert_anchor_links"
        value.as?(Bool).try { |b| page.insert_anchor_links = b }
      when "in_sitemap"
        value.as?(Bool).try { |b| page.in_sitemap = b }
      when "in_search_index"
        value.as?(Bool).try { |b| page.in_search_index = b }
      when "tags"
        # Skip when the page already has tags from a [taxonomies] table —
        # front_matter_keys only guards the top-level `tags` key.
        if (tags = cascade_string_array(value)) && page.tags.empty?
          page.tags = tags
          page.taxonomies["tags"] = tags unless tags.empty?
        end
      when "taxonomies"
        if taxonomies = value.as?(Hash(String, Models::ExtraValue))
          taxonomies.each do |taxonomy_name, terms|
            next if page.taxonomies.has_key?(taxonomy_name)
            # tags/authors also live on dedicated properties, and a top-level
            # `authors` key is never mirrored into page.taxonomies — without
            # these guards a cascaded [cascade.taxonomies] entry would shadow
            # the page's own values in taxonomy aggregation (taxonomy_values
            # prefers the hash). An explicitly declared key wins even when
            # its value is an empty array.
            if taxonomy_name == "tags"
              next if !page.tags.empty? || page.front_matter_keys.includes?("tags")
            elsif taxonomy_name == "authors"
              next if !page.authors.empty? || page.front_matter_keys.includes?("authors")
            end
            next unless term_list = cascade_string_array(terms)
            page.taxonomies[taxonomy_name] = term_list
            page.tags = term_list if taxonomy_name == "tags"
            page.authors = term_list if taxonomy_name == "authors"
          end
        end
      when "authors"
        if (authors = cascade_string_array(value)) && page.authors.empty?
          page.authors = authors
        end
      when "extra"
        if extra = value.as?(Hash(String, Models::ExtraValue))
          extra.each do |extra_key, extra_value|
            page.extra[extra_key] = extra_value unless page.extra.has_key?(extra_key)
          end
        end
      end
    end
  end

  # Collect cascades from the page's ancestor directories, shallowest first,
  # restricted to sections in the same language tree.
  private def merged_cascade_for(page : Models::Page, cascade_map : Hash(Tuple(String, String), Hash(String, Models::ExtraValue))) : Hash(String, Models::ExtraValue)
    dir = Path[page.path].dirname.to_s
    dir = "" if dir == "."

    chain = [""]
    unless dir.empty?
      acc = ""
      dir.split('/').each do |part|
        acc = acc.empty? ? part : "#{acc}/#{part}"
        chain << acc
      end
    end
    # Cascade applies to descendants only — a section's own cascade must not
    # apply to itself.
    chain.pop if page.is_a?(Models::Section)

    language = effective_cascade_language(page)
    merged = {} of String => Models::ExtraValue
    chain.each do |ancestor_dir|
      if cascade = cascade_map[{ancestor_dir, language}]?
        merged.merge!(cascade)
      end
    end
    merged
  end

  # Pages in the default language may carry nil or the default code —
  # normalize so cascade matching doesn't depend on which form a page got.
  private def effective_cascade_language(page : Models::Page) : String
    page.language || @config.try(&.default_language) || ""
  end

  # Cascade values arrive as ExtraValue; tags/taxonomies/authors need plain
  # string arrays. Non-string elements are skipped.
  # Values are stripped to match `fm_string_array` — cascaded taxonomy
  # terms must not become distinct whitespace-padded terms either.
  private def cascade_string_array(value : Models::ExtraValue) : Array(String)?
    if value.is_a?(Array(String))
      value.map(&.strip)
    elsif value.is_a?(Array(Models::ExtraValue))
      value.compact_map(&.as?(String)).map(&.strip)
    end
  end

  # Stable fingerprint of a merged cascade for cache invalidation:
  # hash keys sorted recursively so insertion order never changes the digest.
  protected def cascade_fingerprint(merged : Hash(String, Models::ExtraValue)) : String
    digest = Digest::MD5.new
    fingerprint_cascade_value(digest, merged)
    digest.final.hexstring
  end

  private def fingerprint_cascade_value(digest : Digest::MD5, value : Models::ExtraValue | Hash(String, Models::ExtraValue))
    case value
    when Hash(String, Models::ExtraValue)
      digest.update("{")
      value.keys.sort!.each do |key|
        fingerprint_string(digest, key)
        digest.update("=")
        fingerprint_cascade_value(digest, value[key])
        digest.update(";")
      end
      digest.update("}")
    when Array(String)
      digest.update("[")
      value.each do |item|
        fingerprint_string(digest, item)
        digest.update(",")
      end
      digest.update("]")
    when Array(Models::ExtraValue)
      digest.update("[")
      value.each do |item|
        fingerprint_cascade_value(digest, item)
        digest.update(",")
      end
      digest.update("]")
    else
      digest.update(value.class.name)
      digest.update(":")
      fingerprint_string(digest, value.to_s)
    end
  end

  # Length-prefix strings so values containing the structural delimiters
  # (`=`, `;`, `,`) can't make two different cascades digest identically.
  private def fingerprint_string(digest : Digest::MD5, value : String)
    Utils::DigestUtils.update_length_prefixed(digest, value)
  end

  private def calculate_page_url(page : Models::Page)
    relative_path = page.path
    config = @config

    # Apply permalinks mapping
    directory_path = Path[relative_path].dirname.to_s
    effective_dir = config ? config.resolve_permalink_dir(directory_path) : directory_path

    # For multilingual sites, include language prefix for non-default languages
    lang_prefix = if page.language && config && page.language != config.default_language
                    "/#{page.language}"
                  else
                    ""
                  end

    if custom_path = page.custom_path
      custom = custom_path.lchop("/")
      page.url = "#{lang_prefix}/#{custom}"
      page.url += "/" unless page.url.ends_with?("/")
    elsif page.is_index
      if effective_dir == "." || effective_dir.empty?
        page.url = lang_prefix.empty? ? "/" : "#{lang_prefix}/"
      else
        page.url = "#{lang_prefix}/#{effective_dir}/"
      end
    else
      stem = Path[relative_path].stem

      # Remove language suffix from stem (e.g., "hello-world.ko" -> "hello-world")
      clean_stem = if page.language
                     stem.chomp(".#{page.language}")
                   else
                     stem
                   end

      leaf = page.slug || clean_stem

      if effective_dir == "." || effective_dir.empty?
        page.url = "#{lang_prefix}/#{leaf}/"
      else
        page.url = "#{lang_prefix}/#{effective_dir}/#{leaf}/"
      end
    end
  end
end
