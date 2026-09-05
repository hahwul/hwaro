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
    # /page/N/ outputs live under the section's claimed URL.
    return if collision_suppressed?(page, page.url)
    url_path = url_output_path(page.url.lchop("/").rstrip("/"))
    return unless url_path
    output_path = File.join(output_dir, url_path, paginate_path, page_number.to_s, "index.html")
    return unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)

    ensure_dir(Path[output_path].dirname.to_s)
    Hwaro::Utils::FileSafe.atomic_write(output_path, content)
    Logger.action :create, output_path if verbose
  end
end
