# Render phase — highlight/PWA asset tags and cache-busting digests.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Public URLs of self-hosted highlight.js assets that are referenced
  # (`[highlight] use_cdn = false`) but missing from `static/`. Empty when the
  # CDN is used, highlighting is disabled, or every asset is present. Hwaro
  # never copies these files itself, so the user is expected to drop them under
  # `static/assets/`; this surfaces the gap instead of shipping 404s.
  def missing_local_highlight_assets(config : Models::Config) : Array(String)
    return [] of String unless config.highlight.enabled
    return [] of String if config.highlight.use_cdn

    missing = [] of String
    css_rel = File.join("static", "assets", "css", "highlight", "#{config.highlight.theme}.min.css")
    js_rel = File.join("static", "assets", "js", "highlight.min.js")
    missing << "/assets/css/highlight/#{config.highlight.theme}.min.css" unless File.exists?(css_rel)
    # Server-side highlighting references no JS at all — only the theme CSS.
    unless config.highlight.server?
      missing << "/assets/js/highlight.min.js" unless File.exists?(js_rel)
    end
    missing
  end

  # Head markup wiring up the `[pwa]` outputs: the manifest link, a
  # theme-color meta, and a service-worker registration for sw.js (both
  # URLs go through `with_base_path` so sub-path deploys keep working).
  #
  # Every interpolated value is config-authored free text, so each one is
  # escaped for the context it lands in — `HTML.escape` inside the two
  # attributes (a `theme_color` carrying a quote used to close the
  # attribute early and inject markup into the `<head>` of every page),
  # and a JSON string literal inside the inline `<script>`, where HTML
  # entities are NOT decoded and would corrupt the URL instead.
  private def pwa_tags(config : Models::Config) : String
    return "" unless config.pwa.enabled

    manifest_url = config.with_base_path("/manifest.json")
    sw_url = config.with_base_path("/sw.js")
    String.build do |str|
      str << %(<link rel="manifest" href="#{HTML.escape(manifest_url)}">\n)
      str << %(<meta name="theme-color" content="#{HTML.escape(config.pwa.theme_color)}">\n)
      str << %(<script>if ("serviceWorker" in navigator) { window.addEventListener("load", function () { navigator.serviceWorker.register(#{js_string_literal(sw_url)}); }); }</script>)
    end
  end

  # A JS string literal safe to embed in an inline `<script>`: JSON quoting
  # handles quotes/backslashes/control characters, and `</` is split so a
  # value containing `</script>` cannot terminate the element early (the
  # HTML parser looks for that byte sequence without parsing JS).
  private def js_string_literal(value : String) : String
    value.to_json.gsub("</", "<\\/")
  end

  private def warn_missing_local_highlight_assets(config : Models::Config)
    missing = missing_local_highlight_assets(config)
    return if missing.empty?

    Logger.warn "[highlight] use_cdn = false but self-hosted asset(s) are missing: " \
                "#{missing.join(", ")}. Syntax highlighting will not load (the references 404). " \
                "Add the highlight.js build under static/ (static/assets/js/highlight.min.js and " \
                "static/assets/css/highlight/#{config.highlight.theme}.min.css), or set [highlight] use_cdn = true."
  end

  # The build output directory when `[assets] sri` is on: the tag emitters
  # hash the emitted bytes under it (static copy, Sass and bundles have all
  # written by the time the Render phase asks). Nil when SRI is off.
  # Off under `hwaro serve`: its tags carry the dev origin, so viewing the
  # site from another host name (localhost vs 127.0.0.1, a LAN address)
  # would make every check fail. `asset_integrity()` still answers there.
  private def sri_root(config : Models::Config) : String?
    return unless config.assets.sri
    ctx = @context
    return if ctx.nil? || ctx.options.serve_mode
    ctx.output_dir
  end

  # True when a template calls `asset_integrity()`. Its value digests an
  # emitted file, so the serve static lane — which only copies — must
  # re-render after any static change while one does.
  def asset_integrity_used? : Bool
    @templates.try(&.each_value.any?(&.includes?("asset_integrity"))) || false
  end

  # Hand AssetHooks the source of every output the Write phase copies
  # verbatim AFTER rendering — `[content.files]` raw files and page-bundle
  # assets — so `asset_integrity()` hashes those bytes on a cold build (the
  # copy does not exist yet) and on a `--cache` build (it still holds the
  # previous copy) alike. Raw files `--minify` rewrites are left out, along
  # with the bundle copies they shadow: their source is not what ships.
  private def publish_asset_sources(ctx : Lifecycle::BuildContext) : Nil
    sources = {} of String => String
    if asset_integrity_used?
      output_dir = ctx.options.output_dir
      transformed = Set(String).new
      withheld = withheld_bundle_dirs
      ctx.raw_files.each do |raw|
        next if !withheld.empty? && withheld_content_file?(raw.relative_path, withheld)
        dest = File.expand_path(File.join(output_dir, raw.relative_path))
        if ctx.options.minify && File.extname(raw.source_path).downcase.in?(".json", ".xml", ".html", ".htm")
          transformed << dest
        else
          sources[dest] = raw.source_path
        end
      end
      ctx.all_pages.each do |page|
        next if page.assets.empty?
        bundle_asset_destinations(page, output_dir).try &.each do |source, dest|
          dest = File.expand_path(dest)
          sources[dest] ||= source unless transformed.includes?(dest)
        end
      end
    end
    Content::Hooks::AssetHooks.sources = sources
  end

  # Compute a content-based cache bust hash from local CSS/JS files.
  # Returns an 8-character hex digest, or "" if no local files exist.
  private def compute_cache_bust(config : Models::Config) : String
    has_local_highlight = config.highlight.enabled && !config.highlight.use_cdn
    has_auto_includes = config.auto_includes.enabled && config.auto_includes.dirs.present?

    return "" unless has_local_highlight || has_auto_includes

    digest = Digest::MD5.new
    cache_bust_inputs(config).each { |file| digest.file(file) }
    digest.hexfinal[0, 8]
  end

  # True when one of `paths` (watcher paths, `static/css/site.css`) is a file
  # the cache-bust digest reads. Its `?v=` is printed into every page that
  # references a highlight or auto-include asset, so the serve static lane —
  # which only copies the file — must re-render the site when one changes.
  def cache_bust_input_changed?(paths : Array(String)) : Bool
    config = @config
    return false if config.nil? || paths.empty?
    inputs = cache_bust_inputs(config).map { |file| Path[file].normalize.to_s }.to_set
    return false if inputs.empty?
    paths.any? { |path| inputs.includes?(Path[path].normalize.to_s) }
  end

  # The files `compute_cache_bust` digests, in digest order.
  private def cache_bust_inputs(config : Models::Config) : Array(String)
    files = [] of String
    has_local_highlight = config.highlight.enabled && !config.highlight.use_cdn
    has_auto_includes = config.auto_includes.enabled && config.auto_includes.dirs.present?

    if has_local_highlight
      css_path = File.join("static", "assets", "css", "highlight", "#{config.highlight.theme}.min.css")
      files << css_path if File.exists?(css_path)
      js_path = File.join("static", "assets", "js", "highlight.min.js")
      files << js_path if File.exists?(js_path)
    end

    if has_auto_includes
      # `.scss` sources are digested too when Sass is on: the compiled
      # `.css` is not in the source tree, so without them an SCSS-only
      # edit would leave `?v=` unchanged and serve stale CSS from caches.
      # Partials count — they change the output of the entry importing them.
      pattern = config.sass.enabled ? "*.{css,js,scss}" : "*.{css,js}"
      config.auto_includes.dirs.each do |dir|
        static_dir = File.join("static", dir)
        next unless Dir.exists?(static_dir)
        files.concat(Dir.glob(File.join(static_dir, "**", pattern)).sort)
      end
      # Also digest SCSS outside auto_includes dirs (e.g. static/lib/_theme.scss
      # pulled in via @use from static/css/style.scss). Without this, a
      # partial-only edit recompiles CSS bytes but keeps the old ?v=.
      if config.sass.enabled
        Dir.glob(File.join("static", "**", "*.scss")).sort.each do |file|
          relative = Path[file].relative_to("static").to_s
          next if config.auto_includes.dirs.any? { |dir|
                    relative == dir || relative.starts_with?("#{dir}/")
                  }
          files << file
        end
      end
    end

    files
  end
end
