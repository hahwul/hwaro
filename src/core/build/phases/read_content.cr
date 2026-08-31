# Phase: ReadContent — content path collection
#
# Handles collecting content file paths from the content/ directory
# without parsing them. Creates Page and Section objects and collects
# raw files (JSON, XML) for later processing.

module Hwaro::Core::Build::Phases::ReadContent
  # Page source extensions. Must agree with the markdown processor's
  # `extensions` declaration — a `.markdown` file the processor claims but
  # this phase skips would silently vanish from the build.
  PAGE_EXTENSIONS = {".md", ".markdown"}

  private def execute_read_content_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("ReadContent")
    result = @lifecycle.run_phase(Lifecycle::Phase::ReadContent, ctx) do
      Logger.status_phase("read")
      collect_content_paths(ctx, ctx.options.drafts)
      synthesize_generated_pages(ctx)
      # Count surfaces in the closing build receipt's "read" row instead of an
      # inline line, keeping the build quiet until the summary.
      ctx.stats.pages_read = ctx.all_pages.size
    end
    profiler.end_phase
    result
  end

  # Collect content file paths without parsing (single directory traversal)
  private def collect_content_paths(ctx : Lifecycle::BuildContext, include_drafts : Bool)
    config = ctx.config
    content_files_enabled = config.try(&.content_files.enabled?) || false
    seen_raw = Set(String).new

    # Single pass over content directory for both markdown and raw files
    Dir.glob("content/**/*") do |file_path|
      # lstat, not `File.directory?`: that follows symlinks, and following a
      # symlink cycle (`ln -s loop content/loop`) fails with ELOOP, which
      # `File.info?` raises as `File::Error` — aborting the whole build with a
      # raw filesystem error. lstat never follows, so a cycle is just an
      # ordinary symlink entry here.
      lstat = File.info?(file_path, follow_symlinks: false)
      next if lstat.nil? || lstat.directory?

      if lstat.symlink?
        # A content symlink whose target lives outside the project would
        # publish a file from outside the site — `content/leak.md ->
        # ../../secrets.env` rendered straight into public/leak/index.html.
        # This is the same policy already applied to static files
        # (phases/initialize.cr), raw files and page-bundle assets
        # (phases/write.cr). In-project symlinks resolve back within the root
        # and keep working; `resolves_within?` also answers false for dangling
        # links and cycles (realpath fails), so those are skipped here instead
        # of failing later in the parse phase's `File.read` — hence the
        # "does not resolve inside" wording, which covers all three.
        unless Hwaro::Utils::PathUtils.resolves_within?(file_path, Dir.current)
          Logger.warn "Skipping content symlink that does not resolve inside the project: #{file_path}"
          next
        end
        # `resolves_within?` already resolved the link (realpath succeeded),
        # so this stat cannot hit the ELOOP the lstat above avoids.
        target = File.info?(file_path, follow_symlinks: true)
        next if target.nil?
      else
        target = lstat
      end

      # Only regular files are readable content. A FIFO or socket dropped into
      # content/ would otherwise reach the parse phase's `File.read`, and
      # `open(2)` on a writer-less FIFO blocks forever — a build that hangs
      # with no output and no error. Directories were dropped above; a symlink
      # to an in-project directory lands here (the glob does not descend into
      # it either) and is skipped by the same test.
      next unless target.file?

      relative_path = Path[file_path].relative_to("content").to_s
      ext = Path[file_path].extension.downcase

      if PAGE_EXTENSIONS.includes?(ext)
        # Process markdown file
        basename = Path[relative_path].basename
        language = extract_language_from_filename(basename, config, ext)

        clean_basename = if language
                           # basename is guaranteed to end with
                           # ".<language><ext>" (extract_language_from_filename
                           # just matched it), so plain string surgery replaces
                           # what was a per-file interpolated Regex compile.
                           "#{basename.rchop(".#{language}#{ext}")}#{ext}"
                         else
                           basename
                         end

        is_section_index = clean_basename == "_index#{ext}"
        is_index = clean_basename == "index#{ext}" || is_section_index

        if is_section_index
          page = Models::Section.new(relative_path)
          ctx.sections << page
        else
          page = Models::Page.new(relative_path)
          ctx.pages << page
        end

        path_parts = Path[relative_path].parts
        if is_section_index
          page.section = path_parts.size > 1 ? path_parts[0..-2].join("/") : ""
        elsif is_index
          page.section = path_parts.size > 2 ? path_parts[0..-3].join("/") : ""
        else
          page.section = path_parts.size > 1 ? path_parts[0..-2].join("/") : ""
        end
        page.is_index = is_index
        page.language = language
      else
        # Collect raw files (JSON, XML) and content files
        next if seen_raw.includes?(relative_path)
        is_raw = ext == ".json" || ext == ".xml"
        is_content_file = content_files_enabled && config && Content::Processors::ContentFiles.publish?(relative_path, config)

        if is_raw || is_content_file
          ctx.raw_files << Lifecycle::RawFile.new(file_path, relative_path)
          seen_raw << relative_path
        end
      end
    end
  end

  # Extract the language code from a filename (`about.ko.md` -> "ko",
  # `_index.zh-tw.md` -> "zh-tw"). The candidate is whatever sits between
  # the last two dots and is matched against the DECLARED language codes
  # (plus the default) — not a fixed `[a-z]{2,3}` alphabet, which silently
  # read `about.zh-tw.md` as a regular page published at /about.zh-tw/.
  # An undeclared suffix still means "no language" (regular page).
  private def extract_language_from_filename(basename : String, config : Models::Config?, ext : String = ".md") : String?
    return unless config
    return unless config.multilingual?
    return unless basename.size > ext.size && basename[-ext.size..].downcase == ext

    stem = basename[0, basename.size - ext.size]
    idx = stem.rindex('.')
    # idx > 0: a non-empty base name must remain (".ko.md" is not a translation)
    return unless idx && idx > 0
    lang_code = stem[(idx + 1)..]
    return if lang_code.empty?
    return lang_code if config.languages.has_key?(lang_code) || lang_code == config.default_language

    nil
  end

  # `[[content.generate]]` — materialize planned data pages into the build's
  # page list, HERE, so they enter the pipeline at the same point authored
  # files do and every later phase (parse, cascade/draft filtering,
  # taxonomies, feeds, search, sitemap, render, output formats) treats them
  # as ordinary content. See Core::Build::ContentGenerate for the plan
  # contract and Models::Page::Synthesis for why these pages must NOT carry
  # the `generated` flag.
  private def synthesize_generated_pages(ctx : Lifecycle::BuildContext)
    config = ctx.config
    return unless config
    return if config.content_generate.empty?
    site = @site || return

    plans = ContentGenerate.plan(config, site.data, crinja_env)
    return if plans.empty?

    # Authored content always wins a path. Collected paths cover what this
    # build read; the shared disk probe additionally covers files the
    # collect pass excluded (a draft without --drafts, a `.markdown` twin)
    # and the leaf-bundle twin `<slug>/index.md` that publishes the same
    # URL — those still OWN their URL, and a generated page silently
    # replacing an authored one is the one collision outcome this feature
    # must never produce.
    collected_paths = Set(String).new
    ctx.pages.each { |p| collected_paths << p.path }
    ctx.sections.each { |s| collected_paths << s.path }

    added = Hash(String, Int32).new(0)
    plans.each do |plan|
      if collected_paths.includes?(plan.path) || ContentGenerate.authored_twin_exists?(plan.path)
        Logger.warn "  #{plan.origin}: skipping generated page '#{plan.path}' — an authored content file already claims that path (authored content wins)."
        next
      end
      page = Models::Page.new(plan.path)
      page.section = plan.section
      page.synthesis = Models::Page::Synthesis.new(plan.markdown, plan.item, plan.origin)
      ctx.pages << page
      collected_paths << plan.path
      added[plan.origin] += 1
    end
    ctx.invalidate_all_pages_cache

    added.each do |origin, count|
      Logger.info "  Generated #{count} page(s) from #{origin}"
    end
  end
end
