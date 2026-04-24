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

      ctx.templates = load_templates
      @templates = ctx.templates

      # Compute global checksums for invalidation graph
      if cache_enabled
        template_hash = Cache.compute_templates_hash(ctx.templates)
        config_hash = Cache.compute_config_hash
        build_cache.set_global_checksums(template_hash, config_hash)
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
        FileUtils.rm_rf(output_dir)
      end
    end
    FileUtils.mkdir_p(output_dir)
  end

  private def copy_static_files(output_dir : String, verbose : Bool, incremental : Bool = false)
    return unless Dir.exists?("static")

    if incremental
      # Incremental mode: only copy files that are newer than their destination
      copy_static_files_incremental("static", output_dir, verbose)
    else
      FileUtils.cp_r("static/.", "#{output_dir}/")
      Logger.action :copy, "static files", :blue if verbose
    end
  end

  # Copy only changed static files by comparing mtime, using parallel I/O
  private def copy_static_files_incremental(src_dir : String, output_dir : String, verbose : Bool)
    # First pass: collect files that need copying (sequential, fast stat calls)
    files_to_copy = [] of {String, String} # {src, dest}
    Dir.glob(File.join(src_dir, "**", "*")) do |src_path|
      next if File.directory?(src_path)

      relative = Path[src_path].relative_to(src_dir).to_s
      dest_path = File.join(output_dir, relative)

      needs_copy = if File.exists?(dest_path)
                     File.info(src_path).modification_time > File.info(dest_path).modification_time
                   else
                     true
                   end

      files_to_copy << {src_path, dest_path} if needs_copy
    end

    return if files_to_copy.empty?

    # Ensure destination directories exist (must be sequential to avoid races)
    files_to_copy.each { |_, dest| FileUtils.mkdir_p(File.dirname(dest)) }

    # Second pass: copy files in parallel using worker pool
    config = ParallelConfig.new(enabled: true)
    worker_count = config.calculate_workers(files_to_copy.size)

    work_queue = Channel({String, String}).new(files_to_copy.size)
    done = Channel(Nil).new(worker_count)

    files_to_copy.each { |pair| work_queue.send(pair) }
    work_queue.close

    worker_count.times do
      spawn do
        begin
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
    end
    worker_count.times { done.receive }

    Logger.action :copy, "static files (#{files_to_copy.size} updated)", :blue if verbose
  end

  private def load_templates : Hash(String, String)
    if cached = @templates
      return cached
    end

    templates = {} of String => String
    if Dir.exists?("templates")
      # Single glob for all supported template extensions.
      # Priority: html > j2 > jinja2 > jinja > ecr (first loaded wins via ||=)
      extension_priority = {"html" => 0, "j2" => 1, "jinja2" => 2, "jinja" => 3, "ecr" => 4}
      all_template_files = Dir.glob("templates/**/*.{html,j2,jinja2,jinja,ecr}")
      # Sort by extension priority so higher-priority extensions are loaded first
      all_template_files.sort_by! { |path| extension_priority[Path[path].extension.lchop('.')] || 99 }
      all_template_files.each do |path|
        relative = Path[path].relative_to("templates")
        name = relative.to_s.gsub(Builder::TEMPLATE_EXTENSION_REGEX, "")
        # Don't overwrite if already loaded (higher priority extensions loaded first)
        templates[name] ||= File.read(path)
      end
    end

    unless templates.has_key?("page")
      if templates.has_key?("default")
        templates["page"] = templates["default"]
      end
    end

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
