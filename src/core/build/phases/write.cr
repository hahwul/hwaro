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

      # Process raw files (JSON, XML)
      raw_count = process_raw_files(ctx.raw_files, output_dir, minify, verbose)
      ctx.stats.raw_files_processed = raw_count

      # Process co-located assets (images, etc. in page bundles)
      process_assets(ctx.all_pages, output_dir, verbose)
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

    final_html = minify_html(final_html) if minify

    output_path = File.join(output_dir, "404.html")
    Hwaro::Utils::FileSafe.mkdir_p(File.dirname(output_path))
    File.write(output_path, final_html)
    Logger.action :create, output_path if verbose
  end

  # Process raw files (JSON, XML) with minification
  private def process_raw_files(raw_files : Array(Lifecycle::RawFile), output_dir : String, minify : Bool, verbose : Bool) : Int32
    count = 0

    raw_files.each do |raw_file|
      output_path = File.join(output_dir, raw_file.relative_path)

      # Validate output path stays within output directory
      unless Utils::OutputGuard.within_output_dir?(output_path, output_dir)
        Logger.warn "Skipping raw file outside output directory: #{raw_file.relative_path}"
        next
      end

      # Get appropriate processor
      processor = Content::Processors::Registry.for_file(raw_file.source_path).first?

      Hwaro::Utils::FileSafe.mkdir_p(File.dirname(output_path))

      if processor && minify
        content = File.read(raw_file.source_path)
        context = Content::Processors::ProcessorContext.new(
          file_path: raw_file.source_path,
          output_path: output_path
        )
        result = processor.process(content, context)
        if result.success
          File.write(output_path, result.content)
        else
          Logger.warn "Failed to process #{raw_file.relative_path}: #{result.error}"
          FileUtils.cp(raw_file.source_path, output_path)
        end
      else
        # Copy as-is (binary-safe) when not minifying or no processor exists.
        FileUtils.cp(raw_file.source_path, output_path)
      end

      Logger.action :create, output_path if verbose
      count += 1
    end

    count
  end

  # Process co-located assets for pages
  private def process_assets(pages : Array(Models::Page), output_dir : String, verbose : Bool)
    pages.each do |page|
      next if page.assets.empty?

      # Page bundle directory relative to content/
      page_bundle_dir = File.dirname(page.path)

      # Destination directory matches the page's URL structure
      # page.url typically starts with / and ends with /, e.g., /blog/post/
      url_path = page.url.lchop("/")
      dest_dir = File.join(output_dir, url_path)

      Hwaro::Utils::FileSafe.mkdir_p(dest_dir)

      page.assets.each do |asset_path|
        # asset_path is relative to content/ (e.g. "blog/post/image.jpg")
        source_path = File.join("content", asset_path)

        # Calculate relative path inside the bundle (e.g. "image.jpg")
        relative_to_bundle = Path[asset_path].relative_to(page_bundle_dir)
        dest_path = File.join(dest_dir, relative_to_bundle.to_s)

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
            next
          end
        end

        Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(source_path, dest_path)
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

  private def write_output(page : Models::Page, output_dir : String, content : String, verbose : Bool)
    output_path = get_output_path(page, output_dir)

    ensure_dir(Path[output_path].dirname.to_s)
    File.write(output_path, content)
    Logger.action :create, output_path if verbose
  end

  # Create directory only if not already created during this build.
  # Avoids redundant mkdir_p syscalls (stat+mkdir) for large sites.
  # Mutex protects the Set during parallel rendering; mkdir_p is
  # itself idempotent, so the worst case without it is duplicate syscalls.
  private def ensure_dir(dir : String)
    needs_create = @created_dirs_mutex.synchronize do
      if @created_dirs.includes?(dir)
        false
      else
        @created_dirs << dir
        true
      end
    end
    Hwaro::Utils::FileSafe.mkdir_p(dir) if needs_create
  end
end
