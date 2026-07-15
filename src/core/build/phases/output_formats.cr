# Phase: Output Formats — sibling non-HTML output files (see `[outputs]`)
#
# HTML always renders. This module additively renders sibling
# `<url>/index.<fmt>` files (json/txt/xml/csv) from user-supplied
# `templates/<name>.<fmt>.jinja` templates for pages/sections that opt in via
# config (`[outputs]`) or front matter (`page.extra["outputs"]`). Hooked into
# the render phase (see Phases::Render#render_page) so pagination naturally
# limits generation to page 1 of a section.
module Hwaro::Core::Build::Phases::OutputFormats
  # MIME types for the `rel=alternate` link tags (see `alternate_output_tags`)
  # and the dev server's Content-Type header.
  FORMAT_MIME = {
    "json" => "application/json",
    "xml"  => "application/xml",
    "txt"  => "text/plain",
    "csv"  => "text/csv",
  }

  # Effective set of extra output formats for `page`, after applying (in
  # order): the generated/redirect/404 exclusions, a front matter override
  # (`outputs = [...]`, which takes total precedence — including an explicit
  # `[]` to opt back out), and finally the `[outputs]` config default plus its
  # `sections` allowlist.
  def effective_output_formats(page : Models::Page, config : Models::Config) : Array(String)
    return [] of String if page.generated || page.has_redirect? || page.path == "404.html"

    if extra_val = page.extra["outputs"]?
      arr = extra_val.as?(Array(String))
      unless arr
        warn_once(page, "Front matter 'outputs' for #{page.path} must be a list of format names (#{Models::OutputsConfig::VALID_FORMATS.join(", ")}); ignoring and rendering HTML only.")
        return [] of String
      end

      invalid = arr.reject { |f| Models::OutputsConfig::VALID_FORMATS.includes?(f) }
      unless invalid.empty?
        warn_once(page, "Front matter 'outputs' for #{page.path} has unknown format(s) #{invalid.join(", ")} (valid: #{Models::OutputsConfig::VALID_FORMATS.join(", ")}); ignoring and rendering HTML only.")
        return [] of String
      end

      return arr
    end

    base = page.is_a?(Models::Section) ? config.outputs.section : config.outputs.page
    return [] of String if base.empty?
    # The `sections` allowlist scopes *section* output only (the documented
    # contract); page-level output is unscoped. Gating pages on it too meant
    # `sections = ["posts"]` silently dropped `page` formats everywhere
    # outside posts/ — scope page output per-section via `[cascade.extra]`
    # instead.
    return base unless page.is_a?(Models::Section)
    return base if config.outputs.sections.empty?

    matches_section = config.outputs.sections.any? { |s| page.section == s || page.section.starts_with?("#{s}/") }
    matches_section ? base : [] of String
  end

  # Log+record a build warning at most once per page (subsequent calls with
  # the same message are silent) — mirrors the dedup pattern used elsewhere
  # for repeated per-page warnings (e.g. `determine_template`).
  private def warn_once(page : Models::Page, msg : String)
    return if page.build_warnings.includes?(msg)
    Logger.warn msg
    page.build_warnings << msg
  end

  # Resolve the template to use for `fmt` on `page`, following the chain
  # `<entry-template>.<fmt>` -> `section.<fmt>` (sections only) -> `page.<fmt>`.
  # Raises a classified HWARO_E_TEMPLATE error listing every name tried when
  # none of them exist — a missing format template is a hard build failure,
  # not a silent skip.
  def determine_format_template(page : Models::Page, fmt : String, templates : Hash(String, String), site : Models::Site) : String
    entry = determine_template(page, templates, site)

    candidates = [] of String
    candidates << "#{entry}.#{fmt}"
    candidates << "section.#{fmt}" if page.is_a?(Models::Section)
    candidates << "page.#{fmt}"
    candidates.uniq!

    candidates.each do |name|
      return name if templates.has_key?(name)
    end

    raise Hwaro::HwaroError.new(
      code: Hwaro::Errors::HWARO_E_TEMPLATE,
      message: "No template found for output format '#{fmt}' on #{page.path}. Tried: #{candidates.join(", ")}.",
      hint: "Create one of: #{candidates.map { |name| "templates/#{name}.jinja" }.join(", ")}.",
    )
  end

  # True when one of `page`'s extra output formats resolves to a template in
  # `affected`. The serve-mode selective re-render checks this alongside the
  # HTML entry template: editing e.g. `templates/page.json.jinja` leaves the
  # entry template untouched, so without this check no page re-renders and
  # the sibling `index.json` files serve stale content until a full rebuild.
  def format_templates_affected?(page : Models::Page, templates : Hash(String, String), site : Models::Site, affected : Set(String)) : Bool
    formats = effective_output_formats(page, site.config)
    return false if formats.empty?

    formats.any? do |fmt|
      name = begin
        determine_format_template(page, fmt, templates, site)
      rescue Hwaro::HwaroError
        # No template exists for this format — render_page will surface that
        # for the page when something else selects it; a missing template
        # can't be the one that changed.
        nil
      end
      name ? affected.includes?(name) : false
    end
  end

  # Render and write every enabled extra format for `page`. No-op when
  # `effective_output_formats` is empty — the common case when the feature
  # isn't configured at all, so this is a cheap guard on every page.
  def render_output_formats(
    page : Models::Page,
    site : Models::Site,
    templates : Hash(String, String),
    output_dir : String,
    html_content : String,
    toc_html : String,
    toc_headers : Array(Models::TocHeader),
    verbose : Bool,
    global_vars : Hash(String, Crinja::Value)?,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
  )
    formats = effective_output_formats(page, site.config)
    return if formats.empty?

    formats.each do |fmt|
      template_name = determine_format_template(page, fmt, templates, site)
      template_content = templates[template_name]
      content = apply_template(template_content, html_content, page, site, "", toc_html, templates, toc_headers,
        global_vars: global_vars, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
        template_name: template_name)
      write_format_output(page, output_dir, fmt, content, verbose)
    end
  end

  # Write a single format's rendered content to `<url>/index.<fmt>`. Computes
  # the path directly via OutputGuard (rather than through get_output_path's
  # HTML-oriented root fallback) so a rejected path is skipped with a warning
  # instead of silently colliding multiple pages onto one shared root-level
  # `index.<fmt>` file.
  def write_format_output(page : Models::Page, output_dir : String, fmt : String, content : String, verbose : Bool)
    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
    candidate = File.join(output_dir, url_path, "index.#{fmt}")
    output_path = Utils::OutputGuard.safe_output_path(candidate, output_dir)
    unless output_path
      Logger.warn "Skipping #{fmt} output outside output directory: #{candidate}"
      return
    end

    ensure_dir(Path[output_path].dirname.to_s)
    File.write(output_path, content)
    Logger.action :create, output_path if verbose
  end

  # Output paths `formats` would resolve to for `page`, skipping any that
  # fail the OutputGuard check. Used by the cache (to detect a deleted sibling
  # file) and by stale-output removal (when a page's source disappears).
  def format_output_paths(page : Models::Page, output_dir : String, formats : Array(String)) : Array(String)
    url_path = Utils::PathUtils.sanitize_path(page.url.lchop("/"))
    formats.compact_map do |fmt|
      candidate = File.join(output_dir, url_path, "index.#{fmt}")
      Utils::OutputGuard.safe_output_path(candidate, output_dir)
    end
  end

  # `<link rel="alternate" type="MIME" href="ABS">` tags for every enabled
  # format on `page`, one per line — empty string when no formats apply.
  # `ABS` matches the same `base_url_stripped + page.url` pattern used by
  # `canonical_tag`/`hreflang_tags` so subpath deployments resolve correctly.
  def alternate_output_tags(page : Models::Page, config : Models::Config) : String
    formats = effective_output_formats(page, config)
    return "" if formats.empty?

    base = config.base_url_stripped
    url_path = page.url.starts_with?("/") ? page.url : "/#{page.url}"
    # The sibling file is written at `<url>/index.<fmt>` (a directory join),
    # so the advertised href needs the separating slash too — otherwise a
    # page whose URL lacks a trailing slash (e.g. a custom `path`) yields
    # `/downloadsindex.json` instead of `/downloads/index.json`.
    url_path += "/" unless url_path.ends_with?("/")

    formats.map do |fmt|
      mime = FORMAT_MIME[fmt]? || "application/octet-stream"
      href = "#{base}#{url_path}index.#{fmt}"
      %(<link rel="alternate" type="#{mime}" href="#{HTML.escape(href)}">)
    end.join("\n  ")
  end
end
