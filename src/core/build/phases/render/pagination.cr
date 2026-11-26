# Render phase — paginated section rendering.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  private def render_section_with_pagination(
    section : Models::Section,
    site : Models::Site,
    templates : Hash(String, String),
    template_content : String?,
    output_dir : String,
    minify : Bool,
    html_content : String,
    toc_html : String,
    toc_headers : Array(Models::TocHeader) = [] of Models::TocHeader,
    verbose : Bool = false,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    error_overlay : Bool = false,
    template_name : String? = nil,
  )
    pagination_result = section_pagination(section, site)
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
                      "#{base}/#{section.paginate_url_path}/#{paginated_page.page_number}/"
                    end

      final_html = if template_content
                     apply_template(template_content, html_content, section, site, section_list_html, toc_html, templates, toc_headers, pagination_nav_html, current_url, paginated_page, global_vars,
                       crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, pagination_seo_links: pagination_seo_links,
                       template_name: template_name)
                   else
                     no_template_fallback(section, html_content)
                   end

      if error_overlay && !section.build_warnings.empty?
        final_html = inject_error_overlay(final_html, section.build_warnings)
      end

      # Scrubbed on BOTH paths, before the optional minify pass: a NUL that
      # reaches the page through a data-file value is invalid HTML text and is
      # what makes the minifier's `\x00`-delimited sentinels forgeable, but
      # scrubbing it only under --minify made the two build modes emit
      # different page bytes for the same source.
      final_html = Utils::HtmlMinifier.scrub_nul(final_html)
      final_html = Utils::HtmlMinifier.minify(final_html) if minify

      # Write output - first page uses section URL, subsequent pages use /page/N/
      if paginated_page.page_number == 1
        write_output(section, output_dir, final_html, verbose)
      else
        write_paginated_output(section, paginated_page.page_number, output_dir, final_html, verbose, section.paginate_path)
      end
    end
  end

  # The pager pages of `section`: its listed pages (the site utility's set;
  # the Paginator sorts by the section's `sort_by`) cut into pages. Shared by
  # the renderer, the alias arbitration (`pager_page_owner`) and
  # `Builder#plan_urls`.
  private def section_pagination(section : Models::Section, site : Models::Site) : Content::Pagination::PaginationResult
    section_name = Path[section.path].dirname
    section_name = "" if section_name == "."
    # Collision losers are never written — see build_section_pages_crinja.
    section_pages = site.pages_for_section(section_name, section.language).reject(&.output_suppressed)
    Content::Pagination::Paginator.new(site.config).paginate(section, section_pages)
  end

  # Where pager page `page_number` (>= 2) of `page` is written, or nil when
  # it is not.
  private def paginated_output_path(page : Models::Page, page_number : Int32, output_dir : String, paginate_path : String = "page") : String?
    # /page/N/ outputs live under the section's claimed URL.
    return if collision_suppressed?(page, page.url)
    url_path = url_output_path(page.url.lchop("/").rstrip("/"))
    return unless url_path
    output_path = File.join(output_dir, url_path, paginate_path, page_number.to_s, "index.html")
    return unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)
    if owner = page_output_owner(output_path, output_dir)
      Logger.warn "Pagination page #{page_number} of '#{page.path}' is not written: content page '#{owner}' publishes the same path (#{output_path}). Rename that page or set the section's `paginate_path`."
      return
    end
    output_path
  end

  private def write_paginated_output(page : Models::Page, page_number : Int32, output_dir : String, content : String, verbose : Bool, paginate_path : String = "page")
    return unless output_path = paginated_output_path(page, page_number, output_dir, paginate_path)

    content = privacy_rewrite(content, page.path)
    ensure_dir(Path[output_path].dirname.to_s)
    publish_output(output_path, content)
    record_html_stats(content)
    # A section that loses posts paginates into fewer pages; the file for the
    # page number it no longer fills is only ever named here.
    record_page_derived_output(page.path, output_path)
    Logger.action :create, output_path if verbose
  end
end
