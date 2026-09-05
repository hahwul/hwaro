# Render phase — per-page pipeline (cache hydration, content render, template selection).
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Does anything after the render phase read a cache-hit page's `content`?
  #
  # The Generate phase's skip (`generate_outputs_unchanged?`) is not the
  # only consumer:
  #   * the taxonomy hook (BeforeGenerate) regenerates every term page AND
  #     every per-term feed on every build, skip or no skip, and the feeds
  #     read `page.content` — an all-hit warm build with `taxonomy.feed`
  #     shipped raw `{% shortcode %}` markup into `tags/<term>/rss.xml`;
  #   * `serve` keeps the Builder alive: its incremental rebuilds regenerate
  #     search.json / feeds / taxonomy pages from the in-memory page set
  #     after every edit, so a `serve --cache` whose start was an all-hit
  #     build served corrupted search.json and feeds from the first edit on.
  #   * `generate_seo_outputs` never lets the feeds join the skip while a
  #     user feed template exists (`feed_template_present?`), so an all-hit
  #     warm build still regenerates rss.xml — from `page.content`. Without
  #     hydration that feed carried raw shortcode markup, unresolved `@/`
  #     links and no base_path: the exact corruption #775 fixed, back on the
  #     one site shape that overrides the feed template.
  private def cached_content_needed?(ctx : Lifecycle::BuildContext, site : Models::Site) : Bool
    return true unless generate_outputs_unchanged?(ctx)
    return true if ctx.options.serve_mode
    return true if feed_template_present?
    site.config.taxonomies.any?(&.feed)
  end

  # Populate `page.content` for cache-hit pages on a warm `--cache` build.
  #
  # The render phase only runs `render_page` for pages whose cache entry is
  # stale, so cache hits reach the Generate phase with an empty `content`.
  # The search index and the feeds then fell back to a markdown-only render
  # of `raw_content` — no shortcode expansion, no `@/` link resolution, no
  # base_path prefix — and search.json / rss.xml carried raw `{% gal() %}`
  # markup for every cached page (`hwaro build --cache` twice on any site
  # with a block shortcode; also 4 pages of docs/). Running the same content
  # pipeline a render runs, minus the template + write, makes a warm build's
  # generated outputs byte-identical to a clean build's. Fans out across the
  # same per-worker Crinja envs the render uses; a failure hydrating one page
  # is logged and leaves that page on the old fallback rather than failing a
  # build whose page output already succeeded.
  private def hydrate_cached_page_content(
    pages : Array(Models::Page),
    site : Models::Site,
    templates : Hash(String, String),
    highlight : Bool,
    global_vars : Hash(String, Crinja::Value),
    parallel : Bool,
  ) : Nil
    pages = pages.select { |page| page.render && !page.has_redirect? }
    return if pages.empty?
    safe = site.config.markdown.safe

    hydrate = ->(page : Models::Page, env : Crinja?, cache : Hash(UInt64, Crinja::Template)?) do
      # Same reset `render_page` does: shortcode warnings are re-collected by
      # the content pass, so a page hydrated on every serve rebuild must not
      # accumulate duplicates.
      page.build_warnings.clear
      render_page_content(page, site, templates, highlight, safe, global_vars,
        crinja_env_override: env, template_cache_override: cache)
  rescue ex
    # Loud, not debug: the page's HTML is already correct (it was a cache
    # hit), but its search.json / feed entry now comes from the raw-markdown
    # fallback — the corruption this pass exists to prevent — and the build
    # still exits 0, so the log line is the only trace.
    Logger.warn "Could not re-render cached content for #{page.path}: #{ex.message}. Its search index and feed entries fall back to unprocessed markdown for this build; run without --cache to refresh them."
    end

    if parallel && pages.size > 1
      worker_count = render_worker_count(pages, site, templates, pages.size)
      worker_envs = Array.new(worker_count) { create_fresh_crinja_env }
      worker_caches = Array.new(worker_count) { {} of UInt64 => Crinja::Template }
      work_queue = Channel(Models::Page).new(pages.size)
      pages.each { |page| work_queue.send(page) }
      work_queue.close
      done = Channel(Nil).new(pages.size)
      worker_count.times do |worker_id|
        spawn do
          while page = work_queue.receive?
            begin
              hydrate.call(page, worker_envs[worker_id], worker_caches[worker_id])
            ensure
              done.send(nil)
            end
          end
        end
      end
      pages.size.times { done.receive }
    else
      pages.each { |page| hydrate.call(page, nil, nil) }
    end
  end

  # The content half of a page render: shortcodes → markdown → placeholder
  # restore → internal-link resolution → subpath prefix → responsive images.
  # Sets `page.content` and returns the HTML, the TOC headers and the template
  # variables the shortcode pass built (so `apply_template` can reuse them).
  #
  # Split out of `render_page` so `hydrate_cached_page_content` can produce
  # exactly what a real render produces for pages a warm `--cache` build
  # skips: the search index and the feeds read `page.content`, and their
  # markdown-only fallback (no shortcodes, no link resolution, no base_path)
  # shipped raw `{% shortcode %}` markup into search.json / rss.xml.
  private def render_page_content(
    page : Models::Page,
    site : Models::Site,
    templates : Hash(String, String),
    highlight : Bool,
    safe : Bool,
    global_vars : Hash(String, Crinja::Value)?,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    profiler : Profiler? = nil,
  ) : {String, Array(Models::TocHeader), Hash(String, Crinja::Value)?}
    # Only build shortcode context and process shortcodes if content actually
    # contains shortcode syntax ({{ or {%).  This avoids the expensive
    # build_template_variables call for the majority of pages that have no
    # shortcodes.
    shortcode_results = {} of String => String
    raw = page.raw_content
    # Use accurate fence + inline-code aware pre-filter instead of naive includes?.
    # This is the main D2 optimization for the shortcode hot path (#562):
    # documentation pages full of example syntax no longer pay the cost of
    # build_template_variables + full shortcode processing.
    has_shortcodes = content_may_contain_shortcodes?(raw)
    warn_hugo_shortcode_syntax(raw, page.path) if raw.includes?("{{<")
    shortcode_context : Hash(String, Crinja::Value)? = nil

    processed_content = if has_shortcodes
                          shortcode_context = build_template_variables(page, site, "", "", "", global_vars: global_vars)
                          # `warnings:` routes shortcode template errors into
                          # page.build_warnings so the serve error overlay can
                          # surface them (the render itself "succeeds").
                          process_shortcodes_jinja(raw, templates, shortcode_context, shortcode_results,
                            crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
                            warnings: page.build_warnings)
                        else
                          raw
                        end

    lazy_loading = site.config.markdown.lazy_loading
    emoji = site.config.markdown.emoji

    # Render-hook context — nil (the zero-cost default) when no
    # templates/hooks/render-* template is configured, in which case
    # Processor::Markdown.render below constructs the exact same
    # HighlightingRenderer it always has.
    hooks_ctx = if reg = Content::Processors::RenderHooks.registry
                  build_hook_render_context(reg, page, site, crinja_env_override, template_cache_override)
                end

    # Use anchor links if enabled: page front matter (tri-state) overrides
    # the site-wide `[markdown] insert_anchor_links` ("none"/"left"/"right";
    # "before"/"after" accepted as internal-style aliases). A page-level
    # `true` with config "none" keeps today's hard-coded "after" placement.
    md_config = site.config.markdown
    anchors_cfg = md_config.insert_anchor_links
    anchors_on = page.insert_anchor_links.nil? ? anchors_cfg != "none" : page.insert_anchor_links
    anchor_style = anchors_cfg.in?("left", "before") ? "before" : "after"
    md_start = profiler ? Time.instant : nil
    md_input_bytes = processed_content.bytesize.to_i64
    html_content, toc_headers = if anchors_on
                                  Processor::Markdown.render_with_anchors(processed_content, highlight, safe, anchor_style, lazy_loading, emoji, markdown_config: md_config, hooks: hooks_ctx)
                                else
                                  Processor::Markdown.render(processed_content, highlight, safe, lazy_loading, emoji, markdown_config: md_config, hooks: hooks_ctx)
                                end
    if profiler && md_start
      md_elapsed = (Time.instant - md_start).total_milliseconds
      profiler.record_markdown(page.path, md_input_bytes, md_elapsed)
    end

    # Replace shortcode placeholders with their rendered HTML content
    html_content = replace_shortcode_placeholders(html_content, shortcode_results)

    # Resolve internal @/ links to actual page URLs
    if pages_by_path = @pages_by_path
      if site.config.links.broken_internal == "error"
        # Strict mode: collect unresolved links in a local array, then fold
        # them into the builder-wide accumulator under the mutex (render
        # workers run this concurrently under -Dpreview_mt). The aggregated
        # error is raised AFTER the fan-out so one bad link doesn't hide
        # the others.
        misses = [] of {String, String}
        html_content = Content::Processors::InternalLinkResolver.resolve(html_content, pages_by_path, page.path, site.config.base_url, misses: misses)
        unless misses.empty?
          @broken_links_mutex.synchronize do
            misses.each { |target, reason| @broken_internal_links << "#{page.path} → @/#{target} (#{reason})" }
          end
        end
      else
        html_content = Content::Processors::InternalLinkResolver.resolve(html_content, pages_by_path, page.path, site.config.base_url)
      end
    end

    # Prefix plain root-relative content links (e.g. `[Posts](/posts/)`) with the
    # base_url path so they resolve under a subpath deploy. No-op on root deploys;
    # also keeps RSS `<content:encoded>` and the search index subpath-correct
    # because both reuse `page.content` set below.
    html_content = Content::Processors::InternalLinkResolver.prefix_root_relative_links(html_content, site.config.base_url, site.config.base_path)

    # Make content images responsive: when image_processing generated width
    # variants for an <img>, add srcset/sizes so browsers pick an appropriate
    # size instead of always loading the full-resolution source.
    html_content = apply_responsive_images(html_content, page, site.config)

    # Store rendered HTML in page.content for reuse by Feed/Search generators
    # (avoids expensive re-rendering of Markdown in Generate phase)
    page.content = html_content
    {html_content, toc_headers, shortcode_context}
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
    profiler : Profiler? = nil,
  )
    return unless page.render

    # Clear warnings from previous renders (important for incremental rebuilds)
    page.build_warnings.clear

    # Handle redirect_to for pages AND sections
    if page.has_redirect?
      generate_redirect_page(page, site, output_dir, verbose)
      generate_aliases(page, site, output_dir, verbose)
      return
    end

    html_content, toc_headers, shortcode_context = render_page_content(page, site, templates, highlight, safe, global_vars,
      crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, profiler: profiler)

    # Only expose TOC data when page.toc is enabled
    if page.toc && !toc_headers.empty?
      toc_html = generate_toc_html(toc_headers)
    else
      toc_html = ""
      toc_headers = [] of Models::TocHeader
    end

    template_name = determine_template(page, templates, site)
    template_content = templates[template_name]? || templates["page"]?
    Logger.debug "Rendering #{page.path} (section=#{page.section.empty? ? "<root>" : page.section}, index=#{page.is_index}) using template '#{template_name}'" if verbose

    # Handle section pages with pagination
    if (template_name == "section" || page.template == "section") && page.is_a?(Models::Section)
      render_section_with_pagination(page.as(Models::Section), site, templates, template_content, output_dir, minify, html_content, toc_html, toc_headers, verbose, global_vars,
        crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, error_overlay: error_overlay,
        template_name: template_name)
    else
      section_list_html = ""

      final_html = if template_content
                     apply_template(template_content, html_content, page, site, section_list_html, toc_html, templates, toc_headers, global_vars: global_vars,
                       crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
                       prebuilt_vars: shortcode_context, template_name: template_name)
                   else
                     no_template_fallback(page, html_content)
                   end

      if error_overlay && !page.build_warnings.empty?
        final_html = inject_error_overlay(final_html, page.build_warnings)
      end

      # Scrubbed on BOTH paths, before the optional minify pass: a NUL that
      # reaches the page through a data-file value is invalid HTML text and is
      # what makes the minifier's `\x00`-delimited sentinels forgeable, but
      # scrubbing it only under --minify made the two build modes emit
      # different page bytes for the same source.
      final_html = Utils::HtmlMinifier.scrub_nul(final_html)
      final_html = minify_html(final_html) if minify

      write_output(page, output_dir, final_html, verbose)
    end

    # A collision loser must not write its sibling output-format files
    # (index.json, index.md, …) either — they live at the same claimed URL.
    unless collision_suppressed?(page, page.url)
      render_output_formats(page, site, templates, output_dir, html_content, toc_html, toc_headers, verbose, global_vars,
        crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
    end

    generate_aliases(page, site, output_dir, verbose)
  end

  # Builds the per-page render-hook context: the same per-worker Crinja env
  # and compiled-template cache used for shortcodes/page templates
  # (`render_shortcode_jinja`/`apply_template`), so a hook template shares
  # cache warmth with everything else rendered on this page — just with its
  # own salted cache keys (see `RenderHooks::HookRenderContext`). Only
  # called when a registry exists (see the `if reg = ...` guard at the
  # call site), so this never runs on the no-hooks path.
  private def build_hook_render_context(
    registry : Content::Processors::RenderHooks::Registry,
    page : Models::Page,
    site : Models::Site,
    crinja_env_override : Crinja?,
    template_cache_override : Hash(UInt64, Crinja::Template)?,
  ) : Content::Processors::RenderHooks::HookRenderContext
    env = crinja_env_override || crinja_env
    cache = template_cache_override || @compiled_templates_cache
    cache_mutex = template_cache_override ? nil : @crinja_cache_mutex
    page_vars = Content::Processors::RenderHooks.page_vars(page, site.config)
    Content::Processors::RenderHooks::HookRenderContext.new(registry, env, cache, cache_mutex, page_vars,
      site.config.markdown.mermaid, site.config.markdown.admonitions)
  end

  # Render-path fallback when a page/section has no template: warn, record a
  # dedup'd build warning, and return the raw HTML unchanged. (determine_template
  # has its own intentionally warn-once handling and is not routed through here.)
  private def no_template_fallback(page : Models::Page, html_content : String) : String
    msg = "No template found for #{page.path}. Using raw content."
    Logger.warn msg
    page.build_warnings << msg unless page.build_warnings.includes?(msg)
    html_content
  end

  private def determine_template(page : Models::Page, templates : Hash(String, String), site : Models::Site) : String
    if custom = page.template
      return custom if templates.has_key?(custom)
      msg = "Custom template '#{custom}' not found for #{page.path}. Falling back to default."
      # determine_template runs again after render for profiler bookkeeping;
      # only log/record the first time so the warning isn't printed twice.
      unless page.build_warnings.includes?(msg)
        Logger.warn "#{msg}"
        page.build_warnings << msg
      end
    end

    if page.is_a?(Models::Section)
      return "section" if templates.has_key?("section")
    end

    # Only the site (or per-language) homepage renders with the `index`
    # template — see `home?`. The older test here (`page.is_index &&
    # page.section.empty?`) also matched one-level page bundles like
    # `content/about/index.md`, whose section resolves to "" as well: those
    # pages were rendered with the homepage template, silently discarding
    # their own title and body (the gh#601 fix landed on `home?` but never
    # reached this call site).
    if home?(page) && templates.has_key?("index")
      return "index"
    end

    # Inherit the parent section's default template (`page_template`) for regular
    # child pages that did not set an explicit `template`. Sections render with
    # their own "section" template (handled above), so they are excluded here.
    unless page.is_a?(Models::Section)
      if section = site.section_for(page.section, page.language)
        if pt = section.page_template
          return pt if templates.has_key?(pt)
        end
      end
    end

    "page"
  end

  private def minify_html(html : String) : String
    Utils::HtmlMinifier.minify(html)
  end

  # Hugo-style `{{< name >}}` shortcodes aren't a Hwaro syntax — they'd
  # otherwise reach Markdown unchanged and ship as HTML-escaped literals
  # (`{{&lt; alert &gt;}}`) in the rendered page. The conversion depends on
  # whether the shortcode wraps a body: self-closing Hugo shortcodes
  # (`{{< youtube id="v" >}}`) map to the direct-call form `{{ youtube(id="v") }}`,
  # while paired ones (`{{< alert >}}…{{< /alert >}}`) map to the block form
  # `{% alert(…) %}…{% end %}`. Emitting `{% youtube(…) %}` for a self-closing
  # shortcode produces an unclosed block tag that still ships as literal text,
  # so the warning must show both forms. Warn once per page and list the
  # distinct shortcode names so the message is actionable in a `hwaro build`
  # log even with hundreds of pages.
  HUGO_SHORTCODE_RE = /\{\{<\s*\/?\s*([a-zA-Z_][\w\-]*)/

  private def warn_hugo_shortcode_syntax(raw : String, path : String) : Nil
    names = Set(String).new
    # Only `{{<` OUTSIDE fenced code blocks and inline code spans reaches
    # Markdown as live (escaped) text — fenced examples are the documented
    # way to SHOW Hugo syntax and must not warn. Reuse the same
    # FenceTracker + inline-code masking the shortcode pre-filter uses
    # (content_may_contain_shortcodes?) so the two can't disagree about
    # what is fenced.
    tracker = Content::Processors::FenceTracker.new
    raw.each_line(chomp: false) do |line|
      next if tracker.fence_line?(line)
      next unless line.includes?("{{<")
      scan_line = line.includes?('`') ? mask_inline_code(line)[0] : line
      scan_line.scan(HUGO_SHORTCODE_RE) { |m| names << m[1] }
    end
    return if names.empty?
    sorted = names.to_a.sort
    Logger.warn "Hugo-style shortcode syntax `{{< … >}}` is not supported and will render as literal text in #{path}. " \
                "Found: #{sorted.join(", ")}. Convert to Hwaro's Crinja syntax — self-closing: " \
                "`{{< name arg=\"v\" >}}` → `{{ name(arg=\"v\") }}`; with a body: " \
                "`{{< name arg=\"v\" >}}body{{< /name >}}` → `{% name(arg=\"v\") %}body{% end %}` (named closer `{% endname %}` recommended)."
  end

  # Is this the site (or per-language) homepage — the root `index.md` /
  # `_index.md`? Such a page is an index whose source file sits directly
  # under `content/` with no parent directory, so `page.path` has no `/`
  # (`index.md`, `index.ko.md`, `_index.md`, …). This deliberately does NOT
  # use `page.is_index && page.section.empty?`: one-level page bundles like
  # `content/about/index.md` also resolve to an empty section, so that test
  # mislabels them as the homepage (gh#601).
  private def home?(page : Models::Page) : Bool
    page.is_index && !page.path.includes?('/')
  end
end
