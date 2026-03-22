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
      # Default parsing if no hooks registered
      unless @lifecycle.has_hooks?(Lifecycle::HookPoint::AfterReadContent)
        parse_content_default(ctx)
      end
    end
    profiler.end_phase
    return result if result != Lifecycle::HookResult::Continue

    # Link multilingual translations between pages/sections (for language switchers)
    if config = ctx.config
      Content::Multilingual.link_translations!(ctx.all_pages, config)
    end

    # Link lower/higher page navigation and build ancestors
    link_page_navigation(ctx)
    build_subsections(ctx)
    collect_assets(ctx)
    populate_taxonomies(ctx)

    Lifecycle::HookResult::Continue
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

    # Single-pass filtering: remove parse-failed, draft, and expired pages.
    # Combines multiple reject! calls into one pass per array to avoid
    # repeated traversals, and calls invalidate_all_pages_cache at most once.
    include_drafts = ctx.options.drafts
    filter_expired = !ctx.options.include_expired
    now = filter_expired ? Time.utc : Time.utc # evaluated once
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
    expired_count = 0

    filter = ->(p : Models::Page) do
      if p.parse_failed
        failed_count += 1
        true
      elsif !include_drafts && p.draft
        true
      elsif filter_expired && (p.expires.try { |e| e <= now } || false)
        expired_count += 1
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

    Logger.warn "  #{failed_count} page(s) skipped due to parse errors." if failed_count > 0
    Logger.info "  Excluded #{expired_count} expired page#{"s" if expired_count > 1}" if expired_count > 0

    # Show included draft content paths when --drafts flag is used
    if include_drafts
      draft_pages = ctx.all_pages.select(&.draft)
      if draft_pages.size > 0
        max_url_len = draft_pages.max_of { |p| p.url.size }
        pad = {max_url_len, 24}.max
        Logger.info "Including #{draft_pages.size} draft(s):"
        draft_pages.each do |p|
          Logger.info "  #{p.url.ljust(pad)} <- content/#{p.path}"
        end
      end
    end
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
    page.template = data[:template]
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

    # Extract summary from <!-- more --> marker
    page.extract_summary

    if page.is_a?(Models::Section)
      page.transparent = data[:transparent]
      page.generate_feeds = data[:generate_feeds]
      page.paginate = data[:paginate]
      page.pagination_enabled = data[:pagination_enabled]
      page.sort_by = data[:sort_by]
      page.reverse = data[:reverse]
      page.page_template = data[:page_template]
      page.paginate_path = data[:paginate_path]
    end

    # Calculate URL
    calculate_page_url(page)
  end

  private def parse_content_sequential(pages : Array(Models::Page))
    pages.each do |page|
      begin
        parse_single_page(page)
      rescue ex
        page.parse_failed = true
        Logger.warn "Failed to parse #{page.path}: #{ex.message}"
      end
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

    # Spawn workers
    worker_count.times do
      spawn do
        while page = work_queue.receive?
          begin
            parse_single_page(page)
          rescue ex
            page.parse_failed = true
            Logger.warn "Failed to parse #{page.path}: #{ex.message}"
          end
          done.send(nil)
        end
      end
    end

    # Wait for all pages to finish
    pages.size.times { done.receive }
  end

  private def calculate_page_url(page : Models::Page)
    relative_path = page.path
    config = @config

    # Apply permalinks mapping
    directory_path = Path[relative_path].dirname.to_s
    effective_dir = directory_path

    if config
      config.permalinks.each do |source, target|
        if directory_path == source
          effective_dir = target
          break
        elsif directory_path.starts_with?("#{source}/")
          effective_dir = target + directory_path[source.size..]
          break
        end
      end
    end

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
