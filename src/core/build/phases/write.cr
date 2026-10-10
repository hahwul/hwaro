# Phase: Write — 404 page, raw files, assets
#
# Handles writing output files that are not part of the main page
# rendering pipeline: the 404 page, raw files (JSON, XML), and
# co-located page bundle assets.

module Hwaro::Core::Build::Phases::Write
  private def execute_write_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Write")
    result = @lifecycle.run_phase(Lifecycle::Phase::Write, ctx) do
      Logger.status_phase("write")
      site = @site || raise "Site not initialized"
      templates = @templates || raise "Templates not loaded"
      output_dir = ctx.options.output_dir
      minify = ctx.options.minify
      verbose = ctx.options.verbose

      generate_404_page(site, templates, output_dir, minify, verbose, @render_global_vars)

      # Process raw files (JSON, XML). A file inside the bundle of a page
      # the build withholds (draft, future-dated, expired) stays
      # unpublished, exactly as its page-bundle asset copy does.
      withheld = withheld_bundle_dirs
      unless withheld.empty?
        ctx.raw_files.reject! { |raw| withheld_content_file?(raw.relative_path, withheld) }
      end
      written_raw = Set(String).new
      shadowed = content_copy_shadowed_outputs(output_dir)
      raw_count = process_raw_files(ctx.raw_files, output_dir, minify, verbose, written_raw, shadowed)
      ctx.stats.raw_files_processed = raw_count

      # Process co-located assets (images, etc. in page bundles). A `.json`/
      # `.xml` bundle asset that `[content.files]` also publishes is already
      # written above — as MINIFIED output under `--minify`. Copying the raw
      # source over it here silently undid the minification, so the
      # destinations just written are passed in and skipped.
      process_assets(ctx.all_pages, output_dir, verbose, written_raw, shadowed)
    end
    profiler.end_phase
    result
  end

  # `global_vars` is the render phase's site-wide template vars (or the
  # caller's freshly built set). Passing it avoids an O(site) rebuild of
  # every page/section Crinja value just for this one page; nil falls back
  # to building them (standalone callers).
  private def generate_404_page(site : Models::Site, templates : Hash(String, String), output_dir : String, minify : Bool, verbose : Bool, global_vars : Hash(String, Crinja::Value)? = nil)
    return unless templates.has_key?("404")

    template = templates["404"]
    page = Models::Page.new("404.html")
    page.title = "404 Not Found"
    # Give the 404 page a real URL so `og:url` doesn't render as a bare
    # host (gh#522). The actual file lives at `<output>/404.html`; most
    # static hosts also serve it for any unmatched path, so a stable
    # canonical-style URL is the best we can do.
    page.url = "/404.html"

    content = ""
    section_list = ""
    toc = ""

    final_html = apply_template(template, content, page, site, section_list, toc, templates, template_name: "404", global_vars: global_vars)

    final_html = Utils::HtmlMinifier.minify(final_html) if minify
    final_html = privacy_rewrite(final_html)

    output_path = File.join(output_dir, "404.html")
    Hwaro::Utils::FileSafe.mkdir_p(File.dirname(output_path))
    Hwaro::Utils::FileSafe.atomic_write(output_path, final_html)
    record_html_stats(final_html)
    # 404 is rewritten on every build, so its live claim should not depend on
    # the filesystem's mtime precision when a static 404.html was removed.
    claim_generated_output(output_path)
    Logger.action :create, output_path if verbose
  end

  # Bundle directories (see `@content_index_dirs`) none of whose index
  # pages survived the build's publication filter — a draft without
  # `--drafts`, a future-dated page without `--include-future`, an expired
  # one without `--include-expired`, a parse failure. The page-bundle asset
  # lane withholds their files by construction (only surviving pages copy
  # assets); `[content.files]` and raw JSON/XML copies match paths only, so
  # they consult this set. Empty — the common case — when nothing was
  # filtered out. A page that lost an output-path collision is not
  # published either: its files went into the WINNER's directory, so two
  # bundles sharing a URL served the loser's `cover.jpg` on the winner's page.
  def withheld_bundle_dirs : Set(String)
    return Set(String).new if @content_index_dirs.empty?
    live = Set(String).new
    if site = @site
      site.pages.each { |p| live << File.dirname(p.path) if p.is_index && !p.output_suppressed }
      site.sections.each { |s| live << File.dirname(s.path) if s.is_index && !s.output_suppressed }
    end
    @content_index_dirs - live
  end

  # True when content-relative `relative` sits in a withheld bundle: its
  # NEAREST enclosing bundle directory (the one whose page would own it as
  # an asset) is in `withheld`. A live nested bundle inside a withheld one
  # still publishes its own files.
  def withheld_content_file?(relative : String, withheld : Set(String) = withheld_bundle_dirs) : Bool
    return false if withheld.empty?
    dir = File.dirname(relative)
    until dir == "." || dir == "/" || dir.empty?
      return withheld.includes?(dir) if @content_index_dirs.includes?(dir)
      dir = File.dirname(dir)
    end
    false
  end

  # Output files a page render or a generator writes (the feed, sitemap,
  # robots, 404, taxonomy pages, alias stubs...), absolute. The Write phase
  # copies content files AFTER those, so a `[content.files]` copy or bundle
  # asset at one of these paths silently replaced the rendered page or the
  # generated feed — the opposite of `static/`, which they beat — and serve,
  # re-rendering the page on an edit, disagreed with the build. They lose
  # now, as a static file does (see `copy_changed_static`).
  def content_copy_shadowed_outputs(output_dir : String) : Set(String)
    cwd = Dir.current
    shadowed = owned_output_paths(output_dir).map { |path| File.expand_path(path, cwd) }.to_set
    copies = @generated_claims_mutex.synchronize { @content_copy_claims.map { |path| File.expand_path(path, cwd) }.to_set }
    generated_output_paths(output_dir).each do |path|
      full = File.expand_path(path, cwd)
      shadowed << full unless copies.includes?(full)
    end
    # A `--cache` hit renders nothing, so its alias stubs and `/page/N/`
    # pages are on record only in its cache entry.
    if (cache = @cache) && cache.enabled? && (site = @site)
      rendered = @page_derived_mutex.synchronize { @derived_outputs_this_pass.keys.to_set }
      (site.pages + site.sections).each do |page|
        next if rendered.includes?(page.path)
        cache.derived_paths_for(cache_paths_for(page, output_dir)[0]).each { |path| shadowed << File.expand_path(path, cwd) }
      end
    end
    shadowed
  end

  # True (after warning) when a content copy of `source` to `dest` would
  # replace a page or generated output — see `content_copy_shadowed_outputs`.
  private def content_copy_shadowed?(source : String, dest : String, shadowed : Set(String)) : Bool
    return false unless shadowed.includes?(File.expand_path(dest))
    Logger.warn "Not publishing #{source}: #{dest} is a page or generated output, which takes precedence."
    true
  end

  # Process raw files (JSON, XML) with minification
  private def process_raw_files(raw_files : Array(Lifecycle::RawFile), output_dir : String, minify : Bool, verbose : Bool, written : Set(String), shadowed : Set(String)) : Int32
    count = 0

    raw_files.each do |raw_file|
      next unless output_path = publish_raw_file(raw_file.source_path, raw_file.relative_path, output_dir, minify, shadowed)

      written << File.expand_path(output_path)
      # A raw/content file has no cache entry, so nothing else remembers that
      # this build published it — and a `--cache` build never wipes the
      # output directory. Claiming it lets Finalize delete the copy when its
      # source is removed (see Phases::Finalize#stale_generated_outputs).
      claim_generated_output(output_path, content_copy: true)
      Logger.action :create, output_path if verbose
      count += 1
    end

    count
  end

  # Publish one raw / `[content.files]` file to `output_dir/<relative_path>`,
  # minifying JSON / XML when `minify` is on. The destination, or nil when the
  # file was refused. Shared with serve's content-file republish so an edited
  # file gets the bytes a full build would write. `shadowed` defaults to a
  # fresh `content_copy_shadowed_outputs`.
  def publish_raw_file(source_path : String, relative_path : String, output_dir : String, minify : Bool, shadowed : Set(String)? = nil) : String?
    output_path = File.join(output_dir, relative_path)

    # Validate output path stays within output directory
    unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)
      Logger.warn "Skipping raw file outside output directory: #{relative_path}"
      return
    end
    # ponytail: serve's per-file republish recomputes the O(pages) set per
    # file; pass one in if a mass content edit ever makes that show.
    return if content_copy_shadowed?(source_path, output_path, shadowed || content_copy_shadowed_outputs(output_dir))

    # The copy below (and File.read) follows symlinks, so a raw-file symlink
    # whose target escapes the project would publish a file from outside
    # the site. Skip it — mirrors the bundle-asset guard in process_assets
    # and the static copy guard. In-repo symlinks resolve within and pass.
    if File.symlink?(source_path) && !Hwaro::Utils::PathUtils.resolves_within?(source_path, Dir.current)
      Logger.warn "Skipping raw file symlink pointing outside the project: #{source_path}"
      return
    end

    ext = File.extname(source_path).downcase

    mkdir_output(File.dirname(output_path))

    # JSON and XML are minified; HTML is rewritten unchanged.
    if minify && ext.in?(".json", ".xml", ".html", ".htm")
      content = File.read(source_path)
      error = nil
      begin
        content = JSON.parse(content).to_json if ext == ".json"
        content = Content::Processors::Xml.minify(content) if ext == ".xml"
      rescue ex : JSON::ParseException
        error = "JSON parsing failed: #{ex.message}"
      rescue ex
        error = "#{ext == ".json" ? "JSON" : "XML"} processing failed: #{ex.message}"
      end
      if error
        Logger.warn "Failed to process #{relative_path}: #{error}"
        Hwaro::Utils::FileSafe.atomic_copy(source_path, output_path)
      else
        Hwaro::Utils::FileSafe.atomic_write(output_path, content)
      end
    else
      # Copy as-is (binary-safe) when not minifying or no processor exists.
      #
      # Atomic (temp file + rename) for the same reason the processed branch
      # above uses `atomic_write`: `hwaro serve` rebuilds while HTTP fibers
      # stream these very paths, and a plain `FileUtils.cp` truncates the
      # destination and then streams, so a request landing mid-copy is
      # answered with a zero-length or half-written file.
      Hwaro::Utils::FileSafe.atomic_copy(source_path, output_path)
    end

    output_path
  end

  # `{source, destination}` of each of `page`'s bundle assets. Nil when the
  # page URL is unpublishable (a traversing segment); empty when its
  # directory resolves outside the output directory.
  private def bundle_asset_destinations(page : Models::Page, output_dir : String) : Array({String, String})?
    return unless safe_url_path = url_output_path(page.url.lchop("/"))
    dest_dir = File.join(output_dir, safe_url_path)
    return [] of {String, String} unless Hwaro::Utils::OutputGuard.within_output_dir?(dest_dir, output_dir)
    # Page bundle directory relative to content/
    page_bundle_dir = File.dirname(page.path)
    page.assets.map do |asset_path|
      # asset_path is relative to content/ (e.g. "blog/post/image.jpg");
      # the destination keeps its path inside the bundle (e.g. "image.jpg").
      relative_to_bundle = Path[asset_path].relative_to(page_bundle_dir)
      {File.join("content", asset_path), File.join(dest_dir, relative_to_bundle.to_s)}
    end
  end

  # Process co-located assets for pages
  private def process_assets(pages : Array(Models::Page), output_dir : String, verbose : Bool, already_written : Set(String) = Set(String).new, shadowed : Set(String)? = nil)
    now = Time.utc.to_unix_ms
    shadowed ||= content_copy_shadowed_outputs(output_dir)
    pages.each do |page|
      next if page.assets.empty?
      # A collision loser's URL directory belongs to the winner (see
      # `withheld_bundle_dirs`).
      next if page.output_suppressed

      # Destination directory matches the page's URL structure
      # page.url typically starts with / and ends with /, e.g., /blog/post/
      #
      # The URL goes through the same refusal contract as every other sink
      # (`url_output_path`): a traversing segment is unpublishable. The old
      # code `mkdir_p`'d the RAW `output_dir/<url>` before any guard ran, so
      # a bundle page with `path = "../outside"` created a directory NEXT TO
      # the output directory — outside it — on every build, even though the
      # per-file guard below then correctly refused every asset in it.
      # Nothing creates the directory now until an asset is actually copied.
      pairs = bundle_asset_destinations(page, output_dir)
      unless pairs
        Logger.warn "Skipping bundle assets for #{page.path}: its URL #{page.url.inspect} cannot be written inside the output directory."
        next
      end

      pairs.each do |source_path, dest_path|
        next unless File.exists?(source_path)

        # A symlinked bundle asset whose target escapes the project would
        # publish a file from outside the site; skip it (mirrors the static
        # copy guard). In-repo symlinks resolve within the project and pass.
        if File.symlink?(source_path) && !Hwaro::Utils::PathUtils.resolves_within?(source_path, Dir.current)
          Logger.warn "Skipping bundle asset symlink pointing outside the project: #{source_path}"
          next
        end

        # Defense in depth: never write outside the output directory even if
        # an asset's relative path somehow climbs out of the bundle.
        next unless Hwaro::Utils::OutputGuard.within_output_dir?(dest_path, output_dir)

        # Already emitted by process_raw_files (possibly minified) — a plain
        # copy here would overwrite the processed output with the source.
        next if already_written.includes?(File.expand_path(dest_path))
        # A bundle's `index.html` sibling is an asset whose destination IS
        # the page's own output.
        next if content_copy_shadowed?(source_path, dest_path, shadowed)

        # Claimed even when the copy below is skipped as unchanged: the claim
        # list is "what this build publishes", and a file missing from it is
        # deleted by the next `--cache` build (see Phases::Finalize).
        claim_generated_output(dest_path, content_copy: true)

        # Skip unchanged assets. The Write phase runs on every build with a
        # surviving output dir (serve rebuilds, --preserve-output), so
        # image-heavy page bundles otherwise pay full copy I/O each time.
        # The copy below stamps the destination with the SOURCE mtime, so
        # size + exact mtime equality identifies "this exact source version
        # was already copied". A `src <= dest` ordering check instead would
        # skip forever when an asset is replaced by a same-size file with an
        # older preserved mtime (rsync -a / tar -x restoring a revision).
        src_info = File.info?(source_path)
        if src_info && (dest_info = File.info?(dest_path))
          if src_info.size == dest_info.size && src_info.modification_time == dest_info.modification_time
            # Racy-git (#857): while the source mtime is inside its
            # timestamp tick a same-size rewrite keeps it, so compare bytes.
            next if Cache.stable_mtime?(src_info.modification_time.to_unix_ms, now) ||
                    same_contents?(source_path, dest_path)
          end
        end

        mkdir_output(File.dirname(dest_path))
        # Atomic copy: bundle assets are re-copied on every serve rebuild while
        # HTTP fibers stream them to the browser, and a truncate-and-stream
        # copy hands out zero-length or partial images that nothing retries.
        # The mtime stamp below still lands on the renamed-in destination, so
        # the skip-unchanged check above keeps working.
        Hwaro::Utils::FileSafe.atomic_copy(source_path, dest_path)
        if src_info
          begin
            File.utime(Time.utc, src_info.modification_time, dest_path)
          rescue File::Error
            # Stamping is an optimization; a failure just means the next
            # build recopies this asset.
          end
        end
        Logger.action :copy, dest_path, Logger::Role::Dim if verbose
      end
    end
  end

  # `[build] write_stats`: fold one written HTML page into the collector.
  def record_html_stats(html : String) : Nil
    @html_stats.try(&.add(html))
  end

  # Flush the collector to `hwaro_stats.json`. `complete` means every page
  # rendered into this collector, so it replaces the file; a partial pass
  # (`--cache` hits, fast-start, serve's incremental passes) folds the
  # previous file in instead — a superset, so a selector only a removed or
  # edited page used lingers until the next build that renders every page.
  def write_html_stats(complete : Bool) : Nil
    return unless stats = @html_stats
    stats.merge_file(Utils::HtmlStats::FILE) unless complete
    stats.write(Utils::HtmlStats::FILE)
  end

  private def write_output(page : Models::Page, output_dir : String, content : String, verbose : Bool)
    # A page that lost an output-path collision renders normally (its content
    # still feeds listings/feeds/search) but must not race the winner on disk.
    return if collision_suppressed?(page, page.url)
    # nil = this page cannot be published where its URL says (a traversing
    # path segment, or a result outside the output directory). Skip it rather
    # than write it over the site root index — but never silently: an authored
    # page vanishing from the output with an exit code of 0 is exactly the
    # failure this warning exists to prevent.
    unless output_path = get_output_path(page, output_dir)
      Logger.warn "Not publishing #{page.path}: its URL #{page.url.inspect} cannot be written inside the output directory (a path segment traverses or escapes it). Rename the file or set an explicit `slug`/`path` in its front matter."
      note_unpublished_page
      return
    end

    content = privacy_rewrite(content, page.path)
    ensure_dir(Path[output_path].dirname.to_s)
    Hwaro::Utils::FileSafe.atomic_write(output_path, content)
    record_html_stats(content)
    note_published_page
    Logger.action :create, output_path if verbose
  end

  # Create directory only if not already created during this build.
  # Avoids redundant mkdir_p syscalls (stat+mkdir) for large sites.
  # Mutex protects the Set during parallel rendering; mkdir_p is
  # itself idempotent, so the worst case without it is duplicate syscalls.
  #
  # The Set is recorded only AFTER mkdir_p returns, so membership truthfully
  # implies the directory already exists on disk. Recording before creation
  # let a second fiber writing into the same directory (two pages resolving
  # to one output path) see it as "already created", skip its own mkdir, and
  # race ahead to File.write on a directory that did not exist yet — a flaky
  # "No such file or directory" under -Dpreview_mt. Two fibers may now both
  # mkdir_p the same new directory, but mkdir_p is idempotent and MT-safe, so
  # the worst case is one duplicate syscall, never a missing directory.
  # The memo is only a hint that `dir` existed when this builder last made
  # it. A serve session outlives that: pruning an orphaned output removes the
  # directory it leaves empty (a slug edit, a removed alias), and the next
  # rebuild writing back into it — the slug reverted — failed with ENOENT
  # because the memo skipped the mkdir. Every rebuild entry point starts over
  # (`forget_created_dirs`), and the builder's own pruning forgets exactly
  # the directories it deletes.
  private def forget_created_dirs(dir : String? = nil) : Nil
    @created_dirs_mutex.synchronize do
      if dir
        @created_dirs.delete(dir)
      else
        @created_dirs.clear
      end
    end
  end

  private def ensure_dir(dir : String)
    return if @created_dirs_mutex.synchronize { @created_dirs.includes?(dir) }
    mkdir_output(dir)
    @created_dirs_mutex.synchronize { @created_dirs << dir }
  end

  # `mkdir_p` for a directory inside the output tree. A kept tree (`--cache`,
  # serve) is pruned only in Finalize, so an output that changed kind since
  # the last build — `static/x` became `static/x/a.css`, the content file
  # `notes.txt` became the page `notes.txt.md` — still finds the old FILE
  # where this build needs a directory. mkdir failed on it, and on every
  # later warm build too, until the output directory was wiped by hand. A
  # cold build starts empty, so the previous build's leftover is removed; a
  # file THIS build wrote is a real collision and still fails, as it does
  # cold.
  private def mkdir_output(dir : String) : Nil
    Hwaro::Utils::FileSafe.mkdir_p(dir)
  rescue ex : File::AlreadyExistsError
    raise ex unless remove_stale_file_in_the_way(dir)
    Hwaro::Utils::FileSafe.mkdir_p(dir)
  end

  # Delete the regular file standing at `dir` or one of its ancestors, when
  # it is a previous build's output: neither written nor claimed by this
  # build (an unchanged static copy is skipped, not rewritten, but still
  # published). True when one was removed.
  private def remove_stale_file_in_the_way(dir : String) : Bool
    return false unless kept = @kept_output_dir
    path = dir
    while Utils::OutputGuard.within_output_dir?(path, kept)
      if File.info?(path, follow_symlinks: false).try(&.file?)
        target = File.expand_path(path)
        return false if written_this_build?(path) || generated_output_claims.any? { |claim| File.expand_path(claim) == target }
        return false unless Utils::OutputGuard.safe_to_delete_file?(path, kept)
        File.delete(path)
        return true
      end
      parent = File.dirname(path)
      break if parent == path
      path = parent
    end
    false
  end
end
