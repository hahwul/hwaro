# Render phase — layout application, Crinja-literal masking and template compilation.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  def apply_template(
    template : String,
    content : String,
    page : Models::Page,
    site : Models::Site,
    section_list : String,
    toc : String,
    templates : Hash(String, String),
    toc_headers : Array(Models::TocHeader) = [] of Models::TocHeader,
    pagination : String = "",
    page_url_override : String? = nil,
    paginator : Content::Pagination::PaginatedPage? = nil,
    global_vars : Hash(String, Crinja::Value)? = nil,
    crinja_env_override : Crinja? = nil,
    template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
    pagination_seo_links : String = "",
    prebuilt_vars : Hash(String, Crinja::Value)? = nil,
    template_name : String? = nil,
  ) : String
    # Use per-worker env when provided (parallel path), otherwise shared env
    env = crinja_env_override || crinja_env
    cache = template_cache_override || @compiled_templates_cache

    # Build template variables — reuse prebuilt_vars if available (shortcode path)
    vars = if pv = prebuilt_vars
             update_content_vars(pv, content, section_list, toc, toc_headers, pagination, pagination_seo_links)
             # The prebuilt hash is the shortcode pre-render context, built
             # with content="" — its per-fence copy probe saw nothing. Re-run
             # it against the FINAL rendered content, otherwise a
             # `{copy=true}` fence on any page that also uses a shortcode
             # ships no copy runtime.
             inject_per_fence_copy_runtime(pv, site.config, content)
             pv
           else
             build_template_variables(page, site, content, section_list, toc, toc_headers, pagination, page_url_override, paginator, global_vars, pagination_seo_links: pagination_seo_links,
               features: template_name.try { |tn| @template_var_features[tn]? })
           end

    begin
      # Process shortcodes in template directly (skip per-line fence detection
      # since templates don't contain markdown fenced code blocks). Templates
      # known to contain no shortcode tokens (precomputed in load_templates)
      # skip the scan entirely; unknown sources are processed as before.
      processed_template = if @template_shortcode_scan[template.hash]? == false
                             template
                           else
                             # Hide the constructs Crinja owns (raw blocks, macro
                             # invocations) from that pass and restore them
                             # afterwards — see `mask_template_literals`.
                             masked, literals = masked_template(template)
                             expanded = process_shortcodes_in_text(masked, templates, vars,
                               crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
                               warnings: page.build_warnings)
                             unmask_template_literals(expanded, literals)
                           end

      # Cache compiled Crinja templates by content hash.
      # Most pages share the same base template string, so this avoids
      # re-parsing the template AST on every page render.
      cache_key = processed_template.hash
      crinja_template = if cached = cache[cache_key]?
                          @cache_manager.record_hit("compiled_templates")
                          cached
                        else
                          @cache_manager.record_miss("compiled_templates")
                          compiled = compile_template(env, processed_template, template_name)
                          cache[cache_key] = compiled
                          compiled
                        end
      crinja_template.render(vars)
    rescue ex : Crinja::Error
      # Classify as a template error so `hwaro build --json` surfaces a
      # stable HWARO_E_TEMPLATE code (exit 4). Previously these errors
      # were downgraded to build warnings, which hid misconfigured
      # templates from scripts and CI.
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_TEMPLATE,
        # Clamped at construction, not just where it is logged: this message
        # is what the CLI prints and what `--json` emits, and Crinja attaches a
        # source excerpt to it — so a single minified (one-line) template made
        # one failure a multi-megabyte console line and a multi-megabyte JSON
        # field. 4000 characters is far more than any readable excerpt.
        message: "Template error for #{page.path}: #{Utils::TextUtils.truncate_error(ex.message || "")}",
        cause: ex,
      )
    end
  end

  # ---------------------------------------------------------------------
  # Protecting Crinja-owned syntax from the shortcode pass.
  #
  # `apply_template` expands shortcodes over the RAW template source, before
  # Crinja parses it, so that pass has no notion of Jinja block structure:
  # every `{{ name(...) }}` looks like a direct shortcode call, and text
  # inside `{% raw %}` … `{% endraw %}` looks like ordinary template text.
  # Two constructs the template language owns were destroyed by it:
  #
  #   * a macro invocation (`{{ nav_item("/", "Home") }}`, `{{ caller() }}`,
  #     `{% from "m.html" import btn %}{{ btn("Go") }}`) became
  #     `<!-- hwaro: missing shortcode 'nav_item' -->` plus a bogus warning.
  #     The `crinja_function?` escape hatch could not save it: a macro is a
  #     value bound into the render-time CONTEXT, never a registered env
  #     function.
  #   * a `{% raw %}` example was expanded (or deleted) instead of staying
  #     literal, which is exactly the construct raw blocks exist for.
  #
  # Both are swapped for NUL-delimited tokens before the shortcode pass and
  # restored right after, so what Crinja finally compiles is byte-identical
  # to the author's source for those regions. NUL never appears in a template
  # read as UTF-8 source, the same reasoning `mask_inline_code` relies on.
  #
  # The raw-block shape itself is owned by ShortcodeProcessor, which masks the
  # same regions on the CONTENT path (`mask_raw_blocks`): a hand-copied second
  # regex here would let the two paths drift, and a raw block that protects an
  # example in a template has to protect the same example in a markdown body.
  private TEMPLATE_RAW_BLOCK_RE = ShortcodeProcessor::RAW_BLOCK_RE
  private TEMPLATE_MACRO_DEF_RE = /\{\%-?\s*macro\s+([a-zA-Z_]\w*)\s*\(/
  private TEMPLATE_IMPORT_RE    = /\{\%-?\s*from\s+[^%]*?\bimport\s+([^%]*?)-?\%\}/
  # Mirrors the direct-call regex in ShortcodeProcessor (single line, same
  # name alphabet), so a masked call covers exactly what that pass would
  # otherwise have rewritten.
  private TEMPLATE_CALL_RE        = /\{\{\s*([a-zA-Z_][\w\-]*)\s*\(.*?\)\s*\}\}/
  private TEMPLATE_MASK_RE        = /\x00HWARO-TEMPLATE-LITERAL-(\d+)\x00/
  private TEMPLATE_IMPORT_NAME_RE = /\A[a-zA-Z_]\w*\z/

  # Masked form of a layout source, from the per-build cache when possible.
  #
  # Masking is a pure function of the template STRING, but it ran once per
  # rendered PAGE: four full-source `includes?` probes, a tuple allocation and
  # (whenever the source declares or imports a macro) a full `gsub` over the
  # layout — for the one template every page in a section shares. On a
  # page-count-heavy site that fixed per-page overhead is visible in the Render
  # phase; the cache is filled single-threaded in `load_templates`, before any
  # render worker spawns, and read-only here.
  #
  # The miss path is not dead: `apply_template` is also reached with sources
  # that never entered the templates hash (rerender paths, synthesized
  # layouts). Those pay what they paid before.
  private def masked_template(template : String) : {String, Array(String)}
    if cached = @template_literal_masks[template.hash]?
      return cached
    end
    mask_template_literals(template)
  end

  # `callables` lets the caller supply a set the source alone cannot produce —
  # macros a parent layout declares, which this template can call only because
  # it `{% extends %}` it. Defaults to the source's own declarations.
  private def mask_template_literals(template : String, callables : Set(String)? = nil) : {String, Array(String)}
    spans = [] of String
    masked = template

    # Substring probes first: the overwhelming majority of templates use
    # neither construct.
    if template.includes?("raw")
      masked = masked.gsub(TEMPLATE_RAW_BLOCK_RE) do |region|
        spans << region
        "\x00HWARO-TEMPLATE-LITERAL-#{spans.size - 1}\x00"
      end
    end

    # Macro names are collected from the raw-masked source: a `{% macro %}`
    # shown inside a raw block is documentation, not a definition.
    names = callables || template_local_callables(masked)
    unless names.empty?
      masked = masked.gsub(TEMPLATE_CALL_RE) do |invocation|
        next invocation unless names.includes?($1)
        spans << invocation
        "\x00HWARO-TEMPLATE-LITERAL-#{spans.size - 1}\x00"
      end
    end

    {masked, spans}
  end

  # `{% extends "base.html" %}` — the one reference that puts a macro declared
  # elsewhere in scope for THIS template's body. Mirrors TemplateDeps' literal
  # form; a computed `{% extends var %}` cannot be followed and falls back to
  # the template's own declarations.
  private TEMPLATE_EXTENDS_RE = /\{\%-?\s*extends\s+["']([^"']+)["']/

  # Callables a template source declares by itself, with `{% raw %}` regions
  # removed first (a `{% macro %}` shown inside a raw block is documentation,
  # not a definition).
  private def own_template_callables(source : String) : Set(String)
    scrubbed = source.includes?("raw") ? source.gsub(TEMPLATE_RAW_BLOCK_RE, "") : source
    template_local_callables(scrubbed)
  end

  # Everything `{{ name(...) }}` can resolve to when `name` renders: its own
  # declarations unioned with those of every layout it extends, transitively.
  #
  # Scanning one template in isolation missed the single most common Jinja
  # idiom — shared macros declared in a base layout and called from the child
  # that extends it. The child's body has no `{% macro %}`, so the call looked
  # like a shortcode: the invocation was replaced with
  # `<!-- hwaro: missing shortcode 'shared' -->` and the build warned about a
  # shortcode template that was never missing.
  private def inherited_template_callables(
    name : String,
    templates : Hash(String, String),
    memo : Hash(String, Set(String)),
    chain : Array(String),
  ) : Set(String)
    if cached = memo[name]?
      return cached
    end
    source = templates[name]?
    return Set(String).new unless source
    # An `{% extends %}` cycle is Crinja's error to report, not a reason to
    # recurse forever here.
    return Set(String).new if chain.includes?(name)

    chain.push(name)
    names = own_template_callables(source)
    if match = source.match(TEMPLATE_EXTENDS_RE)
      parent = match[1].sub(Builder::TEMPLATE_EXTENSION_REGEX, "")
      names.concat(inherited_template_callables(parent, templates, memo, chain))
    end
    chain.pop

    memo[name] = names
    names
  end

  # Names that resolve to a macro when this template renders: locally defined
  # macros, names (or aliases) pulled in by `{% from "x" import a, b as c %}`,
  # and `caller`, which `{% call %}` binds around a macro body. A namespaced
  # call (`{{ ui.btn() }}`, after `{% import "x" as ui %}`) needs no entry —
  # the dot keeps it out of the shortcode processor's name alphabet.
  private def template_local_callables(template : String) : Set(String)
    names = Set(String).new

    if template.includes?("macro")
      template.scan(TEMPLATE_MACRO_DEF_RE) { |m| names << m[1] }
    end

    if template.includes?("import")
      template.scan(TEMPLATE_IMPORT_RE) do |m|
        m[1].split(',').each do |part|
          # Bare `split` drops the surrounding whitespace and empty tokens.
          tokens = part.split
          next if tokens.empty?
          # `btn as tile` binds `tile`; a trailing `with context` /
          # `without context` modifier is a modifier, not a name.
          idx = tokens.index("as")
          name = idx ? tokens[idx + 1]? : tokens[0]
          next unless name
          names << name if name.matches?(TEMPLATE_IMPORT_NAME_RE)
        end
      end
    end

    names << "caller" if template.includes?("caller")
    names
  end

  private def unmask_template_literals(text : String, spans : Array(String)) : String
    return text if spans.empty?
    return text unless text.includes?('\u{0}')
    # to_i? (not to_i): a counterfeit token whose digit run overflows Int32
    # must not raise out of the render.
    text.gsub(TEMPLATE_MASK_RE) { |tok| $1.to_i?.try { |i| spans[i]? } || tok }
  end

  # Compile a template string, attaching its source filename when the template
  # came from disk. Crinja errors then report `templates/foo.html:line:col`
  # with a source excerpt instead of an anonymous `<string>` template.
  protected def compile_template(env : Crinja, source : String, template_name : String?) : Crinja::Template
    if template_name && (path = @template_paths[template_name]?)
      begin
        Crinja::Template.new(source, env, template_name, path)
      rescue ex : Crinja::Error
        # Crinja attaches the template to parse-time TemplateErrors itself, but
        # other parse-time errors (e.g. unknown-tag library lookups raise a
        # RuntimeError) escape without one — attach a non-parsed stub so the
        # message still names the source file.
        ex.template ||= Crinja::Template.new(source, env, template_name, path, run_parser: false)
        raise ex
      end
    else
      env.from_string(source)
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
    toc_headers : Array(Models::TocHeader),
    pagination : String,
    pagination_seo_links : String,
  )
    vars["content"] = Crinja::Value.new(content)
    vars["section_list"] = Crinja::Value.new(section_list)
    vars["toc"] = Crinja::Value.new(toc)
    vars["toc_obj"] = Crinja::Value.new({
      "html"    => Crinja::Value.new(toc),
      "headers" => Crinja::Value.new(toc_headers_to_crinja(toc_headers)),
    })
    vars["pagination"] = Crinja::Value.new(pagination)
    vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)

    # NOTE: pagination_obj is not updated here because its fields (URLs, page
    # numbers, booleans) are stable across the shortcode pre-render and final
    # render passes. The html field is set from the same pagination string
    # that was used when build_template_variables originally created it.
  end
end
