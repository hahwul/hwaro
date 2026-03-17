# Phase: Render — template rendering (sequential/parallel/streaming)
#
# Handles the render phase: building template variables, applying Crinja
# templates to pages, shortcode processing, markdown rendering, pagination,
# and writing rendered HTML to disk. Includes caching for Crinja values
# and compiled templates to minimize allocations during parallel rendering.

module Hwaro::Core::Build::Phases::Render
  private def execute_render_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    site = @site || raise "Site not initialized"
    templates = @templates || raise "Templates not loaded"
    build_cache = @cache || raise "Cache not initialized"
    output_dir = ctx.options.output_dir
    cache_enabled = ctx.options.cache
    parallel = ctx.options.parallel
    minify = ctx.options.minify
    highlight = ctx.options.highlight
    verbose = ctx.options.verbose

    all_pages = ctx.all_pages

    # Filter pages for caching
    pages_to_build = if cache_enabled
                       filter_changed_pages(all_pages, output_dir, build_cache)
                     else
                       all_pages
                     end

    if cache_enabled && pages_to_build.size < all_pages.size
      ctx.stats.cache_hits = all_pages.size - pages_to_build.size
      Logger.info "  Skipping #{ctx.stats.cache_hits} unchanged pages."
    end

    # Determine if syntax highlighting should be used
    # Config setting takes precedence, but can be overridden by CLI flag
    use_highlight = highlight && (site.config.highlight.enabled)

    error_overlay = ctx.options.error_overlay

    profiler.start_phase("Render")
    result = @lifecycle.run_phase(Lifecycle::Phase::Render, ctx) do
      global_vars = build_global_vars(site, ctx.options.cache_busting)
      @pages_by_path = build_pages_by_path(site)
      count = if ctx.options.streaming?
                render_streaming(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay, parallel, ctx.options.batch_size)
              elsif parallel && pages_to_build.size > 1
                process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              else
                process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              end
      ctx.stats.pages_rendered = count
    end
    profiler.end_phase
    result
  end

  private def render_streaming(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    build_cache : Cache,
    use_highlight : Bool,
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value),
    error_overlay : Bool,
    parallel : Bool,
    batch_size : Int32,
  ) : Int32
    total_count = 0
    batch_num = 0

    pages.each_slice(batch_size) do |batch|
      batch_num += 1
      Logger.debug "  Streaming batch #{batch_num} (#{batch.size} pages)"

      count = if parallel && batch.size > 1
                process_files_parallel(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              else
                process_files_sequential(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
              end
      total_count += count

      # Release rendered HTML and per-section/page caches to free memory
      batch.each { |page| page.content = "" }
      @section_pages_crinja_cache.clear
      @section_assets_crinja_cache.clear
      @page_crinja_value_cache.clear
      @ancestors_crinja_cache.clear
      @related_posts_crinja_cache.clear
      GC.collect
    end

    total_count
  end

  private def filter_changed_pages(pages : Array(Models::Page), output_dir : String, cache : Cache) : Array(Models::Page)
    pages.select do |page|
      source_path = File.join("content", page.path)
      output_path = get_output_path(page, output_dir)
      cache.changed?(source_path, output_path)
    end
  end

  private def get_output_path(page : Models::Page, output_dir : String) : String
    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
    output_path = File.join(output_dir, url_path, "index.html")
    Utils::OutputGuard.safe_output_path(output_path, output_dir) || File.join(output_dir, "index.html")
  end

  private def process_files_parallel(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    cache : Cache,
    highlight : Bool,
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value),
    error_overlay : Bool = false,
    profiler : Profiler? = nil,
  ) : Int32
    return 0 if pages.empty?

    config = ParallelConfig.new(enabled: true)
    worker_count = config.calculate_workers(pages.size)
    safe = site.config.markdown.safe

    # Pre-create per-worker Crinja environments and template caches
    # to avoid shared mutable state between concurrent fibers.
    worker_envs = Array.new(worker_count) { create_fresh_crinja_env }
    worker_caches = Array.new(worker_count) { {} of UInt64 => Crinja::Template }

    results = Channel(Bool).new(pages.size)
    work_queue = Channel({Models::Page, Int32}).new(pages.size)

    # Enqueue all work items
    pages.each_with_index { |page, idx| work_queue.send({page, idx}) }
    work_queue.close

    # Spawn workers, each with its own Crinja env and template cache
    worker_count.times do |worker_id|
      env = worker_envs[worker_id]
      tmpl_cache = worker_caches[worker_id]
      spawn do
        while work_item = work_queue.receive?
          page, _idx = work_item
          begin
            page_start = profiler ? Time.instant : nil
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars,
              crinja_env_override: env, template_cache_override: tmpl_cache, error_overlay: error_overlay)
            if profiler && page_start
              elapsed_ms = (Time.instant - page_start).total_milliseconds
              template_name = determine_template(page, templates)
              profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
            end
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.update(source_path, output_path)
            results.send(true)
          rescue ex
            Logger.error "Parallel render failed for #{page.path}: #{ex.message}"
            Logger.debug "  Template: #{determine_template(page, templates)}, Section: #{page.section}"
            Logger.debug "  Backtrace: #{ex.backtrace?.try(&.first(3).join("\n    ")) || "unavailable"}"
            results.send(false)
          end
        end
      end
    end

    # Collect results
    count = 0
    pages.size.times do
      count += 1 if results.receive
    end
    count
  end

  private def process_files_sequential(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    cache : Cache,
    highlight : Bool,
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value),
    error_overlay : Bool = false,
    profiler : Profiler? = nil,
  ) : Int32
    count = 0
    safe = site.config.markdown.safe
    pages.each do |page|
      page_start = profiler ? Time.instant : nil
      render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars, error_overlay: error_overlay)
      if profiler && page_start
        elapsed_ms = (Time.instant - page_start).total_milliseconds
        template_name = determine_template(page, templates)
        profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
      end
      source_path = File.join("content", page.path)
      output_path = get_output_path(page, output_dir)
      cache.update(source_path, output_path)
      count += 1
    end
    count
  end

  private def render_page(
    page : Models::Page,
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    minify : Bool,
    highlight : Bool = true,
    safe : Bool = false,
    verbose : Bool = false,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    error_overlay : Bool = false,
  )
    return unless page.render

    # Clear warnings from previous renders (important for incremental rebuilds)
    page.build_warnings.clear

    # Handle redirect_to for pages AND sections
    if page.has_redirect?
      generate_redirect_page(page, output_dir, verbose)
      generate_aliases(page, output_dir, verbose)
      return
    end

    # Only build shortcode context and process shortcodes if content actually
    # contains shortcode syntax ({{ or {%).  This avoids the expensive
    # build_template_variables call for the majority of pages that have no
    # shortcodes.
    shortcode_results = {} of String => String
    raw = page.raw_content
    has_shortcodes = raw.includes?("{{") || raw.includes?("{%")
    shortcode_context : Hash(String, Crinja::Value)? = nil

    processed_content = if has_shortcodes
                          shortcode_context = build_template_variables(page, site, "", "", "", "", nil, nil, global_vars)
                          process_shortcodes_jinja(raw, templates, shortcode_context, shortcode_results,
                            crinja_env_override: crinja_env_override)
                        else
                          raw
                        end

    lazy_loading = site.config.markdown.lazy_loading
    emoji = site.config.markdown.emoji

    # Use anchor links if enabled
    md_config = site.config.markdown
    html_content, toc_headers = if page.insert_anchor_links
                                  Content::Processors::Markdown.new.render_with_anchors(processed_content, highlight, safe, "after", lazy_loading, emoji, markdown_config: md_config)
                                else
                                  Processor::Markdown.render(processed_content, highlight, safe, lazy_loading, emoji, markdown_config: md_config)
                                end

    # Replace shortcode placeholders with their rendered HTML content
    html_content = replace_shortcode_placeholders(html_content, shortcode_results)

    # Resolve internal @/ links to actual page URLs
    if pages_by_path = @pages_by_path
      html_content = Content::Processors::InternalLinkResolver.resolve(html_content, pages_by_path, page.path)
    end

    # Store rendered HTML in page.content for reuse by Feed/Search generators
    # (avoids expensive re-rendering of Markdown in Generate phase)
    page.content = html_content

    toc_html = if page.toc && !toc_headers.empty?
                 generate_toc_html(toc_headers)
               else
                 ""
               end

    template_name = determine_template(page, templates)
    template_content = templates[template_name]? || templates["page"]?
    Logger.debug "Rendering #{page.path} (section=#{page.section.empty? ? "<root>" : page.section}, index=#{page.is_index}) using template '#{template_name}'" if verbose

    # Handle section pages with pagination
    if (template_name == "section" || page.template == "section") && page.is_a?(Models::Section)
      render_section_with_pagination(page.as(Models::Section), site, templates, template_content, output_dir, minify, html_content, toc_html, verbose, global_vars,
        crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, error_overlay: error_overlay)
    else
      section_list_html = ""

      final_html = if template_content
                     apply_template(template_content, html_content, page, site, section_list_html, toc_html, templates, global_vars: global_vars,
                       crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
                       prebuilt_vars: shortcode_context)
                   else
                     msg = "No template found for #{page.path}. Using raw content."
                     Logger.warn "#{msg}"
                     page.build_warnings << msg unless page.build_warnings.includes?(msg)
                     html_content
                   end

      if error_overlay && !page.build_warnings.empty?
        final_html = inject_error_overlay(final_html, page.build_warnings)
      end

      final_html = minify_html(final_html) if minify

      write_output(page, output_dir, final_html, verbose)
    end

    generate_aliases(page, output_dir, verbose)
  end

  private def generate_redirect_page(
    page : Models::Page,
    output_dir : String,
    verbose : Bool = false,
  )
    redirect_url = page.redirect_to
    return unless redirect_url

    output_path = File.join(output_dir, page.url.lchop("/"), "index.html")
    ensure_dir(Path[output_path].dirname.to_s)
    File.write(output_path, Utils::RedirectHtml.full_redirect(redirect_url))
    Logger.action :create, output_path if verbose
  end

  private def render_section_with_pagination(
    section : Models::Section,
    site : Models::Site,
    templates : Hash(String, String),
    template_content : String?,
    output_dir : String,
    minify : Bool,
    html_content : String,
    toc_html : String,
    verbose : Bool = false,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    error_overlay : Bool = false,
  )
    # Get pages in this section using the site utility method
    # Note: sorting is handled by Paginator.paginate (uses section.sort_by setting)
    section_name = Path[section.path].dirname
    section_name = "" if section_name == "."
    section_pages = site.pages_for_section(section_name, section.language)

    # Create paginator and render
    paginator = Content::Pagination::Paginator.new(site.config)
    pagination_result = paginator.paginate(section, section_pages)
    renderer = Content::Pagination::Renderer.new(site.config)

    pagination_result.paginated_pages.each do |paginated_page|
      section_list_html = renderer.render_section_list(paginated_page)
      pagination_nav_html = renderer.render_pagination_nav(paginated_page)
      pagination_seo_links = renderer.render_seo_links(paginated_page)

      # Use the correct URL for each paginated page during rendering (important for SEO tags, nav, etc.)
      base = section.url.rstrip("/")
      current_url = if paginated_page.page_number == 1
                      "#{base}/"
                    else
                      "#{base}/#{section.paginate_path}/#{paginated_page.page_number}/"
                    end

      final_html = if template_content
                     apply_template(template_content, html_content, section, site, section_list_html, toc_html, templates, pagination_nav_html, current_url, paginated_page, global_vars,
                       crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, pagination_seo_links: pagination_seo_links)
                   else
                     msg = "No template found for #{section.path}. Using raw content."
                     Logger.warn "#{msg}"
                     section.build_warnings << msg unless section.build_warnings.includes?(msg)
                     html_content
                   end

      if error_overlay && !section.build_warnings.empty?
        final_html = inject_error_overlay(final_html, section.build_warnings)
      end

      final_html = minify_html(final_html) if minify

      # Write output - first page uses section URL, subsequent pages use /page/N/
      if paginated_page.page_number == 1
        write_output(section, output_dir, final_html, verbose)
      else
        write_paginated_output(section, paginated_page.page_number, output_dir, final_html, verbose, section.paginate_path)
      end
    end
  end

  private def write_paginated_output(page : Models::Page, page_number : Int32, output_dir : String, content : String, verbose : Bool, paginate_path : String = "page")
    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/").rstrip("/"))
    output_path = File.join(output_dir, url_path, paginate_path, page_number.to_s, "index.html")
    return unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)

    ensure_dir(Path[output_path].dirname.to_s)
    File.write(output_path, content)
    Logger.action :create, output_path if verbose
  end

  private def determine_template(page : Models::Page, templates : Hash(String, String)) : String
    if custom = page.template
      return custom if templates.has_key?(custom)
      msg = "Custom template '#{custom}' not found for #{page.path}. Falling back to default."
      Logger.warn "#{msg}"
      page.build_warnings << msg unless page.build_warnings.includes?(msg)
    end

    if page.is_a?(Models::Section)
      return "section" if templates.has_key?("section")
    end

    if page.is_index && page.section.empty? && templates.has_key?("index")
      return "index"
    end

    "page"
  end

  private def generate_aliases(page : Models::Page, output_dir : String, verbose : Bool)
    page.aliases.each do |alias_path|
      alias_clean = Utils::PathUtils.sanitize_path(alias_path.lchop("/"))
      dest_path = File.join(output_dir, alias_clean, "index.html")
      next unless Utils::OutputGuard.within_output_dir?(dest_path, output_dir)

      ensure_dir(File.dirname(dest_path))

      redirect_url = page.redirect_to || page.url
      File.write(dest_path, Utils::RedirectHtml.simple_redirect(redirect_url))
      Logger.action :create, dest_path, :yellow if verbose
    end
  end

  private def generate_toc_html(headers : Array(Models::TocHeader)) : String
    return "" if headers.empty?

    String.build do |str|
      str << "<ul>"
      headers.each do |header|
        str << "<li><a href=\"#{header.permalink}\">#{header.title}</a>"
        unless header.children.empty?
          str << generate_toc_html(header.children)
        end
        str << "</li>"
      end
      str << "</ul>"
    end
  end

  # Inject a dismissible error overlay into the HTML page for development feedback.
  # The overlay shows build warnings collected during rendering so developers
  # can spot template issues directly in the browser.
  private def inject_error_overlay(html : String, warnings : Array(String)) : String
    return html if warnings.empty?

    escaped_warnings = warnings.map { |w| HTML.escape(w) }
    list_items = escaped_warnings.map { |w|
      "<li style=\"margin-bottom:8px;line-height:1.5;\">#{w}</li>"
    }.join("\n")

    overlay = <<-OVERLAY
    <div id="hwaro-error-overlay" style="position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:-apple-system,BlinkMacSystemFont,sans-serif;">
      <div style="background:#1e1e2e;color:#cdd6f4;border-radius:8px;padding:24px;max-width:720px;width:90%;max-height:80vh;overflow-y:auto;box-shadow:0 8px 32px rgba(0,0,0,0.4);">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
          <h2 style="margin:0;color:#f38ba8;font-size:18px;">Build Warning</h2>
          <button onclick="document.getElementById('hwaro-error-overlay').remove()" style="background:none;border:none;color:#cdd6f4;font-size:24px;cursor:pointer;padding:0 4px;">&times;</button>
        </div>
        <ul style="margin:0;padding:0 0 0 20px;">
          #{list_items}
        </ul>
      </div>
    </div>
    OVERLAY

    # Inject before </body> if present, otherwise append
    if idx = html.rindex("</body>")
      html.insert(idx, overlay)
    else
      html + overlay
    end
  end

  def apply_template(
    template : String,
    content : String,
    page : Models::Page,
    site : Models::Site,
    section_list : String,
    toc : String,
    templates : Hash(String, String),
    pagination : String = "",
    page_url_override : String? = nil,
    paginator : Content::Pagination::PaginatedPage? = nil,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    pagination_seo_links : String = "",
    prebuilt_vars : Hash(String, Crinja::Value)? = nil,
  ) : String
    # Use per-worker env when provided (parallel path), otherwise shared env
    env = crinja_env_override || crinja_env
    cache = template_cache_override || @compiled_templates_cache

    # Build template variables — reuse prebuilt_vars if available (shortcode path)
    vars = if pv = prebuilt_vars
             update_content_vars(pv, content, section_list, toc, pagination, pagination_seo_links)
             pv
           else
             build_template_variables(page, site, content, section_list, toc, pagination, page_url_override, paginator, global_vars, pagination_seo_links: pagination_seo_links)
           end

    begin
      # Process shortcodes in template directly (skip per-line fence detection
      # since templates don't contain markdown fenced code blocks)
      processed_template = process_shortcodes_in_text(template, templates, vars,
        crinja_env_override: crinja_env_override)

      # Cache compiled Crinja templates by content hash.
      # Most pages share the same base template string, so this avoids
      # re-parsing the template AST on every page render.
      cache_key = processed_template.hash
      crinja_template = cache[cache_key]? || begin
        compiled = env.from_string(processed_template)
        cache[cache_key] = compiled
        compiled
      end
      crinja_template.render(vars)
    rescue ex : Crinja::TemplateNotFoundError
      msg = "Template error for #{page.path}: #{ex.message}"
      Logger.warn "#{msg}"
      page.build_warnings << msg unless page.build_warnings.includes?(msg)
      content
    rescue ex : Crinja::Error
      msg = "Template error for #{page.path}: #{ex.message}"
      Logger.warn "#{msg}"
      page.build_warnings << msg unless page.build_warnings.includes?(msg)
      content
    end
  end

  # Update only content-dependent vars in a pre-built template variables hash.
  # Used to avoid rebuilding the entire variables hash when only content/toc/pagination change
  # (e.g., reusing shortcode context for final template rendering).
  private def update_content_vars(
    vars : Hash(String, Crinja::Value),
    content : String,
    section_list : String,
    toc : String,
    pagination : String,
    pagination_seo_links : String,
  )
    vars["content"] = Crinja::Value.new(content)
    vars["section_list"] = Crinja::Value.new(section_list)
    vars["toc"] = Crinja::Value.new(toc)
    vars["toc_obj"] = Crinja::Value.new({"html" => Crinja::Value.new(toc)})
    vars["pagination"] = Crinja::Value.new(pagination)
    vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)
  end

  # Unified Page→Crinja::Value conversion with per-page caching.
  # Avoids repeated conversion of the same Page across build_global_vars,
  # section page lists, and paginator rendering.  The cached value contains
  # a superset of fields needed by all consumers.
  private def cached_page_crinja_value(p : Models::Page, default_language : String) : Crinja::Value
    @crinja_cache_mutex.synchronize do
      @page_crinja_value_cache[p.path]? || begin
        val = Crinja::Value.new({
          "path"         => Crinja::Value.new(p.path),
          "title"        => Crinja::Value.new(p.title),
          "description"  => Crinja::Value.new(p.description || ""),
          "url"          => Crinja::Value.new(p.url),
          "date"         => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
          "image"        => Crinja::Value.new(p.image || ""),
          "section"      => Crinja::Value.new(p.section),
          "draft"        => Crinja::Value.new(p.draft),
          "toc"          => Crinja::Value.new(p.toc),
          "render"       => Crinja::Value.new(p.render),
          "is_index"     => Crinja::Value.new(p.is_index),
          "generated"    => Crinja::Value.new(p.generated),
          "in_sitemap"   => Crinja::Value.new(p.in_sitemap),
          "language"     => Crinja::Value.new(p.language || default_language),
          "weight"       => Crinja::Value.new(p.weight),
          "summary"      => Crinja::Value.new(p.effective_summary || ""),
          "word_count"   => Crinja::Value.new(p.word_count),
          "reading_time" => Crinja::Value.new(p.reading_time),
          "tags"         => Crinja::Value.new(p.tags.map { |t| Crinja::Value.new(t) }),
          "authors"      => Crinja::Value.new(p.authors.map { |a| Crinja::Value.new(a) }),
          "assets"       => Crinja::Value.new(p.assets.map { |a| Crinja::Value.new(a) }),
        })
        @page_crinja_value_cache[p.path] = val
        val
      end
    end
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
    cache_key = "#{section_name}:#{language}"
    @crinja_cache_mutex.synchronize do
      @section_pages_crinja_cache[cache_key]? || begin
        pages = site.pages_for_section(section_name, language)

        # Use section's sort_by setting if available, otherwise sort by title
        section = site.sections_by_name[section_name]?
        sort_by = section.try(&.sort_by) || "title"
        reverse = section.try(&.reverse) || false
        pages = Utils::SortUtils.sort_pages(pages, sort_by, reverse)

        default_lang = site.config.default_language
        arr = pages.map { |p| page_to_crinja_list_value(p, default_lang) }
        @section_pages_crinja_cache[cache_key] = arr
        arr
      end
    end
  end

  # Build a lookup map from content path → Page for internal link resolution.
  private def build_pages_by_path(site : Models::Site) : Hash(String, Models::Page)
    map = {} of String => Models::Page
    site.pages.each { |p| map[p.path] ||= p }
    site.sections.each { |s| map[s.path] ||= s }
    map
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

    site.sections.each do |s|
      section_pages = s.pages.map do |sp|
        # Reuse cached page values (contains title/url/date and more)
        cached_page_crinja_value(sp, default_lang)
      end
      section_val = Crinja::Value.new({
        "path"        => Crinja::Value.new(s.path),
        "name"        => Crinja::Value.new(s.section),
        "title"       => Crinja::Value.new(s.title),
        "description" => Crinja::Value.new(s.description || ""),
        "url"         => Crinja::Value.new(s.url),
        "pages"       => Crinja::Value.new(section_pages),
        "pages_count" => Crinja::Value.new(s.pages.size),
        "assets"      => Crinja::Value.new(s.assets.map { |a| Crinja::Value.new(a) }),
      })
      all_sections_array << section_val

      # Build O(1) lookup map for get_section() — match by path, name, and URL
      sections_by_key[s.path] ||= section_val
      sections_by_key[s.section] ||= section_val unless s.section.empty?
      sections_by_key[s.url] ||= section_val
    end
    vars["__all_sections__"] = Crinja::Value.new(all_sections_array)
    vars["__sections_by_key__"] = Crinja::Value.new(sections_by_key)

    # Build taxonomies hash for get_taxonomy function
    taxonomies_hash = {} of String => Crinja::Value
    site.taxonomies.each do |name, terms|
      terms_array = terms.map do |term, term_pages|
        term_pages_array = term_pages.map do |tp|
          cached_page_crinja_value(tp, default_lang)
        end
        Crinja::Value.new({
          "name"  => Crinja::Value.new(term),
          "slug"  => Crinja::Value.new(Utils::TextUtils.slugify(term)),
          "pages" => Crinja::Value.new(term_pages_array),
          "count" => Crinja::Value.new(term_pages.size),
        })
      end
      taxonomies_hash[name] = Crinja::Value.new({
        "name"  => Crinja::Value.new(name),
        "items" => Crinja::Value.new(terms_array),
      })
    end
    vars["__taxonomies__"] = Crinja::Value.new(taxonomies_hash)

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

  # Compute a content-based cache bust hash from local CSS/JS files.
  # Returns an 8-character hex digest, or "" if no local files exist.
  private def compute_cache_bust(config : Models::Config) : String
    has_local_highlight = config.highlight.enabled && !config.highlight.use_cdn
    has_auto_includes = config.auto_includes.enabled && config.auto_includes.dirs.any?

    return "" unless has_local_highlight || has_auto_includes

    digest = Digest::MD5.new

    if has_local_highlight
      css_path = File.join("static", "assets", "css", "highlight", "#{config.highlight.theme}.min.css")
      digest_file(digest, css_path) if File.exists?(css_path)
      js_path = File.join("static", "assets", "js", "highlight.min.js")
      digest_file(digest, js_path) if File.exists?(js_path)
    end

    if has_auto_includes
      config.auto_includes.dirs.each do |dir|
        static_dir = File.join("static", dir)
        next unless Dir.exists?(static_dir)
        Dir.glob(File.join(static_dir, "**", "*.{css,js}")).sort.each do |file|
          digest_file(digest, file)
        end
      end
    end

    digest.hexfinal[0, 8]
  end

  # Stream file contents into digest to avoid loading entire file into memory
  private def digest_file(digest : Digest::MD5, path : String)
    File.open(path, "r") do |io|
      buffer = Bytes.new(8192)
      while (n = io.read(buffer)) > 0
        digest.update(buffer[0, n])
      end
    end
  end

  # Build template variables hash for Crinja
  private def build_template_variables(
    page : Models::Page,
    site : Models::Site,
    content : String,
    section_list : String,
    toc : String,
    pagination : String = "",
    page_url_override : String? = nil,
    paginator : Content::Pagination::PaginatedPage? = nil,
    global_vars : Hash(String, Crinja::Value)? = nil,
    pagination_seo_links : String = "",
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

    translations = page.translations.map do |t|
      Crinja::Value.new(
        {
          "code"       => Crinja::Value.new(t.code),
          "url"        => Crinja::Value.new(t.url),
          "title"      => Crinja::Value.new(t.title),
          "is_current" => Crinja::Value.new(t.is_current),
          "is_default" => Crinja::Value.new(t.is_default),
        }
      )
    end
    vars["page_translations"] = Crinja::Value.new(translations)

    # Generate permalink only if not already set
    page.generate_permalink(config.base_url) unless page.permalink

    # Reuse cached Crinja arrays for tags/authors/assets (avoids per-page .map allocation)
    cached_page_val = cached_page_crinja_value(page, default_lang)
    cached_raw = cached_page_val.raw.as(Hash)
    tags_crinja = cached_raw["tags"].as(Crinja::Value)
    authors_crinja = cached_raw["authors"].as(Crinja::Value)
    assets_crinja = cached_raw["assets"].as(Crinja::Value)

    # Convert extra to Crinja hash
    extra_hash = {} of String => Crinja::Value
    page.extra.each do |k, v|
      extra_hash[k] = Utils::CrinjaUtils.from_extra(v)
    end

    # Reuse cached Crinja::Value for lower/higher pages
    lower_obj = page.lower.try { |l| cached_page_crinja_value(l, default_lang) }
    higher_obj = page.higher.try { |h| cached_page_crinja_value(h, default_lang) }

    # Build ancestors array (cached per section — pages in the same section share ancestors)
    ancestors_cache_key = page.section
    ancestors_array = @crinja_cache_mutex.synchronize do
      @ancestors_crinja_cache[ancestors_cache_key]? || begin
        arr = page.ancestors.map do |ancestor|
          Crinja::Value.new({
            "title" => Crinja::Value.new(ancestor.title),
            "url"   => Crinja::Value.new(ancestor.url),
          })
        end
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
      "in_sitemap"   => Crinja::Value.new(page.in_sitemap),
      "language"     => Crinja::Value.new(page_language),
      "translations" => Crinja::Value.new(translations),
      # New properties
      "authors"         => authors_crinja,
      "tags"            => tags_crinja,
      "assets"          => assets_crinja,
      "extra"           => Crinja::Value.new(extra_hash),
      "summary"         => Crinja::Value.new(page.effective_summary || ""),
      "word_count"      => Crinja::Value.new(page.word_count),
      "reading_time"    => Crinja::Value.new(page.reading_time),
      "permalink"       => Crinja::Value.new(page.permalink || ""),
      "weight"          => Crinja::Value.new(page.weight),
      "in_search_index" => Crinja::Value.new(page.in_search_index),
      "lower"           => lower_obj || Crinja::Value.new(nil),
      "higher"          => higher_obj || Crinja::Value.new(nil),
      "ancestors"       => Crinja::Value.new(ancestors_array),
      "series"          => Crinja::Value.new(page.series || ""),
      "series_index"    => Crinja::Value.new(page.series_index),
      "series_pages"    => @crinja_cache_mutex.synchronize {
        page.series.try { |s| @series_crinja_cache[s]? } || begin
          val = Crinja::Value.new(page.series_pages.map { |sp|
            cached_page_crinja_value(sp, default_lang)
          })
          page.series.try { |s| @series_crinja_cache[s] = val }
          val
        end
      },
      "related_posts" => @crinja_cache_mutex.synchronize {
        @related_posts_crinja_cache[page.path]? || begin
          val = Crinja::Value.new(page.related_posts.map { |rp|
            cached_page_crinja_value(rp, default_lang)
          })
          @related_posts_crinja_cache[page.path] = val
          val
        end
      },
    }
    vars["page"] = Crinja::Value.new(page_obj)

    # Flat variables for new properties
    vars["page_summary"] = Crinja::Value.new(page.effective_summary || "")
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

      # Build subsections array
      subsections_array = page.subsections.map do |sub|
        Crinja::Value.new({
          "title"       => Crinja::Value.new(sub.title),
          "description" => Crinja::Value.new(sub.description || ""),
          "url"         => Crinja::Value.new(sub.url),
          "pages_count" => Crinja::Value.new(sub.pages.size),
        })
      end

      # Use the page's assets as section assets
      section_assets_val = assets_crinja
    elsif !page.section.empty?
      # For regular pages, find the parent section via O(1) lookup
      section_page = site.sections_by_name[page.section]?
      if section_page
        section_title = section_page.title
        section_description = section_page.description || ""
        current_section = page.section
        # Use cached section assets to avoid re-allocating per page
        section_assets_val = @crinja_cache_mutex.synchronize do
          @section_assets_crinja_cache[page.section]?.try { |arr| Crinja::Value.new(arr) } || begin
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
      else
        # Non-paginated: use per-section cache, then exclude current page.
        # Find index once, then build result skipping that slot (pre-sized array avoids realloc).
        all_section = cached_section_pages_crinja(current_section, page.language, site)
        page_url_str = page.url
        skip_idx = all_section.index do |v|
          raw = v.raw
          raw.is_a?(Hash) && raw["url"]?.try(&.to_s) == page_url_str
        end
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
    # - toc.html (structured access to the same HTML)
    vars["toc"] = Crinja::Value.new(toc)
    toc_obj = {
      "html" => Crinja::Value.new(toc),
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
        "total_pages"   => Crinja::Value.new(paginator.total_items),
      }
      vars["paginator"] = Crinja::Value.new(paginator_obj)
    end

    # NOTE: highlight_css/js/tags and auto_includes_css/js are now in
    # global_vars (computed once in build_global_vars).

    # OG/Twitter tags (page-specific — depend on page title/description/url/image)
    og_tags = config.og.og_tags(page.title, page.description, effective_url, page.image, config.base_url)
    twitter_tags = config.og.twitter_tags(page.title, page.description, page.image, config.base_url)
    og_all_tags = if og_tags.empty?
                    twitter_tags
                  elsif twitter_tags.empty?
                    og_tags
                  else
                    "#{og_tags}\n#{twitter_tags}"
                  end
    vars["og_tags"] = Crinja::Value.new(og_tags)
    vars["twitter_tags"] = Crinja::Value.new(twitter_tags)
    vars["og_all_tags"] = Crinja::Value.new(og_all_tags)

    # Canonical and Hreflang tags
    canonical_tag = Content::Seo::Tags.canonical_tag(page, config)
    hreflang_tags = Content::Seo::Tags.hreflang_tags(page, config)
    vars["canonical_tag"] = Crinja::Value.new(canonical_tag)
    vars["hreflang_tags"] = Crinja::Value.new(hreflang_tags)

    # JSON-LD structured data — generate breadcrumb only when needed
    jsonld_article = Content::Seo::JsonLd.article(page, config)
    needs_breadcrumb = !page.ancestors.empty? || !page.is_index
    jsonld_breadcrumb = needs_breadcrumb ? Content::Seo::JsonLd.breadcrumb(page, config) : ""

    # Extended schema types (FAQ, HowTo) auto-detected from extra.schema_type
    jsonld_extra = Content::Seo::JsonLd.for_page(page, config)

    jsonld_parts = [jsonld_article]
    jsonld_parts << jsonld_breadcrumb unless jsonld_breadcrumb.empty?
    jsonld_parts << jsonld_extra unless jsonld_extra.empty?
    jsonld_all = jsonld_parts.join("\n")

    vars["jsonld_article"] = Crinja::Value.new(jsonld_article)
    vars["jsonld_breadcrumb"] = Crinja::Value.new(jsonld_breadcrumb)
    # Only compute FAQ/HowTo JSON-LD when schema_type indicates it (avoids
    # per-page hash lookups + array allocations for the common case)
    schema_type_raw = page.extra["schema_type"]?.try(&.as?(String)) || ""
    schema_lower = schema_type_raw.downcase
    vars["jsonld_faq"] = Crinja::Value.new(
      schema_lower == "faqpage" || schema_lower == "faq" ? Content::Seo::JsonLd.faq_page(page, config) : ""
    )
    vars["jsonld_howto"] = Crinja::Value.new(
      schema_lower == "howto" || schema_lower == "how-to" ? Content::Seo::JsonLd.how_to(page, config) : ""
    )
    vars["jsonld"] = Crinja::Value.new(jsonld_all)

    # Merge global vars at the end.  Page-specific keys (written above)
    # take precedence because they were set first; merge! only adds keys
    # that don't already exist when we reverse the direction below.
    gv = global_vars || build_global_vars(site)
    gv.each { |k, v| vars[k] = v unless vars.has_key?(k) }

    vars
  end

  private def minify_html(html : String) : String
    Utils::HtmlMinifier.minify(html)
  end
end
