# Phase: Write — 404 page, raw files, assets
#
# Handles writing output files that are not part of the main page
# rendering pipeline: the 404 page, raw files (JSON, XML), and
# co-located page bundle assets.

module Hwaro::Core::Build::Phases::Write
  private def execute_write_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Write")
    result = @lifecycle.run_phase(Lifecycle::Phase::Write, ctx) do
      site = @site || raise "Site not initialized"
      templates = @templates || raise "Templates not loaded"
      output_dir = ctx.options.output_dir
      minify = ctx.options.minify
      verbose = ctx.options.verbose

      generate_404_page(site, templates, output_dir, minify, verbose)

      # Process raw files (JSON, XML)
      raw_count = process_raw_files(ctx.raw_files, output_dir, minify, verbose)
      ctx.stats.raw_files_processed = raw_count

      # Process co-located assets (images, etc. in page bundles)
      process_assets(ctx.all_pages, output_dir, verbose)
    end
    profiler.end_phase
    result
  end

  private def generate_404_page(site : Models::Site, templates : Hash(String, String), output_dir : String, minify : Bool, verbose : Bool)
    return unless templates.has_key?("404")

    template = templates["404"]
    page = Models::Page.new("404.html")
    page.title = "404 Not Found"

    content = ""
    section_list = ""
    toc = ""

    final_html = apply_template(template, content, page, site, section_list, toc, templates)

    final_html = minify_html(final_html) if minify

    output_path = File.join(output_dir, "404.html")
    FileUtils.mkdir_p(File.dirname(output_path))
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

      FileUtils.mkdir_p(File.dirname(output_path))

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

      FileUtils.mkdir_p(dest_dir)

      page.assets.each do |asset_path|
        # asset_path is relative to content/ (e.g. "blog/post/image.jpg")
        source_path = File.join("content", asset_path)

        # Calculate relative path inside the bundle (e.g. "image.jpg")
        relative_to_bundle = Path[asset_path].relative_to(page_bundle_dir)
        dest_path = File.join(dest_dir, relative_to_bundle.to_s)

        next unless File.exists?(source_path)

        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(source_path, dest_path)
        Logger.action :copy, dest_path, :blue if verbose
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
    FileUtils.mkdir_p(dir) if needs_create
  end
end
