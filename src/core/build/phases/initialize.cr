# Phase: Initialize — output dir setup, cache init, config loading, template loading
#
# Handles the first phase of the build lifecycle:
# - Cache initialization
# - Output directory setup and static file copying
# - Config and site model creation
# - i18n translation loading
# - Template loading and Crinja environment setup

module Hwaro::Core::Build::Phases::Initialize
  private def execute_initialize_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Initialize")
    result = @lifecycle.run_phase(Lifecycle::Phase::Initialize, ctx) do
      output_dir = ctx.options.output_dir
      verbose = ctx.options.verbose
      cache_enabled = ctx.options.cache

      build_cache = Cache.new(enabled: cache_enabled)
      @cache = build_cache
      ctx.cache = build_cache

      if cache_enabled
        if ctx.options.full
          build_cache.clear
          Logger.info "  Cache: full rebuild requested — cleared all entries."
        else
          stats = build_cache.stats
          Logger.info "  Cache enabled (#{stats[:valid]} valid entries)"
        end
      end

      # `preserve_output` keeps existing output files between rebuilds (used
      # by `hwaro serve` watch rebuilds) so mtime-based skip logic in hooks
      # like image processing can actually short-circuit. For a cold build
      # we always wipe to guarantee a clean state.
      keep_output = cache_enabled || ctx.options.preserve_output
      setup_output_dir(output_dir, keep_output)
      copy_static_files(output_dir, verbose, keep_output)

      config = @config || raise "Config not loaded"
      if url = ctx.options.base_url
        override = url.strip
        config.base_url = override unless override.empty?
      end
      site = Models::Site.new(config)
      @site = site
      load_data_files(site, config)

      # Load i18n translations
      i18n_dir = File.join("i18n")
      @i18n_translations = Content::I18n.load_translations(i18n_dir, config)

      @config = config
      ctx.site = @site
      ctx.config = config

      # Propagate the highlighting mode to the markdown renderer once per
      # build — read-only afterwards, including by parallel render fibers.
      Content::Processors::SyntaxHighlighter.server_mode = config.highlight.server?
      Content::Processors::SyntaxHighlighter.default_line_numbers = config.highlight.line_numbers
      Content::Processors::SyntaxHighlighter.default_copy = config.highlight.copy
      # Same pattern for the markdown options template filters consult
      # (markdownify honors the site's safe/smart_punctuation settings).
      Processor::Markdown.filter_markdown_config = config.markdown

      ctx.templates = load_templates
      @templates = ctx.templates

      # Per-page template closure hashes replace the invalidate-everything
      # template checksum when dependency tracking is on AND every template
      # reference resolved statically (no variable includes).
      @global_templates_hash = Cache.compute_templates_hash(ctx.templates)
      if (graph = @template_deps) && !graph.snapshot_escaping_refs.empty?
        @global_templates_hash = fold_snapshot_escaping_refs(@global_templates_hash, graph.snapshot_escaping_refs)
      end
      @per_page_template_hash = config.build.template_deps &&
                                (@template_deps.try { |deps| !deps.dynamic? } || false)
      if (deps = @template_deps) && deps.dynamic? && config.build.template_deps
        Logger.debug "Template deps: dynamic include/extends found — falling back to whole-site template invalidation."
      end

      # Compute global checksums for invalidation graph
      if cache_enabled
        # Hash the effective merged config (+ env + base_url override), not the
        # raw config.toml bytes, so env-override files and ${ENV_VAR} changes
        # correctly invalidate the per-page cache.
        #
        # Fold in a digest of the `data/` tree so editing a data file (which
        # feeds `site.data` into any page) invalidates the cache the same way a
        # config edit does. Without this, `build --cache` keeps serving stale
        # `site.data` values and diverges from `--full` (see I-cache-data).
        config_hash = Cache.compute_config_hash(config, ctx.options.env)
        config_hash = "#{config_hash}-#{compute_data_hash}-#{Cache.compute_options_hash(ctx.options)}"
        build_cache.set_global_checksums(@global_templates_hash, config_hash,
          invalidate_on_template_change: !@per_page_template_hash,
          output_dir: output_dir)
      end
    end
    profiler.end_phase
    result
  end

  private def setup_output_dir(output_dir : String, incremental : Bool = false)
    # Sanity-check the destination on EVERY path, not just the one that wipes
    # it. `--cache`, `--preserve-output` and `hwaro serve` all take the
    # incremental branch, and `build --cache -o content` used to exit 0 after
    # scattering `index.html` files through the source tree.
    guard_output_dir!(output_dir)
    # In incremental mode (--cache), keep existing output to avoid
    # re-generating unchanged pages and re-copying unchanged static files.
    if !incremental && Dir.exists?(output_dir)
      # Trailing separators are stripped for the symlink test only: `-o public/`
      # is what shell completion types, and lstat on a path ending in `/`
      # follows the final link, so `public/` would report as a plain directory.
      if File.symlink?(output_dir.rstrip(File::SEPARATOR))
        # A symlinked output directory (`ln -s /var/www/site public`) is a
        # deliberate publish-through-the-link setup, but `rm_rf` deletes the
        # LINK, not the tree behind it: Crystal's `rm_r` only recurses when
        # the path is a directory AND not a symlink, otherwise it unlinks.
        # The cold build therefore replaced `public` with a real directory —
        # silently, exit 0 — and every later build published somewhere nobody
        # deploys. Clear the contents behind the link instead: same clean
        # slate for the build, link (and deploy target) intact.
        entries = begin
          Dir.children(output_dir)
        rescue File::Error
          # Unreadable output directory: nothing we can clear here. The write
          # phase reports the real permission failure with a classified error.
          [] of String
        end
        # Say WHERE, once, before deleting anything. Publishing through a link
        # is the intended setup, but it also means a mis-aimed link makes the
        # cold build delete a tree the previous behavior never touched — and
        # the deletion is otherwise completely silent (build output is
        # identical either way, exit 0). Naming the resolved destination is
        # what lets an author notice the link points somewhere unexpected.
        unless entries.empty?
          Logger.info "Output directory #{output_dir} -> #{Hwaro::Utils::PathUtils.resolved_real_path(output_dir)} (clearing #{entries.size} entries behind the symlink)"
        end
        FileUtils.rm_rf(entries.map { |entry| File.join(output_dir, entry) })
      else
        FileUtils.rm_rf(output_dir)
      end
    end
    begin
      Hwaro::Utils::FileSafe.mkdir_p(output_dir)
    rescue ex : File::Error
      # `-o` pointing at an existing plain file (or /dev/null), a read-only
      # parent, a name the filesystem rejects: ordinary misconfiguration the
      # user can fix. Unclassified it reached the CLI as HWARO_E_INTERNAL /
      # exit 70 — the code reserved for hwaro bugs — so CI that alerts on
      # internal faults fired on a typo. Name the path and say what to do.
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_IO,
        message: "Cannot create output directory #{output_dir.inspect}: #{ex.message}",
        hint: "Remove or rename whatever occupies that path, or build into a different directory with -o/--output.",
        cause: ex,
      )
    end
  end

  # Directories a build READS. `output_dir` is wiped before a cold build, so
  # aiming it at one of these (`hwaro build -o content`) deleted the site's
  # own sources — silently, and with exit 0. Matching is on the RESOLVED
  # path, so an output directory that merely shares a prefix with one of
  # these names (`-o contents`, `-o static-site`) is unaffected.
  PROTECTED_INPUT_DIRS = %w[content templates static data i18n themes archetypes .git]

  # Reject an output directory that isn't a safe place to publish into. A cold
  # `hwaro build` clears `output_dir` before writing, and EVERY mode writes
  # files into it, so this runs on the incremental path too. A mistyped or
  # hostile value ("", ".", "/", an absolute path, an ancestor of the project,
  # or one of the project's own input directories) would otherwise turn the
  # cold `rm_rf` into a wipe of the filesystem root, the home directory or the
  # project source — and on `--cache`/`serve`, which never delete, still
  # scatter generated files through the source tree.
  private def guard_output_dir!(output_dir : String)
    expanded = File.expand_path(output_dir)
    # expand_path keeps a trailing separator, and `content/` must be
    # recognized as the same directory as `content`.
    expanded = expanded.rstrip(File::SEPARATOR) unless expanded == File::SEPARATOR_STRING
    # expand_path is also purely LEXICAL — it never follows symlinks — so a
    # single symlinked component hid the real destination from every rule
    # below: `ln -s content pub && hwaro build -o pub/archive` passed the
    # guard and let the cold `rm_rf` delete `content/archive`, and
    # `ln -s templates public && hwaro build --cache` overwrote the site's
    # own templates with rendered HTML. Judge the RESOLVED destination.
    expanded = resolved_real_path(expanded)
    cwd = resolved_real_path(File.expand_path(Dir.current))

    reason =
      if expanded == "/" || Path[expanded].parent.to_s == expanded
        "the filesystem root"
      elsif expanded == resolved_real_path(Path.home.to_s)
        # Resolved on both sides: `$HOME` is itself a symlink on plenty of
        # setups (/home/u -> /data/u), and comparing a resolved destination
        # against the unresolved `Path.home` would let `-o $HOME` through.
        "the home directory"
      elsif cwd == expanded || cwd.starts_with?(expanded + File::SEPARATOR)
        "the project directory (or a parent of it)"
      elsif input_dir = protected_input_dir(expanded, cwd)
        "the project's #{input_dir.inspect} directory (hwaro reads it as build input)"
      elsif File.basename(expanded) == ".git"
        "a git directory"
      elsif Dir.exists?(File.join(expanded, ".git"))
        "a repository root"
      end

    if reason
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_CONFIG,
        message: "Refusing to use #{reason} as the output directory: output_dir resolves to #{expanded.inspect}.",
        hint: "Point output_dir at a dedicated build directory such as \"public\" (hwaro build -o public)."
      )
    end
  end

  # The project input directory `expanded` is, or lives inside, if any.
  # `expanded` arrives symlink-resolved, so the roots must be resolved too:
  # a project whose `content/` is itself a symlink (a shared content tree)
  # would otherwise never match the lexical `<cwd>/content`.
  private def protected_input_dir(expanded : String, cwd : String) : String?
    PROTECTED_INPUT_DIRS.find do |dir|
      root = resolved_real_path(File.join(cwd, dir))
      expanded == root || expanded.starts_with?(root + File::SEPARATOR)
    end
  end

  # `path` with every symlink resolved, including when it does not exist yet:
  # resolve the deepest existing ancestor and re-append the missing tail. A
  # not-yet-created output directory is the normal case (`-o public` on a
  # fresh checkout), so bailing out on a missing leaf would leave exactly the
  # paths this guard exists for unresolved. Falls back to the given path when
  # resolution fails (broken link, symlink loop, unreadable ancestor) —
  # lexical matching is what we had before, so a failure never loosens the
  # guard below the old behavior.
  private def resolved_real_path(path : String) : String
    suffix = [] of String
    current = path
    until File.exists?(current)
      parent = File.dirname(current)
      return path if parent == current
      suffix << File.basename(current)
      current = parent
    end
    real = File.realpath(current)
    suffix.reverse_each { |part| real = File.join(real, part) }
    real
  rescue File::Error | IO::Error
    path
  end

  private def copy_static_files(output_dir : String, verbose : Bool, incremental : Bool = false)
    return unless Dir.exists?("static")

    # Single source of truth for both cold and incremental builds: walk
    # `static/` once (including hidden entries like `.well-known/`), drop
    # excluded cruft, then copy the survivors in parallel. Keeping both modes
    # on the same path guarantees `--cache` and cold builds publish exactly
    # the same files (see issues #610/#611).
    files_to_copy = collect_static_files("static", output_dir, static_publish_config, incremental)
    return if files_to_copy.empty?

    copy_static_pairs(files_to_copy)

    label = incremental ? "static files (#{files_to_copy.size} updated)" : "static files"
    Logger.action :copy, label, Logger::Role::Dim if verbose
  end

  # The effective `[static]` publishing config, falling back to defaults (which
  # keep the built-in cruft denylist on) when config hasn't loaded yet — e.g.
  # in unit tests that exercise the copy directly. Shared by both the full
  # build and the serve-watch copy so they filter identically.
  private def static_publish_config : Models::StaticConfig
    @config.try(&.static) || Models::StaticConfig.new
  end

  # `File.info?` on a symlink target, with an unresolvable link reported the
  # same way as a dangling one (nil) instead of raising.
  #
  # `File.info?` only swallows ENOENT/ENOTDIR; a symlink cycle
  # (`ln -s loop static/loop`) fails with ELOOP, which raises `File::Error`.
  # Nothing between here and the phase runner caught it, so a single bad link
  # aborted the entire build as `HWARO_E_INTERNAL` with an EMPTY output
  # directory, and under `serve` it wedged the watcher into an endless
  # "Watcher iteration failed" retry from which no rebuild could recover.
  # A link we cannot resolve is simply not publishable — skip it and say so.
  private def static_target_info(src_path : String) : File::Info?
    File.info?(src_path, follow_symlinks: true)
  rescue ex : File::Error
    Logger.warn "Skipping unresolvable static symlink: #{src_path}"
    Logger.debug "Static symlink stat failed: #{ex.message}"
    nil
  end

  # Walk `static/` and return the `{src, dest}` pairs that need copying.
  #
  # Hidden files/dirs are matched explicitly via `DotFiles` — Crystal's glob
  # skips them by default, which previously dropped `.well-known/` from cached
  # builds (#610). Excluded paths (`StaticConfig#excluded?`) are filtered out
  # for both modes (#611). In incremental mode, files whose destination is
  # newer-or-equal are skipped.
  # Widest timestamp granularity a destination filesystem is likely to have
  # (FAT/exFAT store 2-second resolution).
  MTIME_SKIP_TOLERANCE = 2.seconds

  private def collect_static_files(
    src_dir : String,
    output_dir : String,
    static_config : Models::StaticConfig,
    incremental : Bool,
  ) : Array({String, String, Time})
    files_to_copy = [] of {String, String, Time}
    glob_match = File::MatchOptions.glob_default | File::MatchOptions::DotFiles

    Dir.glob(File.join(src_dir, "**", "*"), match: glob_match) do |src_path|
      # lstat first: for the common regular-file case one syscall covers
      # the directory check AND proves it isn't a symlink (previously every
      # file paid a stat plus an lstat). Only actual symlinks pay the
      # follow-up target stat and realpath cost.
      lstat = File.info?(src_path, follow_symlinks: false)
      next if lstat.nil?

      if lstat.symlink?
        # Skip dangling symlinks (`info?` nil when the target is missing) so
        # the copy worker doesn't log a spurious failure, and directories.
        # Unresolvable links (symlink cycles) also come back nil here — see
        # `static_target_info`.
        info = static_target_info(src_path)
        next if info.nil? || info.directory?

        # A symlinked file whose target escapes the project would publish
        # content from outside the site (e.g. `static/leak -> ~/.ssh/id_rsa`).
        # Skip those; in-repo symlinks resolve back within the project root
        # and are still copied.
        unless Hwaro::Utils::PathUtils.resolves_within?(src_path, Dir.current)
          Logger.warn "Skipping static symlink pointing outside the project: #{src_path}"
          next
        end
      else
        next if lstat.directory?
        info = lstat
      end

      # Only regular files are publishable. `static/` can also hold a FIFO, a
      # unix socket or a device node (a stray `mkfifo`, an editor/daemon
      # socket left in the tree): `FileUtils.cp` opens the source for reading
      # and `open(2)` on a FIFO with no writer BLOCKS FOREVER, so one such
      # entry hung the whole build with no output at all. Directories are
      # already filtered above, so anything reaching here that isn't a file is
      # unpublishable and worth saying out loud.
      unless info.type.file?
        Logger.warn "Skipping non-regular static file: #{src_path}"
        next
      end

      relative = Path[src_path].relative_to(src_dir).to_s
      next if static_config.excluded?(relative)
      # SCSS sources compile via the sass:compile hook instead of
      # publishing raw.
      next if @config.try(&.sass_source?(relative))

      dest_path = File.join(output_dir, relative)
      # `info` from above already carries the source mtime — re-statting
      # src_path here tripled the stat count over static/ on watch rebuilds.
      #
      # Skip on SIZE equality plus mtime equality within a tolerance, the same
      # shape the Write phase uses for bundle assets. Two reasons it is not an
      # ordering test and not exact:
      #   * `source <= destination` skipped any source whose mtime moved
      #     BACKWARDS — what `git checkout`, `git stash pop` and
      #     `rsync --times` do — serving the previous revision's asset forever.
      #   * exact equality never holds when the DESTINATION filesystem stores
      #     coarser timestamps than the source (exFAT/FAT32 2s, HFS+ 1s, some
      #     SMB/NFS and Docker bind mounts), which would re-copy the whole
      #     `static/` tree on every incremental build and every serve rebuild.
      if incremental && (dest_info = File.info?(dest_path)) &&
         info.size == dest_info.size &&
         (info.modification_time - dest_info.modification_time).abs <= MTIME_SKIP_TOLERANCE
        next
      end

      files_to_copy << {src_path, dest_path, info.modification_time}
    end

    files_to_copy
  end

  # Copy the given `{src, dest}` pairs using a parallel worker pool. Directory
  # creation stays sequential to avoid the check-then-create race that fires
  # under the multi-threaded runtime.
  private def copy_static_pairs(files_to_copy : Array({String, String, Time}))
    files_to_copy.each { |_, dest, _| Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest)) }

    config = ParallelConfig.new(enabled: true)
    worker_count = config.calculate_workers(files_to_copy.size)

    work_queue = Channel({String, String, Time}).new(files_to_copy.size)
    done = Channel(Nil).new(worker_count)

    files_to_copy.each { |pair| work_queue.send(pair) }
    work_queue.close

    worker_count.times do
      spawn do
        while pair = work_queue.receive?
          src, dest, src_mtime = pair
          begin
            FileUtils.cp(src, dest)
            # Stamp the source mtime onto the copy so the incremental skip in
            # collect_static_files can compare timestamps at all — that is what
            # makes a source whose mtime moved BACKWARDS (git checkout, stash
            # pop, rsync --times) still count as changed. `src_mtime` comes
            # from the stat collect_static_files already did; re-stating here
            # tripled the stat count over static/ on watch rebuilds.
            begin
              File.utime(Time.utc, src_mtime, dest)
            rescue ex : File::Error
              # Stamping is an optimization; a failure just means the next
              # build recopies this file. It must NOT be reported as a copy
              # failure — the copy above already succeeded — but it should be
              # discoverable when someone is asking why nothing is cached.
              Logger.debug "Could not stamp mtime on #{dest}: #{ex.message}"
            end
          rescue ex
            Logger.error "Copy failed #{src} -> #{dest}: #{ex.message}"
          end
        end
      ensure
        done.send(nil)
      end
    end
    worker_count.times { done.receive }
  end

  private def load_templates : Hash(String, String)
    if cached = @templates
      return cached
    end

    templates = {} of String => String
    # Built fresh and swapped in (never mutated in place) so a loader
    # holding the previous snapshot keeps a consistent pair of hashes.
    template_paths = {} of String => String
    # Extension-shadowed variants (foo.j2 while foo.html won the slot).
    # They never enter `templates`, but an explicit `{% include "foo.j2" %}`
    # still reads them from disk via the loader fallback — so run_rerender's
    # "did anything change?" diff must see their edits too (path → MD5).
    shadowed_hashes = {} of String => String
    if Dir.exists?("templates")
      # Single glob for all supported template extensions.
      # Priority: html > j2 > jinja2 > jinja > ecr (first loaded wins via ||=)
      extension_priority = {"html" => 0, "j2" => 1, "jinja2" => 2, "jinja" => 3, "ecr" => 4}
      all_template_files = Dir.glob("templates/**/*.{html,j2,jinja2,jinja,ecr}")
      # Sort by extension priority so higher-priority extensions are loaded
      # first. `[]?` matters: `Hash#[]` raises on a miss, so the intended
      # `|| 99` fallback was unreachable if the glob ever admits a new
      # extension not present in the priority map.
      all_template_files.sort_by! { |path| extension_priority[Path[path].extension.lchop('.')]? || 99 }
      all_template_files.each do |path|
        relative = Path[path].relative_to("templates")
        name = relative.to_s.gsub(Builder::TEMPLATE_EXTENSION_REGEX, "")
        # Don't overwrite if already loaded (higher priority extensions loaded first)
        if templates.has_key?(name)
          if source = read_template_source(path)
            shadowed_hashes[path] = Digest::MD5.hexdigest(source)
          end
        else
          if source = read_template_source(path)
            templates[name] = source
            template_paths[name] = path
          end
        end
      end
    end

    unless templates.has_key?("page")
      if templates.has_key?("default")
        templates["page"] = templates["default"]
        if default_path = template_paths["default"]?
          template_paths["page"] = default_path
        end
      end
    end
    @template_paths = template_paths
    @shadowed_template_hashes = shadowed_hashes

    # (Re)build the template dependency graph for selective invalidation.
    # `template_paths` lets the graph detect literal refs the snapshot
    # loader cannot serve (shadowed extension variants etc.) — see
    # TemplateDeps#snapshot_escaping_refs.
    @template_deps = TemplateDeps.new(templates, template_paths)

    # (Re)build the render-hook registry — nil when no templates/hooks/render-*
    # template exists, which is the zero-cost gate the render path checks
    # before doing any hook-related work.
    Content::Processors::RenderHooks.configure(templates, @template_paths)

    # Precompute, per template source, whether the shortcode processor could
    # rewrite it — apply_template consults this to skip its per-page scan.
    # Rebuilt together with the templates hash so serve-mode template edits
    # can't read a stale decision.
    @template_shortcode_scan.clear
    templates.each_value do |source|
      @template_shortcode_scan[source.hash] = shortcode_scan_needed?(source)
    end

    # Precompute the Crinja-owned regions masked out of each template that the
    # shortcode pass will actually touch. Two reasons this belongs here rather
    # than in apply_template:
    #
    #   * cost — masking is a pure function of the source but ran once per
    #     rendered PAGE, which is a fixed per-page overhead on the layout every
    #     page in a section shares;
    #   * correctness — a macro declared in a base layout and called from the
    #     template that `{% extends %}` it is invisible to a single-source
    #     scan, and the whole template set is only in hand here.
    #
    # Rebuilt alongside the templates hash so a serve-mode edit can't read a
    # stale mask, and written single-threaded before any render worker spawns.
    @template_literal_masks.clear
    callable_memo = {} of String => Set(String)
    chain = [] of String
    templates.each do |name, source|
      next if @template_shortcode_scan[source.hash]? == false
      callables = inherited_template_callables(name, templates, callable_memo, chain)
      @template_literal_masks[source.hash] = mask_template_literals(source, callables)
    end

    compute_template_var_features(templates)

    # Publish the snapshot BEFORE (re)building the Crinja environment so its
    # snapshot-backed loader captures this load's template set.
    @templates = templates

    # Initialize Crinja environment with the snapshot-backed loader
    @crinja_env = setup_crinja_env

    templates
  end

  # Templates referenced by literal name that the snapshot loader cannot
  # serve (./-prefixed, non-template extensions, shadowed extension
  # variants — see TemplateDeps#snapshot_escaping_refs) are read from DISK
  # at render time: their bytes reach the output but live in no snapshot
  # hash. Fold their current disk contents into the global templates
  # checksum so editing one invalidates the `--cache` entries. The graph is
  # dynamic whenever such refs exist, so this folded hash is exactly the
  # one every page's cache entry stores and compares.
  private def fold_snapshot_escaping_refs(base : String, refs : Set(String)) : String
    digest = Digest::MD5.new
    Utils::DigestUtils.update_length_prefixed(digest, base)
    refs.to_a.sort!.each do |ref|
      path = File.join("templates", ref)
      content_hash = begin
        File.exists?(path) ? Digest::MD5.hexdigest(File.read(path)) : "<absent>"
      rescue
        # Unreadable mid-save: treat as absent; the next build re-hashes.
        "<absent>"
      end
      Utils::DigestUtils.update_length_prefixed(digest, ref)
      Utils::DigestUtils.update_length_prefixed(digest, content_hash)
    end
    digest.final.hexstring
  end

  # How long `read_template_source` rides out a template file that a glob
  # just found but a read can't open — the delete-then-recreate window of
  # editors using "safe write" saves (vim without backupcopy, some IDEs).
  TEMPLATE_READ_RETRIES        = 4
  TEMPLATE_READ_RETRY_INTERVAL = 25.milliseconds

  # Read a template's source, retrying briefly when the file is momentarily
  # unreadable mid-save. A file that stays unreadable is treated as deleted
  # (skipped with a warning) rather than aborting the whole build — during
  # serve, the watcher's removed-file detection follows up with a full
  # rebuild once the filesystem settles.
  private def read_template_source(path : String) : String?
    attempts = 0
    loop do
      source = File.read(path)
      # `File.read` does not validate UTF-8, so a single stray byte (0xff from
      # a latin-1 paste, a truncated multi-byte sequence) used to travel into
      # the templates hash intact — and the first PCRE2 pass over it
      # (TemplateDeps' reference scan) aborted the whole Initialize phase with
      # "Regex match error: UTF-8 error: illegal byte", reported as an
      # internal error naming no file. Content, data files and SCSS all
      # degrade per-file here, so templates must too: scrub the offending
      # bytes and name the template so the user can find it.
      unless source.valid_encoding?
        Logger.warn "Template #{path} contains invalid UTF-8; the offending bytes were replaced."
        source = source.scrub
      end
      return source
    rescue ex : IO::Error
      attempts += 1
      if attempts >= TEMPLATE_READ_RETRIES
        Logger.warn "Could not read template #{path} (#{ex.message}); skipping it for this build."
        return
      end
      sleep TEMPLATE_READ_RETRY_INTERVAL
    end
  end

  # Decide, per entry template, which expensive per-page variables its static
  # closure can reach (see Builder::TemplateVarFeatures). A template is gated
  # only when every closure member resolves to a loaded source (an unknown
  # include leaves the closure incomplete) and no member can carry shortcodes.
  private def compute_template_var_features(templates : Hash(String, String))
    @template_var_features.clear
    deps = @template_deps
    return unless deps
    # A dynamic include (`{% include var %}`) makes every closure incomplete.
    return if deps.dynamic?

    templates.each_key do |name|
      closure = deps.closure(name)
      sources = closure.compact_map { |dep| templates[dep]? }
      next unless sources.size == closure.size
      next unless sources.all? { |src| @template_shortcode_scan[src.hash]? == false }

      union = sources.join('\n')
      # NOTE: "og_all_tags" is NOT a substring of "og_tags" (or vice versa) —
      # both must be listed, or a template using only {{ og_all_tags }}
      # would lose its OG block.
      @template_var_features[name] = Builder::TemplateVarFeatures.new(
        needs_seo: union.includes?("og_tags") || union.includes?("og_all_tags") ||
                   union.includes?("twitter_tags") ||
                   union.includes?("canonical_tag") || union.includes?("hreflang_tags") ||
                   union.includes?("alternate_output_tags") ||
                   union.includes?("seo"),
        needs_jsonld: union.includes?("jsonld"),
        needs_section_pages: union.includes?("section"),
        # Targeted on purpose — see the record's doc comment. These feed the
        # render worker heuristic, where a false positive costs parallelism.
        listing_fanout_site: union.includes?("site.pages"),
        listing_fanout_section: union.includes?("section.pages"),
      )
    end
  end

  # Setup Crinja environment with custom filters, tests, and functions
  private def setup_crinja_env : Crinja
    env = Content::Processors::Template.engine.env

    # The engine is a process-lifetime singleton and Crinja's InMemory
    # template cache keys entries by (env, name, file, SOURCE) — every
    # serve-mode template reload would add a fresh generation of compiled
    # templates without ever evicting the previous one. Start each snapshot
    # with a fresh cache so long serve sessions don't accumulate every
    # historical template source in memory.
    env.cache = Crinja::TemplateCache::InMemory.new

    # Set up template loader for template inheritance and includes
    if loader = build_template_loader
      env.loader = loader
    end

    env
  end

  # Get or create Crinja environment
  private def crinja_env : Crinja
    @crinja_env ||= setup_crinja_env
  end

  # Create a fresh, independent Crinja environment for parallel workers.
  # Each worker fiber gets its own env to avoid shared mutable state in
  # Crinja's `with_scope` (which mutates @context on the environment).
  private def create_fresh_crinja_env : Crinja
    engine = Content::Processors::TemplateEngine.new
    env = engine.env
    if loader = build_template_loader
      env.loader = loader
    end
    env
  end

  # Loader for `{% include %}`/`{% extends %}` resolution. Once templates
  # are loaded, references resolve against the in-memory snapshot (see
  # SnapshotTemplateLoader) so a rebuild can't observe half-written files
  # an editor is rewriting mid-render; before that (or for names outside
  # the snapshot) the filesystem loader answers, exactly as before.
  private def build_template_loader : Crinja::Loader?
    return unless Dir.exists?("templates")
    disk = Crinja::Loader::FileSystemLoader.new("templates/")
    if (templates = @templates) && !templates.empty?
      SnapshotTemplateLoader.new(templates, @template_paths, disk)
    else
      disk
    end
  end

  # Tree node used while assembling `site.data` from the `data/` directory.
  # Each node can hold a leaf value (a parsed data file) and/or a map of
  # children (subdirectory entries). When both are present the children
  # win — see `load_data_files`.
  private class DataTreeNode
    getter children : Hash(String, DataTreeNode) = {} of String => DataTreeNode
    property value : Crinja::Value? = nil
    property source_path : String? = nil
  end

  # Content digest of everything that feeds `site.data`, for cache
  # invalidation: the `data/` directory (and i18n/) plus any fetched
  # `[[data.remote]]` payloads.
  private def compute_data_hash : String
    disk = compute_disk_data_hash
    # Remote payloads feed `site.data` exactly like `data/` files, so their
    # bytes (captured by load_remote_data earlier in this phase) must feed
    # the cache invalidation digest the same way — a changed payload has to
    # invalidate cached pages. Empty (the "" no-remote-sources case) keeps
    # the hash byte-identical to what it was before this feature existed.
    remote = @remote_data_digest
    return disk if remote.empty?
    "#{disk}-remote:#{remote}"
  end

  # Compute a content digest of the `data/` directory for cache invalidation.
  #
  # Globs every supported data file, sorts the paths for determinism, and folds
  # both the path and the raw bytes of each file into an MD5. It is deliberately
  # mtime-independent (content-only) so a touch-without-edit doesn't churn the
  # cache, while any real edit, add, or rename changes the digest and triggers
  # the existing "config change invalidates all entries" path. Returns "" when
  # there is no `data/` directory.
  private def compute_disk_data_hash : String
    return "" unless Dir.exists?("data") || Dir.exists?("i18n")

    paths = [] of String
    # i18n translations feed every localized string the same way data files
    # feed templates — an i18n edit must invalidate cached pages too, or
    # `build --cache` ships stale translations while `serve` (which watches
    # i18n/) rebuilds correctly.
    Dir.glob("data/**/*.{yml,yaml,json,toml}", "i18n/**/*.{yml,yaml,json,toml}") do |path|
      next if File.directory?(path)
      paths << path
    end
    return "" if paths.empty?

    digest = Digest::MD5.new
    paths.sort!.each do |path|
      # Length-prefixed (see DigestUtils) so adjacent path/content pairs
      # can't collide across boundaries.
      Utils::DigestUtils.update_length_prefixed(digest, path)
      Utils::DigestUtils.update_length_prefixed(digest, File.read(path))
    end
    digest.final.hexstring
  end

  # Load data files from `data/`, preserving directory structure.
  #
  # A file at `data/users/alice.yml` is exposed as `site.data.users.alice`,
  # and the parent map `site.data.users` is iterable in templates
  # (`{% for name, user in site.data.users %}`). When a directory and a
  # sibling file share the same stem (e.g. `data/users.yml` alongside
  # `data/users/`), the directory wins and a warning is emitted for the
  # shadowed file.
  private def load_data_files(site : Models::Site, config : Models::Config)
    site.data.clear
    @remote_data_digest = ""

    root = DataTreeNode.new

    if Dir.exists?("data")
      # Process deeper paths first so directory namespaces are established
      # before any same-stem root-level file can claim the key.
      entries = [] of {Array(String), String, String}
      Dir.glob("data/**/*.{yml,yaml,json,toml}") do |path|
        next if File.directory?(path)
        rel = Path[path].relative_to("data")
        parts = rel.parts
        stem = Path[parts.last].stem
        dir_parts = parts[0...-1]
        entries << {dir_parts, stem, path}
      end
      entries.sort_by! { |(dir_parts, _, _)| -dir_parts.size }

      entries.each do |(dir_parts, stem, path)|
        value = parse_data_file(path)
        next unless value

        node = root
        dir_parts.each do |segment|
          node = node.children[segment] ||= DataTreeNode.new
        end

        existing = node.children[stem]?
        if existing && !existing.children.empty?
          Logger.warn "Data file '#{path}' is shadowed by directory 'data/#{(dir_parts + [stem]).join('/')}/'; directory takes precedence."
          next
        end

        leaf = existing || DataTreeNode.new
        if prior = leaf.source_path
          Logger.warn "Duplicate data key for 'site.data.#{(dir_parts + [stem]).join('.')}': '#{path}' overwrites '#{prior}'."
        end
        leaf.value = value
        leaf.source_path = path
        node.children[stem] = leaf
        Logger.debug "Loaded data file: #{path} as site.data.#{(dir_parts + [stem]).join('.')}"
      end
    end

    root.children.each do |key, child|
      site.data[key] = data_tree_to_crinja(child)
    end

    load_remote_data(site, config, root)
  end

  # `[[data.remote]]` sources, fetched once per build AFTER the disk tree is
  # assembled so a key collision can name the exact disk source it clashes
  # with. A collision is a hard config error rather than a precedence rule —
  # silently preferring either side would make `site.data.<key>` depend on
  # network state. Collisions are checked for every entry before the first
  # fetch so the error never costs a network round-trip.
  private def load_remote_data(site : Models::Site, config : Models::Config, root : DataTreeNode)
    entries = config.data_remote
    return if entries.empty?

    entries.each do |entry|
      next unless node = root.children[entry.key]?
      disk_source = node.source_path || "data/#{entry.key}/"
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_CONFIG,
        message: "site.data.#{entry.key} has two sources: '#{disk_source}' on disk and [[data.remote]] \"#{entry.key}\" (#{RemoteData.sanitized_url(entry.url)}).",
        hint: "Rename the [[data.remote]] key or the data/ file — each site.data key must have exactly one source.",
      )
    end

    digest = Digest::MD5.new
    entries.each do |entry|
      result = RemoteData.load(entry)
      Utils::DigestUtils.update_length_prefixed(digest, entry.key)
      if result
        site.data[entry.key] = result.value
        Utils::DigestUtils.update_length_prefixed(digest, result.body)
      else
        # warn-and-skip left the key unset: fold the absence too, so a
        # payload that disappears invalidates cached pages the same way an
        # edit does.
        Utils::DigestUtils.update_length_prefixed(digest, "<skipped>")
      end
    end
    @remote_data_digest = digest.final.hexstring
  end

  private def data_tree_to_crinja(node : DataTreeNode) : Crinja::Value
    if node.children.empty?
      node.value || Crinja::Value.new(nil)
    else
      # Invariant: depth-first processing + directory-wins collision
      # handling means a node with children must never also carry a
      # leaf value — the leaf would have been rejected with a warning.
      # Guard here so a future change to the sort or conflict rules
      # fails loudly instead of silently dropping data.
      if source = node.source_path
        raise "load_data_files invariant broken: node at '#{source}' has both leaf value and children"
      end
      converted = {} of String => Crinja::Value
      node.children.each do |k, child|
        converted[k] = data_tree_to_crinja(child)
      end
      Crinja::Value.new(converted)
    end
  end

  private def parse_data_file(path : String) : Crinja::Value?
    ext = File.extname(path).downcase
    # JSON and TOML both reject a leading BOM outright, so a data file saved
    # by a Windows editor would warn-and-skip and leave `site.data.<key>`
    # undefined — which then fails the whole render.
    content = Utils::TextUtils.strip_bom(File.read(path))
    case ext
    when ".yml", ".yaml"
      Utils::CrinjaUtils.from_yaml(YAML.parse(content))
    when ".json"
      Utils::CrinjaUtils.from_json(JSON.parse(content))
    when ".toml"
      Utils::CrinjaUtils.from_toml(TOML.parse(content))
    end
  rescue ex
    # This rescue also covers read errors and value-conversion failures, not
    # just parse errors, so it must not assert the file is malformed — it once
    # blamed the author for a "parse error" on a TOML file that parsed
    # perfectly. Name the consequence instead: the key disappears from
    # site.data, and templates dereferencing it then fail the whole render.
    Logger.warn "Skipping data file #{path} (site.data entry dropped): #{ex.message}"
    nil
  end
end
