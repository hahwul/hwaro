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
      load_data_files(site)

      # Load i18n translations
      i18n_dir = File.join("i18n")
      @i18n_translations = Content::I18n.load_translations(i18n_dir, config)

      @config = config
      ctx.site = @site
      ctx.config = config

      # Propagate the highlighting mode to the markdown renderer once per
      # build — read-only afterwards, including by parallel render fibers.
      Content::Processors::SyntaxHighlighter.server_mode = config.highlight.server?

      ctx.templates = load_templates
      @templates = ctx.templates

      # Per-page template closure hashes replace the invalidate-everything
      # template checksum when dependency tracking is on AND every template
      # reference resolved statically (no variable includes).
      @global_templates_hash = Cache.compute_templates_hash(ctx.templates)
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
        config_hash = "#{config_hash}-#{compute_data_hash}"
        build_cache.set_global_checksums(@global_templates_hash, config_hash,
          invalidate_on_template_change: !@per_page_template_hash)
      end
    end
    profiler.end_phase
    result
  end

  private def setup_output_dir(output_dir : String, incremental : Bool = false)
    if Dir.exists?(output_dir)
      # In incremental mode (--cache), keep existing output to avoid
      # re-generating unchanged pages and re-copying unchanged static files.
      unless incremental
        guard_destructive_clean!(output_dir)
        FileUtils.rm_rf(output_dir)
      end
    end
    Hwaro::Utils::FileSafe.mkdir_p(output_dir)
  end

  # Refuse to recursively delete a directory that isn't safely *inside* a
  # sane workspace. A cold `hwaro build` clears `output_dir` before writing;
  # a mistyped or hostile config value (""/"."/"/"/an absolute path/an
  # ancestor of the project) would turn that `rm_rf` into a wipe of the
  # filesystem root, the home directory, or the project source itself.
  private def guard_destructive_clean!(output_dir : String)
    expanded = File.expand_path(output_dir)
    cwd = File.expand_path(Dir.current)

    reason =
      if expanded == "/" || Path[expanded].parent.to_s == expanded
        "the filesystem root"
      elsif expanded == Path.home.to_s
        "the home directory"
      elsif cwd == expanded || cwd.starts_with?(expanded + File::SEPARATOR)
        "the project directory (or a parent of it)"
      end

    if reason
      raise Hwaro::HwaroError.new(
        code: Hwaro::Errors::HWARO_E_CONFIG,
        message: "Refusing to delete #{reason}: output_dir resolves to #{expanded.inspect}.",
        hint: "Point output_dir at a dedicated subdirectory such as \"public\"."
      )
    end
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
    Logger.action :copy, label, :blue if verbose
  end

  # The effective `[static]` publishing config, falling back to defaults (which
  # keep the built-in cruft denylist on) when config hasn't loaded yet — e.g.
  # in unit tests that exercise the copy directly. Shared by both the full
  # build and the serve-watch copy so they filter identically.
  private def static_publish_config : Models::StaticConfig
    @config.try(&.static) || Models::StaticConfig.new
  end

  # Walk `static/` and return the `{src, dest}` pairs that need copying.
  #
  # Hidden files/dirs are matched explicitly via `DotFiles` — Crystal's glob
  # skips them by default, which previously dropped `.well-known/` from cached
  # builds (#610). Excluded paths (`StaticConfig#excluded?`) are filtered out
  # for both modes (#611). In incremental mode, files whose destination is
  # newer-or-equal are skipped.
  private def collect_static_files(
    src_dir : String,
    output_dir : String,
    static_config : Models::StaticConfig,
    incremental : Bool,
  ) : Array({String, String})
    files_to_copy = [] of {String, String}
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
        info = File.info?(src_path, follow_symlinks: true)
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

      relative = Path[src_path].relative_to(src_dir).to_s
      next if static_config.excluded?(relative)

      dest_path = File.join(output_dir, relative)
      # `info` from above already carries the source mtime — re-statting
      # src_path here tripled the stat count over static/ on watch rebuilds.
      if incremental && (dest_info = File.info?(dest_path)) &&
         info.modification_time <= dest_info.modification_time
        next
      end

      files_to_copy << {src_path, dest_path}
    end

    files_to_copy
  end

  # Copy the given `{src, dest}` pairs using a parallel worker pool. Directory
  # creation stays sequential to avoid the check-then-create race that fires
  # under the multi-threaded runtime.
  private def copy_static_pairs(files_to_copy : Array({String, String}))
    files_to_copy.each { |_, dest| Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest)) }

    config = ParallelConfig.new(enabled: true)
    worker_count = config.calculate_workers(files_to_copy.size)

    work_queue = Channel({String, String}).new(files_to_copy.size)
    done = Channel(Nil).new(worker_count)

    files_to_copy.each { |pair| work_queue.send(pair) }
    work_queue.close

    worker_count.times do
      spawn do
        while pair = work_queue.receive?
          src, dest = pair
          begin
            FileUtils.cp(src, dest)
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
    @template_paths.clear
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
        unless templates.has_key?(name)
          templates[name] = File.read(path)
          @template_paths[name] = path
        end
      end
    end

    unless templates.has_key?("page")
      if templates.has_key?("default")
        templates["page"] = templates["default"]
        if default_path = @template_paths["default"]?
          @template_paths["page"] = default_path
        end
      end
    end

    # (Re)build the template dependency graph for selective invalidation
    @template_deps = TemplateDeps.new(templates)

    # Initialize Crinja environment with file system loader
    @crinja_env = setup_crinja_env

    @templates = templates
  end

  # Setup Crinja environment with custom filters, tests, and functions
  private def setup_crinja_env : Crinja
    env = Content::Processors::Template.engine.env

    # Set up file system loader for template inheritance and includes
    if Dir.exists?("templates")
      env.loader = Crinja::Loader::FileSystemLoader.new("templates/")
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
    if Dir.exists?("templates")
      env.loader = Crinja::Loader::FileSystemLoader.new("templates/")
    end
    env
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

  # Compute a content digest of the `data/` directory for cache invalidation.
  #
  # Globs every supported data file, sorts the paths for determinism, and folds
  # both the path and the raw bytes of each file into an MD5. It is deliberately
  # mtime-independent (content-only) so a touch-without-edit doesn't churn the
  # cache, while any real edit, add, or rename changes the digest and triggers
  # the existing "config change invalidates all entries" path. Returns "" when
  # there is no `data/` directory.
  private def compute_data_hash : String
    return "" unless Dir.exists?("data")

    paths = [] of String
    Dir.glob("data/**/*.{yml,yaml,json,toml}") do |path|
      next if File.directory?(path)
      paths << path
    end
    return "" if paths.empty?

    digest = Digest::MD5.new
    paths.sort!.each do |path|
      content = File.read(path)
      # Length-prefix both fields so adjacent path/content pairs can't
      # collide across boundaries (the "a"+"bc" vs "ab"+"c" ambiguity) —
      # same reason fingerprint_string in parse_content.cr length-prefixes.
      digest.update(path.bytesize.to_s)
      digest.update(":")
      digest.update(path)
      digest.update(content.bytesize.to_s)
      digest.update(":")
      digest.update(content)
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
  private def load_data_files(site : Models::Site)
    site.data.clear

    return unless Dir.exists?("data")

    root = DataTreeNode.new

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

    root.children.each do |key, child|
      site.data[key] = data_tree_to_crinja(child)
    end
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
    content = File.read(path)
    case ext
    when ".yml", ".yaml"
      Utils::CrinjaUtils.from_yaml(YAML.parse(content))
    when ".json"
      Utils::CrinjaUtils.from_json(JSON.parse(content))
    when ".toml"
      Utils::CrinjaUtils.from_toml(TOML.parse(content))
    end
  rescue ex
    Logger.warn "Failed to parse data file #{path}: #{ex.message}"
    nil
  end
end
