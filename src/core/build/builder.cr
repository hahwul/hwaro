# Main builder module for site generation
#
# This is the core build logic that orchestrates:
# - Content collection and parsing
# - Template loading and rendering (using Crinja/Jinja2 engine)
# - Parallel processing with caching
# - Output generation
#
# The Builder uses the Lifecycle system to allow extensibility
# through hooks at various phases of the build process.

require "digest/md5"
require "file_utils"
require "html"
require "set"
require "toml"
require "json"
require "crinja"
require "./cache"
require "./parallel"
require "./shortcode_processor"
require "../../content/seo/feeds"
require "../../content/seo/sitemap"
require "../../content/seo/robots"
require "../../content/seo/llms"
require "../../content/seo/tags"
require "../../content/seo/jsonld"
require "../../content/search"
require "../../content/pagination/paginator"
require "../../content/pagination/renderer"
require "../../utils/logger"
require "../../utils/profiler"
require "../../utils/text_utils"
require "../../config/options/build_options"
require "../../content/processors/markdown"
require "../../content/processors/content_files"
require "../../content/processors/template"
require "../../content/multilingual"
require "../../content/i18n"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../models/toc"
require "../../models/site"
require "../lifecycle"
require "../../utils/debug_printer"
require "../../utils/path_utils"
require "../../utils/crinja_utils"

module Hwaro
  module Core
    module Build
      class Builder
        include ShortcodeProcessor

        TEMPLATE_EXTENSION_REGEX = /\.(html|j2|jinja2|jinja|ecr)$/

        @site : Models::Site?
        @templates : Hash(String, String)?
        @cache : Cache?
        @config : Models::Config?
        @lifecycle : Lifecycle::Manager
        @context : Lifecycle::BuildContext?
        @profiler : Profiler?
        @crinja_env : Crinja?
        @compiled_templates_cache : Hash(UInt64, Crinja::Template) = {} of UInt64 => Crinja::Template
        @pages_by_path : Hash(String, Models::Page)?
        @i18n_translations : Content::I18n::TranslationData = Content::I18n::TranslationData.new
        # Per-section cache of Crinja::Value arrays, keyed by "section_name:language"
        @section_pages_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
        # Per-section cache of Crinja::Value arrays for section assets, keyed by section name
        @section_assets_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)

        # Regex constants for HTML minification
        private REGEX_PRE_OPEN    = /<pre([^>]*)>\s*<code/
        private REGEX_PRE_CLOSE   = /<\/code>\s*<\/pre>/
        private REGEX_COMMENTS    = /<!--(?!\[if|\s*more\s*-->).*?-->/m
        private REGEX_BLANK_LINES = /\n{3,}/

        def initialize
          @lifecycle = Lifecycle::Manager.new
        end

        # Access lifecycle for external hook registration
        def lifecycle : Lifecycle::Manager
          @lifecycle
        end

        # Register a Hookable module
        def register(hookable : Lifecycle::Hookable)
          @lifecycle.register(hookable)
          self
        end

        def run(options : Config::Options::BuildOptions)
          run(
            output_dir: options.output_dir,
            base_url: options.base_url,
            drafts: options.drafts,
            minify: options.minify,
            parallel: options.parallel,
            cache: options.cache,
            highlight: options.highlight,
            verbose: options.verbose,
            profile: options.profile,
            debug: options.debug,
            error_overlay: options.error_overlay,
            stream: options.stream,
            memory_limit: options.memory_limit,
          )
        end

        # Incremental build: only re-parse and re-render pages whose source
        # files have been modified.  Falls back to a full build when the
        # necessary state from a previous build is not available.
        def run_incremental(changed_content_files : Array(String), options : Config::Options::BuildOptions)
          config = @config
          site = @site
          templates = @templates

          # First build hasn't happened yet – fall back to full build
          unless config && site && templates
            return run(options)
          end

          Logger.info "Incremental build for #{changed_content_files.size} changed file(s)..."
          start_time = Time.instant

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose
          safe = site.config.markdown.safe
          lazy_loading = site.config.markdown.lazy_loading
          include_drafts = options.drafts

          # --- 1. Identify the Page objects that correspond to changed files ---
          changed_pages = [] of Models::Page
          affected_sections = Set(String).new

          # Build O(1) lookup map for changed file matching
          pages_map = @pages_by_path || build_pages_by_path(site)

          changed_content_files.each do |file|
            relative_path = begin
              Path[file].relative_to("content").to_s
            rescue
              file.sub(/^content\//, "")
            end

            page = pages_map[relative_path]?

            next unless page

            # Re-read, re-parse front-matter and recalculate URL
            parse_single_page(page)
            page.generate_permalink(config.base_url)

            changed_pages << page
            affected_sections << page.section
            # Also include ancestor sections that may list this page
            page.ancestors.each { |ancestor| affected_sections << ancestor.section }
          end

          if changed_pages.empty?
            Logger.info "  No matching pages found – skipping."
            return
          end

          # Filter out drafts if not including them
          unless include_drafts
            changed_pages.reject! { |p| p.draft }
          end

          # --- 2. Rebuild relationships that depend on the changed pages ---
          # Re-populate taxonomies (a changed page may have new/removed tags)
          all_pages = (site.pages + site.sections).as(Array(Models::Page))
          rebuild_taxonomies(site, all_pages)

          # Rebuild lookup index (page data may have changed)
          site.build_lookup_index

          # --- 3. Determine the full set of pages that need re-rendering ---
          pages_to_render = Set(Models::Page).new(changed_pages)

          # Section index pages whose content lists include the changed pages
          affected_sections.each do |section_name|
            section = site.sections_by_name[section_name]?
            pages_to_render << section if section
          end

          # Previous / next pages whose navigation links reference changed pages
          changed_pages.each do |page|
            pages_to_render << page.lower.not_nil! if page.lower
            pages_to_render << page.higher.not_nil! if page.higher
          end

          render_list = pages_to_render.to_a

          # --- 4. Re-render the affected pages ---
          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          error_overlay = options.error_overlay
          render_list.each do |page|
            next unless page.render
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars, error_overlay: error_overlay)
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.update(source_path, output_path)
          end

          cache.save if options.cache

          # --- 5. Regenerate lightweight SEO / search files in parallel ---
          seo_tasks = [
            -> { Content::Seo::Sitemap.generate(all_pages, site, output_dir, verbose); nil },
            -> { Content::Seo::Feeds.generate(all_pages, site.config, output_dir, verbose); nil },
            -> { Content::Seo::Robots.generate(site.config, output_dir, verbose); nil },
            -> { Content::Seo::Llms.generate(site.config, all_pages, output_dir, verbose); nil },
            -> { Content::Search.generate(all_pages, site.config, output_dir, verbose); nil },
          ] of Proc(Nil)
          ParallelHelper.execute(seo_tasks, options.parallel)

          elapsed = Time.instant - start_time
          Logger.success "Incremental build complete! Rendered #{render_list.size}/#{all_pages.size} pages in #{elapsed.total_milliseconds.round(2)}ms."
        end

        # Re-render all pages using reloaded templates without re-parsing
        # content.  Useful when only template files have been modified.
        def run_rerender(options : Config::Options::BuildOptions)
          config = @config
          site = @site

          unless config && site
            return run(options)
          end

          Logger.info "Template change detected. Re-rendering all pages..."
          start_time = Time.instant

          # Reload templates from disk & reset compiled template cache
          @templates = nil
          @compiled_templates_cache.clear
          @section_pages_crinja_cache.clear
          @section_assets_crinja_cache.clear
          templates = load_templates
          @templates = templates

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose

          all_pages = (site.pages + site.sections).as(Array(Models::Page))
          renderable_pages = all_pages.select(&.render)

          global_vars = build_global_vars(site, options.cache_busting)
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          error_overlay = options.error_overlay
          count = if options.parallel && renderable_pages.size > 1
                    process_files_parallel(renderable_pages, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay)
                  else
                    process_files_sequential(renderable_pages, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay)
                  end

          # Re-generate 404 page with new template
          generate_404_page(site, templates, output_dir, minify, verbose)

          # Re-generate taxonomy pages with new templates
          Content::Taxonomies.generate(site, output_dir, templates, verbose)

          cache.save if options.cache

          elapsed = Time.instant - start_time
          Logger.success "Re-render complete! Rendered #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
        end

        # Copy only the specified static files to the output directory.
        # Used by serve mode when only static files have changed.
        def copy_changed_static(changed_files : Array(String), output_dir : String, verbose : Bool = false)
          copied = 0
          changed_files.each do |src_path|
            next unless File.exists?(src_path)
            next if File.directory?(src_path)

            relative = begin
              Path[src_path].relative_to("static").to_s
            rescue
              src_path.sub(/^static\//, "")
            end
            dest_path = File.join(output_dir, relative)

            FileUtils.mkdir_p(File.dirname(dest_path))
            FileUtils.cp(src_path, dest_path)
            copied += 1
          end
          Logger.success "Copied #{copied} static file(s)." if copied > 0
        end

        def run(
          output_dir : String = "public",
          base_url : String? = nil,
          drafts : Bool = false,
          minify : Bool = false,
          parallel : Bool = true,
          cache : Bool = false,
          highlight : Bool = true,
          verbose : Bool = false,
          profile : Bool = false,
          debug : Bool = false,
          error_overlay : Bool = false,
          stream : Bool = false,
          memory_limit : String? = nil,
        )
          # Load config once and reuse throughout the build
          config = Models::Config.load
          @config = config
          pre_hooks = config.build.hooks.pre
          post_hooks = config.build.hooks.post

          # Run pre-build hooks
          unless pre_hooks.empty?
            unless Utils::CommandRunner.run_pre_hooks(pre_hooks)
              Logger.error "Build aborted due to pre-build hook failure."
              return
            end
          end

          Logger.info "Building site..."
          start_time = Time.instant

          # Initialize profiler
          @profiler = Profiler.new(enabled: profile)
          profiler = @profiler.not_nil!
          profiler.start

          # Create build context for lifecycle
          options = Config::Options::BuildOptions.new(
            output_dir: output_dir,
            base_url: base_url,
            drafts: drafts,
            minify: minify,
            parallel: parallel,
            cache: cache,
            highlight: highlight,
            verbose: verbose,
            profile: profile,
            debug: debug,
            error_overlay: error_overlay,
            stream: stream,
            memory_limit: memory_limit,
          )
          if options.streaming?
            Logger.info "  Streaming mode enabled (batch size: #{options.batch_size})"
          end

          ctx = Lifecycle::BuildContext.new(options)
          ctx.stats.start_time = Time.instant
          @context = ctx

          # Reset internal caches (preserve @config loaded above)
          @site = nil
          @templates = nil
          @compiled_templates_cache.clear
          @section_pages_crinja_cache.clear
          @section_assets_crinja_cache.clear

          # Execute build phases through lifecycle
          result = execute_phases(ctx, profiler)

          ctx.stats.end_time = Time.instant

          if result == Lifecycle::HookResult::Abort
            Logger.error "Build failed!"
            return
          end

          elapsed = Time.instant - start_time
          raw_msg = ctx.stats.raw_files_processed > 0 ? " + #{ctx.stats.raw_files_processed} raw files" : ""
          Logger.success "Build complete! Generated #{ctx.stats.pages_rendered} pages#{raw_msg} in #{elapsed.total_milliseconds.round(2)}ms."

          # Print profiling report if enabled
          profiler.report
          profiler.template_report

          # Run post-build hooks
          unless post_hooks.empty?
            unless Utils::CommandRunner.run_post_hooks(post_hooks)
              Logger.warn "Post-build hooks failed, but build was successful."
            end
          end

          if options.debug
            Utils::DebugPrinter.print(@site.not_nil!)
          end
        end

        # Execute all build phases with lifecycle hooks
        private def execute_phases(
          ctx : Lifecycle::BuildContext,
          profiler : Profiler,
        ) : Lifecycle::HookResult
          # Phase: Initialize
          result = execute_initialize_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ReadContent
          result = execute_read_content_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ParseContent
          result = execute_parse_content_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Transform
          result = execute_transform_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Render
          result = execute_render_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Generate
          result = execute_generate_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          if ctx.options.streaming?
            ctx.all_pages.each { |page| page.raw_content = "" }
            GC.collect
          end

          # Phase: Write
          result = execute_write_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Finalize
          result = execute_finalize_phase(ctx, profiler)
        end

        private def execute_initialize_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("Initialize")
          result = @lifecycle.run_phase(Lifecycle::Phase::Initialize, ctx) do
            output_dir = ctx.options.output_dir
            verbose = ctx.options.verbose
            cache_enabled = ctx.options.cache

            @cache = Cache.new(enabled: cache_enabled)
            ctx.cache = @cache

            if cache_enabled
              stats = @cache.not_nil!.stats
              Logger.info "  Cache enabled (#{stats[:valid]} valid entries)"
            end

            setup_output_dir(output_dir, cache_enabled)
            copy_static_files(output_dir, verbose, cache_enabled)

            config = @config.not_nil!
            if url = ctx.options.base_url
              override = url.strip
              config.base_url = override unless override.empty?
            end
            @site = Models::Site.new(config)
            load_data_files(@site.not_nil!)

            # Load i18n translations
            i18n_dir = File.join("i18n")
            @i18n_translations = Content::I18n.load_translations(i18n_dir, config)

            @config = config
            ctx.site = @site
            ctx.config = config

            ctx.templates = load_templates
            @templates = ctx.templates
          end
          profiler.end_phase
          result
        end

        private def execute_read_content_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("ReadContent")
          result = @lifecycle.run_phase(Lifecycle::Phase::ReadContent, ctx) do
            collect_content_paths(ctx, ctx.options.drafts)
            Logger.info "  Found #{ctx.all_pages.size} pages."
          end
          profiler.end_phase
          result
        end

        private def execute_parse_content_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("ParseContent")
          result = @lifecycle.run_phase(Lifecycle::Phase::ParseContent, ctx) do
            # Default parsing if no hooks registered
            unless @lifecycle.has_hooks?(Lifecycle::HookPoint::AfterReadContent)
              parse_content_default(ctx)
            end
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          # Link multilingual translations between pages/sections (for language switchers)
          if config = ctx.config
            Content::Multilingual.link_translations!(ctx.all_pages, config)
          end

          # Link lower/higher page navigation and build ancestors
          link_page_navigation(ctx)
          build_subsections(ctx)
          collect_assets(ctx)
          populate_taxonomies(ctx)

          Lifecycle::HookResult::Continue
        end

        private def execute_transform_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("Transform")
          result = @lifecycle.run_phase(Lifecycle::Phase::Transform, ctx) do
            # Hooks handle transformation (Markdown → HTML)
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          site = @site.not_nil!
          # Populate site with pages and sections from context
          site.pages = ctx.pages
          site.sections = ctx.sections

          aggregate_site_authors(site)

          # Build optimized lookup indices
          site.build_lookup_index

          Lifecycle::HookResult::Continue
        end

        private def execute_render_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          site = @site.not_nil!
          templates = @templates.not_nil!
          build_cache = @cache.not_nil!
          output_dir = ctx.options.output_dir
          cache_enabled = ctx.options.cache
          parallel = ctx.options.parallel
          minify = ctx.options.minify
          highlight = ctx.options.highlight
          verbose = ctx.options.verbose

          all_pages = ctx.all_pages

          # Filter pages for caching
          pages_to_build = if cache_enabled
                             filter_changed_pages(all_pages, output_dir, build_cache)
                           else
                             all_pages
                           end

          if cache_enabled && pages_to_build.size < all_pages.size
            ctx.stats.cache_hits = all_pages.size - pages_to_build.size
            Logger.info "  Skipping #{ctx.stats.cache_hits} unchanged pages."
          end

          # Determine if syntax highlighting should be used
          # Config setting takes precedence, but can be overridden by CLI flag
          use_highlight = highlight && (site.config.highlight.enabled)

          error_overlay = ctx.options.error_overlay

          profiler.start_phase("Render")
          result = @lifecycle.run_phase(Lifecycle::Phase::Render, ctx) do
            global_vars = build_global_vars(site, ctx.options.cache_busting)
            @pages_by_path = build_pages_by_path(site)
            count = if ctx.options.streaming?
                      render_streaming(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay, parallel, ctx.options.batch_size)
                    elsif parallel && pages_to_build.size > 1
                      process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
                    else
                      process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
                    end
            ctx.stats.pages_rendered = count
          end
          profiler.end_phase
          result
        end

        private def render_streaming(
          pages : Array(Models::Page),
          site : Models::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          build_cache : Cache,
          use_highlight : Bool,
          verbose : Bool,
          global_vars : Hash(String, Crinja::Value),
          error_overlay : Bool,
          parallel : Bool,
          batch_size : Int32,
        ) : Int32
          total_count = 0
          batch_num = 0

          pages.each_slice(batch_size) do |batch|
            batch_num += 1
            Logger.debug "  Streaming batch #{batch_num} (#{batch.size} pages)"

            count = if parallel && batch.size > 1
                      process_files_parallel(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
                    else
                      process_files_sequential(batch, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars, error_overlay: error_overlay, profiler: @profiler)
                    end
            total_count += count

            # Release rendered HTML and per-section caches to free memory
            batch.each { |page| page.content = "" }
            @section_pages_crinja_cache.clear
            @section_assets_crinja_cache.clear
            GC.collect
          end

          total_count
        end

        private def execute_generate_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("Generate")
          result = @lifecycle.run_phase(Lifecycle::Phase::Generate, ctx) do
            # Default generation if no SEO hooks registered
            unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeGenerate)
              site = @site.not_nil!
              output_dir = ctx.options.output_dir
              all_pages = ctx.all_pages

              # Run independent SEO/search generators in parallel
              tasks = [
                -> { Content::Seo::Sitemap.generate(all_pages, site, output_dir); nil },
                -> { Content::Seo::Feeds.generate(all_pages, site.config, output_dir); nil },
                -> { Content::Seo::Robots.generate(site.config, output_dir); nil },
                -> { Content::Seo::Llms.generate(site.config, all_pages, output_dir); nil },
                -> { Content::Search.generate(all_pages, site.config, output_dir); nil },
              ] of Proc(Nil)
              ParallelHelper.execute(tasks, ctx.options.parallel)
            end
          end
          profiler.end_phase
          result
        end

        private def execute_write_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("Write")
          result = @lifecycle.run_phase(Lifecycle::Phase::Write, ctx) do
            site = @site.not_nil!
            templates = @templates.not_nil!
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

        private def execute_finalize_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
          profiler.start_phase("Finalize")
          result = @lifecycle.run_phase(Lifecycle::Phase::Finalize, ctx) do
            build_cache = @cache.not_nil!
            build_cache.save if ctx.options.cache
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
            next if File.directory?(file_path)
            relative_path = Path[file_path].relative_to("content").to_s
            ext = Path[file_path].extension.downcase

            if ext == ".md"
              # Process markdown file
              basename = Path[relative_path].basename
              language = extract_language_from_filename(basename, config)

              clean_basename = if language
                                 basename.sub(/\.#{language}\.md$/, ".md")
                               else
                                 basename
                               end

              is_section_index = clean_basename == "_index.md"
              is_index = clean_basename == "index.md" || is_section_index

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

        # Load data files from data/ directory
        private def load_data_files(site : Models::Site)
          site.data.clear

          return unless Dir.exists?("data")

          Dir.glob("data/**/*.{yml,yaml,json,toml}") do |path|
            next if File.directory?(path)

            relative_path = Path[path].relative_to("data")
            key = relative_path.stem
            ext = relative_path.extension.downcase

            content = File.read(path)

            begin
              value = case ext
                      when ".yml", ".yaml"
                        if parsed = YAML.parse(content)
                          Utils::CrinjaUtils.from_yaml(parsed)
                        else
                          Crinja::Value.new(nil)
                        end
                      when ".json"
                        if parsed = JSON.parse(content)
                          Utils::CrinjaUtils.from_json(parsed)
                        else
                          Crinja::Value.new(nil)
                        end
                      when ".toml"
                        if parsed = TOML.parse(content)
                          Utils::CrinjaUtils.from_toml(parsed)
                        else
                          Crinja::Value.new(nil)
                        end
                      else
                        Crinja::Value.new(nil)
                      end

              site.data[key] = value
              Logger.debug "Loaded data file: #{path} as site.data.#{key}"
            rescue ex
              Logger.warn "Failed to parse data file #{path}: #{ex.message}"
            end
          end
        end

        # Aggregate authors from pages and data
        private def aggregate_site_authors(site : Models::Site)
          site.authors.clear

          # Temporary storage to build author data
          temp_authors = {} of String => NamedTuple(
            name: String,
            pages: Array(Models::Page),
            extra: Hash(String, Crinja::Value))

          # 1. Collect authors from all pages
          site.pages.each do |page|
            page.authors.each do |author_id|
              # Normalize ID: lower case, stripped
              id = author_id.strip.downcase

              unless temp_authors.has_key?(id)
                temp_authors[id] = {
                  name:  author_id, # Default name is the ID as it appeared first
                  pages: [] of Models::Page,
                  extra: {} of String => Crinja::Value,
                }
              end
              temp_authors[id][:pages] << page
            end
          end

          # 2. Enrich with data from site.data["authors"]
          # We expect site.data["authors"] to be a Hash(String, Crinja::Value)
          # where keys match author IDs
          if authors_data = site.data["authors"]?
            temp_authors.each_key do |id|
              # Crinja::Value#[] returns generic Value
              author_info = authors_data[id]

              # Check if it has data
              next if author_info.raw.nil?

              if info_hash = author_info.raw.as?(Hash(Crinja::Value, Crinja::Value))
                info_hash.each do |k_val, v|
                  k = k_val.to_s
                  if k == "name"
                    current = temp_authors[id]
                    temp_authors[id] = {
                      name:  v.to_s,
                      pages: current[:pages],
                      extra: current[:extra],
                    }
                  else
                    temp_authors[id][:extra][k] = v
                  end
                end
              elsif info_hash = author_info.raw.as?(Hash(String, Crinja::Value))
                info_hash.each do |k, v|
                  if k == "name"
                    current = temp_authors[id]
                    temp_authors[id] = {
                      name:  v.to_s,
                      pages: current[:pages],
                      extra: current[:extra],
                    }
                  else
                    temp_authors[id][:extra][k] = v
                  end
                end
              end
            end
          end

          # 3. Convert to Crinja Values and store in site.authors
          temp_authors.each do |id, data|
            # Sort pages by date descending
            sorted_pages = Utils::SortUtils.sort_pages(data[:pages], "date", true)

            page_values = sorted_pages.map do |p|
              Crinja::Value.new({
                "title"       => Crinja::Value.new(p.title),
                "url"         => Crinja::Value.new(p.url),
                "date"        => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
                "description" => Crinja::Value.new(p.description || ""),
              })
            end

            # Construct the final author object
            author_hash = {} of String => Crinja::Value
            author_hash["key"] = Crinja::Value.new(id)
            author_hash["name"] = Crinja::Value.new(data[:name])
            author_hash["pages"] = Crinja::Value.new(page_values)

            # Merge extra data
            data[:extra].each do |k, v|
              author_hash[k] = v
            end

            site.authors[id] = Crinja::Value.new(author_hash)
          end
        end

        LANGUAGE_FILENAME_PATTERN = /^(.+)\.([a-z]{2,3})\.md$/

        # Extract language code from filename if it matches configured languages
        private def extract_language_from_filename(basename : String, config : Models::Config?) : String?
          return nil unless config
          return nil unless config.multilingual?

          # Match pattern: filename.lang.md (e.g., "about.ko.md" -> "ko", "_index.ko.md" -> "ko")
          if match = basename.match(LANGUAGE_FILENAME_PATTERN)
            lang_code = match[2]
            return lang_code if config.languages.has_key?(lang_code) || lang_code == config.default_language
          end

          nil
        end

        # Default parsing when no hooks are registered.
        # File reads and frontmatter parsing are parallelized using fibers to
        # overlap I/O waits across many files.  Each fiber operates on a
        # distinct Page object so there are no data races.
        private def parse_content_default(ctx : Lifecycle::BuildContext)
          pages = ctx.all_pages
          parallel = ctx.options.parallel && pages.size > 1

          if parallel
            parse_content_parallel(pages)
          else
            parse_content_sequential(pages)
          end

          # Filter drafts (must be sequential — mutates shared arrays)
          unless ctx.options.drafts
            ctx.pages.reject! { |p| p.draft }
            ctx.sections.reject! { |s| s.draft }
          end
        end

        # Parse a single page: read file, parse frontmatter, assign properties
        private def parse_single_page(page : Models::Page)
          source_path = File.join("content", page.path)
          return unless File.exists?(source_path)

          raw_content = File.read(source_path)
          data = Processor::Markdown.parse(raw_content, source_path)

          page.title = data[:title]
          page.description = data[:description]
          page.image = data[:image]
          page.raw_content = data[:content]
          page.draft = data[:draft]
          page.template = data[:template]
          page.in_sitemap = data[:in_sitemap]
          page.toc = data[:toc]
          page.date = data[:date]
          page.updated = data[:updated]
          page.render = data[:render]
          page.slug = data[:slug]
          page.custom_path = data[:custom_path]
          page.aliases = data[:aliases]
          page.tags = data[:tags]
          page.taxonomies = data[:taxonomies]
          page.front_matter_keys = data[:front_matter_keys]
          page.taxonomy_name = nil
          page.taxonomy_term = nil

          # New fields assignment
          page.authors = data[:authors]
          page.extra = data[:extra]
          page.in_search_index = data[:in_search_index]
          page.insert_anchor_links = data[:insert_anchor_links]
          page.weight = data[:weight]

          # Redirect support — applies to both regular pages and sections
          page.redirect_to = data[:redirect_to]

          # Calculate word count and reading time
          page.calculate_word_count
          page.calculate_reading_time

          # Extract summary from <!-- more --> marker
          page.extract_summary

          if page.is_a?(Models::Section)
            page.transparent = data[:transparent]
            page.generate_feeds = data[:generate_feeds]
            page.paginate = data[:paginate]
            page.pagination_enabled = data[:pagination_enabled]
            page.sort_by = data[:sort_by]
            page.reverse = data[:reverse]
            page.page_template = data[:page_template]
            page.paginate_path = data[:paginate_path]
          end

          # Calculate URL
          calculate_page_url(page)
        end

        private def parse_content_sequential(pages : Array(Models::Page))
          pages.each { |page| parse_single_page(page) }
        end

        # Parallel file reading + frontmatter parsing using fibers.
        # Each fiber works on a distinct Page object so mutations are safe.
        # File.read yields the fiber, allowing other fibers to proceed with
        # their I/O — this overlaps disk reads and significantly reduces
        # wall-clock time for large numbers of content files.
        private def parse_content_parallel(pages : Array(Models::Page))
          config = ParallelConfig.new(enabled: true)
          worker_count = config.calculate_workers(pages.size)

          done = Channel(Nil).new(pages.size)
          work_queue = Channel(Models::Page).new(pages.size)

          # Enqueue all pages
          pages.each { |page| work_queue.send(page) }
          work_queue.close

          # Spawn workers
          worker_count.times do
            spawn do
              while page = work_queue.receive?
                begin
                  parse_single_page(page)
                rescue ex
                  Logger.warn "  [WARN] Failed to parse #{page.path}: #{ex.message}"
                end
                done.send(nil)
              end
            end
          end

          # Wait for all pages to finish
          pages.size.times { done.receive }
        end

        # Link lower/higher page navigation for previous/next page links
        private def link_page_navigation(ctx : Lifecycle::BuildContext)
          # Group pages by section
          pages_by_section = {} of String => Array(Models::Page)

          ctx.pages.each do |page|
            next if page.is_index
            section = page.section
            pages_by_section[section] ||= [] of Models::Page
            pages_by_section[section] << page
          end

          # For each section, sort pages and link lower/higher
          pages_by_section.each do |section_name, pages|
            # Find section to get sort_by setting
            section = ctx.sections.find { |s| s.section == section_name }
            sort_by = section.try(&.sort_by) || "date"
            reverse = section.try(&.reverse) || false

            # Sort pages
            sorted = Utils::SortUtils.sort_pages(pages, sort_by, reverse)

            # Link lower (previous) and higher (next)
            sorted.each_with_index do |page, idx|
              page.lower = idx > 0 ? sorted[idx - 1] : nil
              page.higher = idx < sorted.size - 1 ? sorted[idx + 1] : nil
            end
          end
        end

        # Build subsections hierarchy
        private def build_subsections(ctx : Lifecycle::BuildContext)
          sections_by_path = {} of String => Models::Section
          ctx.sections.each { |s| sections_by_path[s.section] = s }

          ctx.sections.each do |section|
            path_parts = section.section.split("/")
            next if path_parts.size <= 1

            # Find parent section
            parent_path = path_parts[0..-2].join("/")
            if parent = sections_by_path[parent_path]?
              parent.add_subsection(section)

              # Build ancestors chain
              current_path = ""
              path_parts[0..-2].each do |part|
                current_path = current_path.empty? ? part : "#{current_path}/#{part}"
                if ancestor = sections_by_path[current_path]?
                  section.ancestors << ancestor
                end
              end
            end
          end

          # Also build ancestors for regular pages
          ctx.pages.each do |page|
            next if page.section.empty?

            path_parts = page.section.split("/")
            current_path = ""
            path_parts.each do |part|
              current_path = current_path.empty? ? part : "#{current_path}/#{part}"
              if ancestor = sections_by_path[current_path]?
                page.ancestors << ancestor
              end
            end
          end
        end

        # Collect assets for each section and page
        private def collect_assets(ctx : Lifecycle::BuildContext)
          ctx.sections.each do |section|
            section.collect_assets("content")
          end

          ctx.pages.each do |page|
            page.collect_assets("content")
          end
        end

        # Populate site.taxonomies from all pages (lifecycle context variant)
        private def populate_taxonomies(ctx : Lifecycle::BuildContext)
          rebuild_taxonomies(ctx.site.not_nil!, ctx.all_pages)
        end

        # Rebuild site.taxonomies from the given set of pages.
        # Shared by both full-build (via populate_taxonomies) and incremental build.
        private def rebuild_taxonomies(site : Models::Site, pages : Array(Models::Page))
          site.taxonomies.clear

          pages.each do |page|
            page.taxonomies.each do |name, terms|
              site.taxonomies[name] ||= {} of String => Array(Models::Page)
              terms.each do |term|
                site.taxonomies[name][term] ||= [] of Models::Page
                site.taxonomies[name][term] << page
              end
            end
          end

          # Sort pages in taxonomies in-place (default by date)
          site.taxonomies.each_value do |terms|
            terms.each_key do |term|
              terms[term] = Utils::SortUtils.sort_pages(terms[term], "date", false)
            end
          end
        end

        private def calculate_page_url(page : Models::Page)
          relative_path = page.path

          # Apply permalinks mapping
          directory_path = Path[relative_path].dirname.to_s
          effective_dir = directory_path

          if @config
            @config.not_nil!.permalinks.each do |source, target|
              if directory_path == source
                effective_dir = target
                break
              elsif directory_path.starts_with?("#{source}/")
                effective_dir = directory_path.sub(/^#{Regex.escape(source)}\//, "#{target}/")
                break
              end
            end
          end

          # For multilingual sites, include language prefix for non-default languages
          lang_prefix = if page.language && @config && page.language != @config.not_nil!.default_language
                          "/#{page.language}"
                        else
                          ""
                        end

          if page.custom_path
            custom = page.custom_path.not_nil!.sub(/^\//, "")
            page.url = "#{lang_prefix}/#{custom}"
            page.url += "/" unless page.url.ends_with?("/")
          elsif page.is_index
            if effective_dir == "." || effective_dir.empty?
              page.url = lang_prefix.empty? ? "/" : "#{lang_prefix}/"
            else
              page.url = "#{lang_prefix}/#{effective_dir}/"
            end
          else
            stem = Path[relative_path].stem

            # Remove language suffix from stem (e.g., "hello-world.ko" -> "hello-world")
            clean_stem = if page.language
                           stem.chomp(".#{page.language}")
                         else
                           stem
                         end

            leaf = page.slug || clean_stem

            if effective_dir == "." || effective_dir.empty?
              page.url = "#{lang_prefix}/#{leaf}/"
            else
              page.url = "#{lang_prefix}/#{effective_dir}/#{leaf}/"
            end
          end
        end

        private def filter_changed_pages(pages : Array(Models::Page), output_dir : String, cache : Cache) : Array(Models::Page)
          pages.select do |page|
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.changed?(source_path, output_path)
          end
        end

        private def get_output_path(page : Models::Page, output_dir : String) : String
          url_path = Utils::PathUtils.sanitize_path(page.url.sub(/^\//, ""))
          output_path = File.join(output_dir, url_path, "index.html")

          # Ensure output path is within output directory
          canonical_output = File.expand_path(output_path)
          canonical_output_dir = File.expand_path(output_dir)
          unless canonical_output.starts_with?(canonical_output_dir)
            Logger.warn "  [WARN] Skipping output outside output directory: #{output_path}"
            return File.join(output_dir, "index.html")
          end

          output_path
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
                    Logger.error "Copy failed: #{ex}"
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
          return @templates.not_nil! if @templates

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
              name = relative.to_s.gsub(TEMPLATE_EXTENSION_REGEX, "")
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

        private def process_files_parallel(
          pages : Array(Models::Page),
          site : Models::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          cache : Cache,
          highlight : Bool,
          verbose : Bool,
          global_vars : Hash(String, Crinja::Value),
          error_overlay : Bool = false,
          profiler : Profiler? = nil,
        ) : Int32
          return 0 if pages.empty?

          config = ParallelConfig.new(enabled: true)
          worker_count = config.calculate_workers(pages.size)
          safe = site.config.markdown.safe

          # Pre-create per-worker Crinja environments and template caches
          # to avoid shared mutable state between concurrent fibers.
          worker_envs = Array.new(worker_count) { create_fresh_crinja_env }
          worker_caches = Array.new(worker_count) { {} of UInt64 => Crinja::Template }

          results = Channel(Bool).new(pages.size)
          work_queue = Channel({Models::Page, Int32}).new(pages.size)

          # Enqueue all work items
          pages.each_with_index { |page, idx| work_queue.send({page, idx}) }
          work_queue.close

          # Spawn workers, each with its own Crinja env and template cache
          worker_count.times do |worker_id|
            env = worker_envs[worker_id]
            tmpl_cache = worker_caches[worker_id]
            spawn do
              while work_item = work_queue.receive?
                page, _idx = work_item
                begin
                  page_start = profiler ? Time.instant : nil
                  render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars,
                    crinja_env_override: env, template_cache_override: tmpl_cache, error_overlay: error_overlay)
                  if profiler && page_start
                    elapsed_ms = (Time.instant - page_start).total_milliseconds
                    template_name = determine_template(page, templates)
                    profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
                  end
                  source_path = File.join("content", page.path)
                  output_path = get_output_path(page, output_dir)
                  cache.update(source_path, output_path)
                  results.send(true)
                rescue ex
                  Logger.debug "Parallel render failed for #{page.path}: #{ex.message}"
                  results.send(false)
                end
              end
            end
          end

          # Collect results
          count = 0
          pages.size.times do
            count += 1 if results.receive
          end
          count
        end

        private def process_files_sequential(
          pages : Array(Models::Page),
          site : Models::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          cache : Cache,
          highlight : Bool,
          verbose : Bool,
          global_vars : Hash(String, Crinja::Value),
          error_overlay : Bool = false,
          profiler : Profiler? = nil,
        ) : Int32
          count = 0
          safe = site.config.markdown.safe
          pages.each do |page|
            page_start = profiler ? Time.instant : nil
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars, error_overlay: error_overlay)
            if profiler && page_start
              elapsed_ms = (Time.instant - page_start).total_milliseconds
              template_name = determine_template(page, templates)
              profiler.record_template(template_name, page.content.bytesize.to_i64, elapsed_ms)
            end
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.update(source_path, output_path)
            count += 1
          end
          count
        end

        private def render_page(
          page : Models::Page,
          site : Models::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          highlight : Bool = true,
          safe : Bool = false,
          verbose : Bool = false,
          global_vars : Hash(String, Crinja::Value)? = nil,
          crinja_env_override : Crinja? = nil,
          template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
          error_overlay : Bool = false,
        )
          return unless page.render

          # Clear warnings from previous renders (important for incremental rebuilds)
          page.build_warnings.clear

          # Handle redirect_to for pages AND sections
          if page.has_redirect?
            generate_redirect_page(page, output_dir, verbose)
            generate_aliases(page, output_dir, verbose)
            return
          end

          # Only build shortcode context and process shortcodes if content actually
          # contains shortcode syntax ({{ or {%).  This avoids the expensive
          # build_template_variables call for the majority of pages that have no
          # shortcodes.
          shortcode_results = {} of String => String
          raw = page.raw_content
          has_shortcodes = raw.includes?("{{") || raw.includes?("{%")
          shortcode_context : Hash(String, Crinja::Value)? = nil

          processed_content = if has_shortcodes
                                shortcode_context = build_template_variables(page, site, "", "", "", "", nil, nil, global_vars)
                                process_shortcodes_jinja(raw, templates, shortcode_context, shortcode_results,
                                  crinja_env_override: crinja_env_override)
                              else
                                raw
                              end

          lazy_loading = site.config.markdown.lazy_loading
          emoji = site.config.markdown.emoji

          # Use anchor links if enabled
          md_config = site.config.markdown
          html_content, toc_headers = if page.insert_anchor_links
                                        Content::Processors::Markdown.new.render_with_anchors(processed_content, highlight, safe, "after", lazy_loading, emoji, markdown_config: md_config)
                                      else
                                        Processor::Markdown.render(processed_content, highlight, safe, lazy_loading, emoji, markdown_config: md_config)
                                      end

          # Replace shortcode placeholders with their rendered HTML content
          html_content = replace_shortcode_placeholders(html_content, shortcode_results)

          # Resolve internal @/ links to actual page URLs
          if pages_by_path = @pages_by_path
            html_content = Content::Processors::InternalLinkResolver.resolve(html_content, pages_by_path, page.path)
          end

          # Store rendered HTML in page.content for reuse by Feed/Search generators
          # (avoids expensive re-rendering of Markdown in Generate phase)
          page.content = html_content

          toc_html = if page.toc && !toc_headers.empty?
                       generate_toc_html(toc_headers)
                     else
                       ""
                     end

          template_name = determine_template(page, templates)
          template_content = templates[template_name]? || templates["page"]?
          Logger.debug "Rendering #{page.path} (section=#{page.section.empty? ? "<root>" : page.section}, index=#{page.is_index}) using template '#{template_name}'" if verbose

          # Handle section pages with pagination
          if (template_name == "section" || page.template == "section") && page.is_a?(Models::Section)
            render_section_with_pagination(page.as(Models::Section), site, templates, template_content, output_dir, minify, html_content, toc_html, verbose, global_vars,
              crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, error_overlay: error_overlay)
          else
            section_list_html = ""

            final_html = if template_content
                           apply_template(template_content, html_content, page, site, section_list_html, toc_html, templates, global_vars: global_vars,
                             crinja_env_override: crinja_env_override, template_cache_override: template_cache_override,
                             prebuilt_vars: shortcode_context)
                         else
                           msg = "No template found for #{page.path}. Using raw content."
                           Logger.warn "  [WARN] #{msg}"
                           page.build_warnings << msg unless page.build_warnings.includes?(msg)
                           html_content
                         end

            if error_overlay && !page.build_warnings.empty?
              final_html = inject_error_overlay(final_html, page.build_warnings)
            end

            final_html = minify_html(final_html) if minify

            write_output(page, output_dir, final_html, verbose)
          end

          generate_aliases(page, output_dir, verbose)
        end

        # Generate redirect page for sections with redirect_to
        private def generate_redirect_page(
          page : Models::Page,
          output_dir : String,
          verbose : Bool = false,
        )
          redirect_url = page.redirect_to
          return unless redirect_url

          html_escaped_url = Utils::TextUtils.escape_xml(redirect_url)
          # For JavaScript context: escape backslashes, quotes, newlines, and </script>
          js_escaped_url = redirect_url
            .gsub("\\", "\\\\")
            .gsub("\"", "\\\"")
            .gsub("\n", "\\n")
            .gsub("\r", "\\r")
            .gsub("</", "<\\/")

          redirect_html = <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta http-equiv="refresh" content="0; url=#{html_escaped_url}">
            <link rel="canonical" href="#{html_escaped_url}">
            <title>Redirecting...</title>
          </head>
          <body>
            <p>Redirecting to <a href="#{html_escaped_url}">#{html_escaped_url}</a>...</p>
            <script>window.location.href = "#{js_escaped_url}";</script>
          </body>
          </html>
          HTML

          output_path = File.join(output_dir, page.url.sub(/^\//, ""), "index.html")
          FileUtils.mkdir_p(Path[output_path].dirname)
          File.write(output_path, redirect_html)
          Logger.action :create, output_path if verbose
        end

        private def render_section_with_pagination(
          section : Models::Section,
          site : Models::Site,
          templates : Hash(String, String),
          template_content : String?,
          output_dir : String,
          minify : Bool,
          html_content : String,
          toc_html : String,
          verbose : Bool = false,
          global_vars : Hash(String, Crinja::Value)? = nil,
          crinja_env_override : Crinja? = nil,
          template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
          error_overlay : Bool = false,
        )
          # Get pages in this section using the site utility method
          # Note: sorting is handled by Paginator.paginate (uses section.sort_by setting)
          section_name = Path[section.path].dirname
          section_name = "" if section_name == "."
          section_pages = site.pages_for_section(section_name, section.language)

          # Create paginator and render
          paginator = Content::Pagination::Paginator.new(site.config)
          pagination_result = paginator.paginate(section, section_pages)
          renderer = Content::Pagination::Renderer.new(site.config)

          pagination_result.paginated_pages.each do |paginated_page|
            section_list_html = renderer.render_section_list(paginated_page)
            pagination_nav_html = renderer.render_pagination_nav(paginated_page)
            pagination_seo_links = renderer.render_seo_links(paginated_page)

            # Use the correct URL for each paginated page during rendering (important for SEO tags, nav, etc.)
            base = section.url.rstrip("/")
            current_url = if paginated_page.page_number == 1
                            "#{base}/"
                          else
                            "#{base}/#{section.paginate_path}/#{paginated_page.page_number}/"
                          end

            final_html = if template_content
                           apply_template(template_content, html_content, section, site, section_list_html, toc_html, templates, pagination_nav_html, current_url, paginated_page, global_vars,
                             crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, pagination_seo_links: pagination_seo_links)
                         else
                           msg = "No template found for #{section.path}. Using raw content."
                           Logger.warn "  [WARN] #{msg}"
                           section.build_warnings << msg unless section.build_warnings.includes?(msg)
                           html_content
                         end

            if error_overlay && !section.build_warnings.empty?
              final_html = inject_error_overlay(final_html, section.build_warnings)
            end

            final_html = minify_html(final_html) if minify

            # Write output - first page uses section URL, subsequent pages use /page/N/
            if paginated_page.page_number == 1
              write_output(section, output_dir, final_html, verbose)
            else
              write_paginated_output(section, paginated_page.page_number, output_dir, final_html, verbose, section.paginate_path)
            end
          end
        end

        private def write_paginated_output(page : Models::Page, page_number : Int32, output_dir : String, content : String, verbose : Bool, paginate_path : String = "page")
          # Sanitize URL to prevent path traversal
          url_path = Utils::PathUtils.sanitize_path(page.url.sub(/^\//, "").rstrip("/"))
          output_path = File.join(output_dir, url_path, paginate_path, page_number.to_s, "index.html")

          # Ensure output path is within output directory
          canonical_output = File.expand_path(output_path)
          canonical_output_dir = File.expand_path(output_dir)
          unless canonical_output.starts_with?(canonical_output_dir)
            Logger.warn "  [WARN] Skipping output outside output directory: #{output_path}"
            return
          end

          FileUtils.mkdir_p(Path[output_path].dirname)
          File.write(output_path, content)
          Logger.action :create, output_path if verbose
        end

        private def determine_template(page : Models::Page, templates : Hash(String, String)) : String
          if custom = page.template
            return custom if templates.has_key?(custom)
            msg = "Custom template '#{custom}' not found for #{page.path}. Falling back to default."
            Logger.warn "  [WARN] #{msg}"
            page.build_warnings << msg unless page.build_warnings.includes?(msg)
          end

          if page.is_a?(Models::Section)
            return "section" if templates.has_key?("section")
          end

          if page.is_index && page.section.empty? && templates.has_key?("index")
            return "index"
          end

          "page"
        end

        private def generate_aliases(page : Models::Page, output_dir : String, verbose : Bool)
          page.aliases.each do |alias_path|
            alias_clean = Utils::PathUtils.sanitize_path(alias_path.sub(/^\//, ""))
            dest_path = File.join(output_dir, alias_clean, "index.html")

            # Ensure output path is within output directory
            canonical_dest = File.expand_path(dest_path)
            canonical_output_dir = File.expand_path(output_dir)
            unless canonical_dest.starts_with?(canonical_output_dir)
              Logger.warn "  [WARN] Skipping alias outside output directory: #{dest_path}"
              next
            end

            FileUtils.mkdir_p(File.dirname(dest_path))

            redirect_url = page.redirect_to || page.url
            escaped_url = HTML.escape(redirect_url)

            content = <<-HTML
            <!DOCTYPE html>
            <html>
            <head>
              <meta http-equiv="refresh" content="0; url=#{escaped_url}" />
              <title>Redirecting to #{escaped_url}</title>
            </head>
            <body>
              <p>Redirecting to <a href="#{escaped_url}">#{escaped_url}</a>.</p>
            </body>
            </html>
            HTML

            File.write(dest_path, content)
            Logger.action :create, dest_path, :yellow if verbose
          end
        end

        private def generate_toc_html(headers : Array(Models::TocHeader)) : String
          return "" if headers.empty?

          String.build do |str|
            str << "<ul>"
            headers.each do |header|
              str << "<li><a href=\"#{header.permalink}\">#{header.title}</a>"
              unless header.children.empty?
                str << generate_toc_html(header.children)
              end
              str << "</li>"
            end
            str << "</ul>"
          end
        end

        # Inject a dismissible error overlay into the HTML page for development feedback.
        # The overlay shows build warnings collected during rendering so developers
        # can spot template issues directly in the browser.
        private def inject_error_overlay(html : String, warnings : Array(String)) : String
          return html if warnings.empty?

          escaped_warnings = warnings.map { |w| HTML.escape(w) }
          list_items = escaped_warnings.map { |w|
            "<li style=\"margin-bottom:8px;line-height:1.5;\">#{w}</li>"
          }.join("\n")

          overlay = <<-OVERLAY
          <div id="hwaro-error-overlay" style="position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:-apple-system,BlinkMacSystemFont,sans-serif;">
            <div style="background:#1e1e2e;color:#cdd6f4;border-radius:8px;padding:24px;max-width:720px;width:90%;max-height:80vh;overflow-y:auto;box-shadow:0 8px 32px rgba(0,0,0,0.4);">
              <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
                <h2 style="margin:0;color:#f38ba8;font-size:18px;">Build Warning</h2>
                <button onclick="document.getElementById('hwaro-error-overlay').remove()" style="background:none;border:none;color:#cdd6f4;font-size:24px;cursor:pointer;padding:0 4px;">&times;</button>
              </div>
              <ul style="margin:0;padding:0 0 0 20px;">
                #{list_items}
              </ul>
            </div>
          </div>
          OVERLAY

          # Inject before </body> if present, otherwise append
          if idx = html.rindex("</body>")
            html.insert(idx, overlay)
          else
            html + overlay
          end
        end

        def apply_template(
          template : String,
          content : String,
          page : Models::Page,
          site : Models::Site,
          section_list : String,
          toc : String,
          templates : Hash(String, String),
          pagination : String = "",
          page_url_override : String? = nil,
          paginator : Content::Pagination::PaginatedPage? = nil,
          global_vars : Hash(String, Crinja::Value)? = nil,
          crinja_env_override : Crinja? = nil,
          template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
          pagination_seo_links : String = "",
          prebuilt_vars : Hash(String, Crinja::Value)? = nil,
        ) : String
          # Use per-worker env when provided (parallel path), otherwise shared env
          env = crinja_env_override || crinja_env
          cache = template_cache_override || @compiled_templates_cache

          # Build template variables — reuse prebuilt_vars if available (shortcode path)
          vars = if pv = prebuilt_vars
                   update_content_vars(pv, content, section_list, toc, pagination, pagination_seo_links)
                   pv
                 else
                   build_template_variables(page, site, content, section_list, toc, pagination, page_url_override, paginator, global_vars, pagination_seo_links: pagination_seo_links)
                 end

          begin
            # Process shortcodes in template first (convert to Jinja2 include syntax)
            processed_template = process_shortcodes_jinja(template, templates, vars,
              crinja_env_override: crinja_env_override)

            # Cache compiled Crinja templates by content hash.
            # Most pages share the same base template string, so this avoids
            # re-parsing the template AST on every page render.
            cache_key = processed_template.hash
            crinja_template = cache[cache_key]? || begin
              compiled = env.from_string(processed_template)
              cache[cache_key] = compiled
              compiled
            end
            crinja_template.render(vars)
          rescue ex : Crinja::TemplateNotFoundError
            msg = "Template error for #{page.path}: #{ex.message}"
            Logger.warn "  [WARN] #{msg}"
            page.build_warnings << msg unless page.build_warnings.includes?(msg)
            content
          rescue ex : Crinja::Error
            msg = "Template error for #{page.path}: #{ex.message}"
            Logger.warn "  [WARN] #{msg}"
            page.build_warnings << msg unless page.build_warnings.includes?(msg)
            content
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
          pagination : String,
          pagination_seo_links : String,
        )
          vars["content"] = Crinja::Value.new(content)
          vars["section_list"] = Crinja::Value.new(section_list)
          vars["toc"] = Crinja::Value.new(toc)
          vars["toc_obj"] = Crinja::Value.new({"html" => Crinja::Value.new(toc)})
          vars["pagination"] = Crinja::Value.new(pagination)
          vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)
        end

        # Convert a Page to a Crinja::Value hash for use in section page lists and paginator.
        # This is a shared helper to avoid duplicating the same conversion in multiple places.
        private def page_to_crinja_list_value(p : Models::Page, default_language : String) : Crinja::Value
          Crinja::Value.new({
            "title"       => Crinja::Value.new(p.title),
            "description" => Crinja::Value.new(p.description || ""),
            "url"         => Crinja::Value.new(p.url),
            "date"        => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
            "image"       => Crinja::Value.new(p.image || ""),
            "draft"       => Crinja::Value.new(p.draft),
            "toc"         => Crinja::Value.new(p.toc),
            "render"      => Crinja::Value.new(p.render),
            "is_index"    => Crinja::Value.new(p.is_index),
            "generated"   => Crinja::Value.new(p.generated),
            "in_sitemap"  => Crinja::Value.new(p.in_sitemap),
            "language"    => Crinja::Value.new(p.language || default_language),
          })
        end

        # Get (or build and cache) the sorted Crinja::Value array for a section's pages.
        # The cache stores the full sorted list; callers should filter current_page themselves if needed.
        private def cached_section_pages_crinja(
          section_name : String,
          language : String?,
          site : Models::Site,
        ) : Array(Crinja::Value)
          cache_key = "#{section_name}:#{language}"
          @section_pages_crinja_cache[cache_key]? || begin
            pages = site.pages_for_section(section_name, language)

            # Use section's sort_by setting if available, otherwise sort by title
            section = site.sections_by_name[section_name]?
            sort_by = section.try(&.sort_by) || "title"
            reverse = section.try(&.reverse) || false
            pages = Utils::SortUtils.sort_pages(pages, sort_by, reverse)

            default_lang = site.config.default_language
            arr = pages.map { |p| page_to_crinja_list_value(p, default_lang) }
            @section_pages_crinja_cache[cache_key] = arr
            arr
          end
        end

        # Build global template variables once
        # Build a lookup map from content path → Page for internal link resolution.
        private def build_pages_by_path(site : Models::Site) : Hash(String, Models::Page)
          map = {} of String => Models::Page
          site.pages.each { |p| map[p.path] ||= p }
          site.sections.each { |s| map[s.path] ||= s }
          map
        end

        private def build_global_vars(site : Models::Site, cache_busting : Bool = true) : Hash(String, Crinja::Value)
          config = site.config
          vars = {} of String => Crinja::Value

          # Hidden variables for get_page/get_section/get_taxonomy functions
          # These are prefixed with __ to indicate they're internal
          all_pages_array = [] of Crinja::Value
          pages_by_path = {} of String => Crinja::Value

          site.pages.each do |p|
            page_val = Crinja::Value.new({
              "path"         => Crinja::Value.new(p.path),
              "title"        => Crinja::Value.new(p.title),
              "description"  => Crinja::Value.new(p.description || ""),
              "url"          => Crinja::Value.new(p.url),
              "date"         => Crinja::Value.new(p.date.try(&.to_s("%Y-%m-%d")) || ""),
              "section"      => Crinja::Value.new(p.section),
              "draft"        => Crinja::Value.new(p.draft),
              "weight"       => Crinja::Value.new(p.weight),
              "summary"      => Crinja::Value.new(p.effective_summary || ""),
              "word_count"   => Crinja::Value.new(p.word_count),
              "reading_time" => Crinja::Value.new(p.reading_time),
            })
            all_pages_array << page_val

            # Build O(1) lookup map
            # Use ||= to preserve first-match behavior (consistent with linear search)
            pages_by_path[p.path] ||= page_val
            pages_by_path[p.url] ||= page_val

            # Handle URL without trailing slash for flexible matching
            if p.url.ends_with?("/") && p.url.size > 1
              pages_by_path[p.url.rstrip("/")] ||= page_val
            end
          end

          vars["__all_pages__"] = Crinja::Value.new(all_pages_array)
          vars["__pages_by_path__"] = Crinja::Value.new(pages_by_path)

          all_sections_array = [] of Crinja::Value
          sections_by_key = {} of String => Crinja::Value

          site.sections.each do |s|
            section_pages = s.pages.map do |sp|
              Crinja::Value.new({
                "title" => Crinja::Value.new(sp.title),
                "url"   => Crinja::Value.new(sp.url),
                "date"  => Crinja::Value.new(sp.date.try(&.to_s("%Y-%m-%d")) || ""),
              })
            end
            section_val = Crinja::Value.new({
              "path"        => Crinja::Value.new(s.path),
              "name"        => Crinja::Value.new(s.section),
              "title"       => Crinja::Value.new(s.title),
              "description" => Crinja::Value.new(s.description || ""),
              "url"         => Crinja::Value.new(s.url),
              "pages"       => Crinja::Value.new(section_pages),
              "pages_count" => Crinja::Value.new(s.pages.size),
              "assets"      => Crinja::Value.new(s.assets.map { |a| Crinja::Value.new(a) }),
            })
            all_sections_array << section_val

            # Build O(1) lookup map for get_section() — match by path, name, and URL
            sections_by_key[s.path] ||= section_val
            sections_by_key[s.section] ||= section_val unless s.section.empty?
            sections_by_key[s.url] ||= section_val
          end
          vars["__all_sections__"] = Crinja::Value.new(all_sections_array)
          vars["__sections_by_key__"] = Crinja::Value.new(sections_by_key)

          # Build taxonomies hash for get_taxonomy function
          taxonomies_hash = {} of String => Crinja::Value
          site.taxonomies.each do |name, terms|
            terms_array = terms.map do |term, term_pages|
              term_pages_array = term_pages.map do |tp|
                Crinja::Value.new({
                  "title" => Crinja::Value.new(tp.title),
                  "url"   => Crinja::Value.new(tp.url),
                  "date"  => Crinja::Value.new(tp.date.try(&.to_s("%Y-%m-%d")) || ""),
                })
              end
              Crinja::Value.new({
                "name"  => Crinja::Value.new(term),
                "slug"  => Crinja::Value.new(Utils::TextUtils.slugify(term)),
                "pages" => Crinja::Value.new(term_pages_array),
                "count" => Crinja::Value.new(term_pages.size),
              })
            end
            taxonomies_hash[name] = Crinja::Value.new({
              "name"  => Crinja::Value.new(name),
              "items" => Crinja::Value.new(terms_array),
            })
          end
          vars["__taxonomies__"] = Crinja::Value.new(taxonomies_hash)

          # Site object with full data
          site_obj = {
            "title"       => Crinja::Value.new(config.title),
            "description" => Crinja::Value.new(config.description || ""),
            "base_url"    => Crinja::Value.new(config.base_url),
            "pages"       => Crinja::Value.new(all_pages_array),
            "sections"    => Crinja::Value.new(all_sections_array),
            "taxonomies"  => Crinja::Value.new(taxonomies_hash),
            "data"        => Crinja::Value.new(site.data),
            "authors"     => Crinja::Value.new(site.authors),
          }
          vars["site"] = Crinja::Value.new(site_obj)

          # Site-wide constant variables — computed once, shared across all pages
          # (These were previously recomputed in build_template_variables for every page)
          vars["site_title"] = Crinja::Value.new(config.title)
          vars["site_description"] = Crinja::Value.new(config.description || "")
          vars["base_url"] = Crinja::Value.new(config.base_url)

          # Cache busting (content hash of local CSS/JS files)
          cache_bust = cache_busting ? compute_cache_bust(config) : ""

          # Highlight tags
          vars["highlight_css"] = Crinja::Value.new(config.highlight.css_tag(cache_bust))
          vars["highlight_js"] = Crinja::Value.new(config.highlight.js_tag(cache_bust))
          vars["highlight_tags"] = Crinja::Value.new(config.highlight.tags(cache_bust))

          # Auto includes
          vars["auto_includes_css"] = Crinja::Value.new(config.auto_includes.css_tags(config.base_url, cache_bust))
          vars["auto_includes_js"] = Crinja::Value.new(config.auto_includes.js_tags(config.base_url, cache_bust))
          vars["auto_includes"] = Crinja::Value.new(config.auto_includes.all_tags(config.base_url, cache_bust))

          # Time-related variables (fixed per build, not per page)
          now = Time.local
          vars["current_year"] = Crinja::Value.new(now.year)
          vars["current_date"] = Crinja::Value.new(now.to_s("%Y-%m-%d"))
          vars["current_datetime"] = Crinja::Value.new(now.to_s("%Y-%m-%d %H:%M:%S"))

          # i18n translations (available to {{ "key" | t }} filter)
          unless @i18n_translations.empty?
            i18n_hash = {} of Crinja::Value => Crinja::Value
            @i18n_translations.each do |lang, entries|
              entries_hash = {} of Crinja::Value => Crinja::Value
              entries.each do |key, value|
                entries_hash[Crinja::Value.new(key)] = Crinja::Value.new(value)
              end
              i18n_hash[Crinja::Value.new(lang)] = Crinja::Value.new(entries_hash)
            end
            vars["_i18n_translations"] = Crinja::Value.new(i18n_hash)
          end
          vars["_i18n_default_language"] = Crinja::Value.new(config.default_language)

          vars
        end

        # Compute a content-based cache bust hash from local CSS/JS files.
        # Returns an 8-character hex digest, or "" if no local files exist.
        private def compute_cache_bust(config : Models::Config) : String
          has_local_highlight = config.highlight.enabled && !config.highlight.use_cdn
          has_auto_includes = config.auto_includes.enabled && config.auto_includes.dirs.any?

          return "" unless has_local_highlight || has_auto_includes

          digest = Digest::MD5.new

          if has_local_highlight
            css_path = File.join("static", "assets", "css", "highlight", "#{config.highlight.theme}.min.css")
            digest.update(File.read(css_path)) if File.exists?(css_path)
            js_path = File.join("static", "assets", "js", "highlight.min.js")
            digest.update(File.read(js_path)) if File.exists?(js_path)
          end

          if has_auto_includes
            config.auto_includes.dirs.each do |dir|
              static_dir = File.join("static", dir)
              next unless Dir.exists?(static_dir)
              Dir.glob(File.join(static_dir, "**", "*.{css,js}")).sort.each do |file|
                digest.update(File.read(file))
              end
            end
          end

          digest.hexfinal[0, 8]
        end

        # Build template variables hash for Crinja
        private def build_template_variables(
          page : Models::Page,
          site : Models::Site,
          content : String,
          section_list : String,
          toc : String,
          pagination : String = "",
          page_url_override : String? = nil,
          paginator : Content::Pagination::PaginatedPage? = nil,
          global_vars : Hash(String, Crinja::Value)? = nil,
          pagination_seo_links : String = "",
        ) : Hash(String, Crinja::Value)
          config = site.config
          vars = {} of String => Crinja::Value

          effective_url = page_url_override || page.url

          # Precompute date strings once to avoid repeated .to_s formatting
          date_str = page.date.try(&.to_s("%Y-%m-%d")) || ""
          updated_str = page.updated.try(&.to_s("%Y-%m-%d")) || ""
          date_crinja = Crinja::Value.new(date_str)

          # Page variables (flat for convenience)
          vars["page_title"] = Crinja::Value.new(page.title)
          vars["page_description"] = Crinja::Value.new(page.description || config.description || "")
          vars["page_url"] = Crinja::Value.new(effective_url)
          vars["page_section"] = Crinja::Value.new(page.section)
          vars["page_date"] = date_crinja
          vars["page_image"] = Crinja::Value.new(page.image || config.og.default_image || "")
          vars["taxonomy_name"] = Crinja::Value.new(page.taxonomy_name || "")
          vars["taxonomy_term"] = Crinja::Value.new(page.taxonomy_term || "")
          page_language = page.language || config.default_language
          vars["page_language"] = Crinja::Value.new(page_language)

          translations = page.translations.map do |t|
            Crinja::Value.new(
              {
                "code"       => Crinja::Value.new(t.code),
                "url"        => Crinja::Value.new(t.url),
                "title"      => Crinja::Value.new(t.title),
                "is_current" => Crinja::Value.new(t.is_current),
                "is_default" => Crinja::Value.new(t.is_default),
              }
            )
          end
          vars["page_translations"] = Crinja::Value.new(translations)

          # Generate permalink only if not already set
          page.generate_permalink(config.base_url) unless page.permalink

          # Convert authors to Crinja array
          authors_array = page.authors.map { |a| Crinja::Value.new(a) }

          # Convert tags to Crinja array
          tags_array = page.tags.map { |t| Crinja::Value.new(t) }

          # Convert assets to Crinja array
          assets_array = page.assets.map { |a| Crinja::Value.new(a) }

          # Convert extra to Crinja hash
          extra_hash = {} of String => Crinja::Value
          page.extra.each do |k, v|
            extra_hash[k] = case v
                            when String
                              Crinja::Value.new(v)
                            when Bool
                              Crinja::Value.new(v)
                            when Int64
                              Crinja::Value.new(v)
                            when Float64
                              Crinja::Value.new(v)
                            when Array(String)
                              Crinja::Value.new(v.map { |s| Crinja::Value.new(s) })
                            else
                              Crinja::Value.new(v.to_s)
                            end
          end

          # Build lower/higher page objects
          lower_obj = if lower = page.lower
                        {
                          "title"       => Crinja::Value.new(lower.title),
                          "url"         => Crinja::Value.new(lower.url),
                          "description" => Crinja::Value.new(lower.description || ""),
                          "date"        => Crinja::Value.new(lower.date.try(&.to_s("%Y-%m-%d")) || ""),
                        }
                      else
                        nil
                      end

          higher_obj = if higher = page.higher
                         {
                           "title"       => Crinja::Value.new(higher.title),
                           "url"         => Crinja::Value.new(higher.url),
                           "description" => Crinja::Value.new(higher.description || ""),
                           "date"        => Crinja::Value.new(higher.date.try(&.to_s("%Y-%m-%d")) || ""),
                         }
                       else
                         nil
                       end

          # Build ancestors array
          ancestors_array = page.ancestors.map do |ancestor|
            Crinja::Value.new({
              "title" => Crinja::Value.new(ancestor.title),
              "url"   => Crinja::Value.new(ancestor.url),
            })
          end

          # Page object with all properties
          page_obj = {
            "title"        => Crinja::Value.new(page.title),
            "description"  => Crinja::Value.new(page.description || ""),
            "url"          => Crinja::Value.new(effective_url),
            "section"      => Crinja::Value.new(page.section),
            "date"         => date_crinja,
            "updated"      => Crinja::Value.new(updated_str),
            "image"        => Crinja::Value.new(page.image || ""),
            "draft"        => Crinja::Value.new(page.draft),
            "toc"          => Crinja::Value.new(page.toc),
            "render"       => Crinja::Value.new(page.render),
            "is_index"     => Crinja::Value.new(page.is_index),
            "generated"    => Crinja::Value.new(page.generated),
            "in_sitemap"   => Crinja::Value.new(page.in_sitemap),
            "language"     => Crinja::Value.new(page_language),
            "translations" => Crinja::Value.new(translations),
            # New properties
            "authors"         => Crinja::Value.new(authors_array),
            "tags"            => Crinja::Value.new(tags_array),
            "assets"          => Crinja::Value.new(assets_array),
            "extra"           => Crinja::Value.new(extra_hash),
            "summary"         => Crinja::Value.new(page.effective_summary || ""),
            "word_count"      => Crinja::Value.new(page.word_count),
            "reading_time"    => Crinja::Value.new(page.reading_time),
            "permalink"       => Crinja::Value.new(page.permalink || ""),
            "weight"          => Crinja::Value.new(page.weight),
            "in_search_index" => Crinja::Value.new(page.in_search_index),
            "lower"           => lower_obj ? Crinja::Value.new(lower_obj) : Crinja::Value.new(nil),
            "higher"          => higher_obj ? Crinja::Value.new(higher_obj) : Crinja::Value.new(nil),
            "ancestors"       => Crinja::Value.new(ancestors_array),
          }
          vars["page"] = Crinja::Value.new(page_obj)

          # Flat variables for new properties
          vars["page_summary"] = Crinja::Value.new(page.effective_summary || "")
          vars["page_word_count"] = Crinja::Value.new(page.word_count)
          vars["page_reading_time"] = Crinja::Value.new(page.reading_time)
          vars["page_permalink"] = Crinja::Value.new(page.permalink || "")
          vars["page_authors"] = Crinja::Value.new(authors_array)
          vars["page_tags"] = Crinja::Value.new(tags_array)
          vars["page_weight"] = Crinja::Value.new(page.weight)

          # Site variables (flat for convenience)
          # NOTE: site_title, site_description, base_url are now in global_vars
          # (computed once in build_global_vars). We skip them here to avoid
          # redundant Crinja::Value allocations per page.

          # Section variables
          section_title = ""
          section_description = ""
          section_pages_array = [] of Crinja::Value
          current_section = ""

          # Section-specific variables
          subsections_array = [] of Crinja::Value
          # assets_array is already defined above for the page itself
          section_assets_array = [] of Crinja::Value
          page_template_var = ""
          paginate_path_var = "page"
          redirect_to_var = ""

          if page.is_a?(Models::Section)
            # For section pages, use the page itself as the section data
            section_title = page.title
            section_description = page.description || ""
            current_section = page.section

            # Section-specific properties
            page_template_var = page.page_template || ""
            paginate_path_var = page.paginate_path
            redirect_to_var = page.redirect_to || ""

            # Build subsections array
            subsections_array = page.subsections.map do |sub|
              Crinja::Value.new({
                "title"       => Crinja::Value.new(sub.title),
                "description" => Crinja::Value.new(sub.description || ""),
                "url"         => Crinja::Value.new(sub.url),
                "pages_count" => Crinja::Value.new(sub.pages.size),
              })
            end

            # Use the page's assets as section assets
            section_assets_array = assets_array
          elsif !page.section.empty?
            # For regular pages, find the parent section via O(1) lookup
            section_page = site.sections_by_name[page.section]?
            if section_page
              section_title = section_page.title
              section_description = section_page.description || ""
              current_section = page.section
              # Use cached section assets to avoid re-allocating per page
              section_assets_array = @section_assets_crinja_cache[page.section]? || begin
                arr = section_page.assets.map { |a| Crinja::Value.new(a) }
                @section_assets_crinja_cache[page.section] = arr
                arr
              end
            end
          end

          if !current_section.empty?
            if paginator
              # Paginated: convert paginator's page subset
              default_lang = config.default_language
              section_pages_array = paginator.pages.map { |p| page_to_crinja_list_value(p, default_lang) }
            else
              # Non-paginated: use per-section cache, then exclude current page
              all_section = cached_section_pages_crinja(current_section, page.language, site)
              page_url_str = page.url
              section_pages_array = all_section.reject do |v|
                raw = v.raw
                raw.is_a?(Hash) && raw["url"]?.try(&.to_s) == page_url_str
              end
            end
          end
          vars["section_title"] = Crinja::Value.new(section_title)
          vars["section_description"] = Crinja::Value.new(section_description)

          # Section object with structured access
          # - section.title, section.description, section.pages (for iteration)
          # - section.list (HTML string, same as section_list for convenience)
          section_obj = {
            "title"       => Crinja::Value.new(section_title),
            "description" => Crinja::Value.new(section_description),
            "pages"       => Crinja::Value.new(section_pages_array),
            "pages_count" => Crinja::Value.new(section_pages_array.size),
            "list"        => Crinja::Value.new(section_list),
            # New section properties
            "subsections"   => Crinja::Value.new(subsections_array),
            "assets"        => Crinja::Value.new(section_assets_array),
            "page_template" => Crinja::Value.new(page_template_var),
            "paginate_path" => Crinja::Value.new(paginate_path_var),
            "redirect_to"   => Crinja::Value.new(redirect_to_var),
          }
          vars["section"] = Crinja::Value.new(section_obj)

          # Content and layout variables
          vars["content"] = Crinja::Value.new(content)
          vars["section_list"] = Crinja::Value.new(section_list)

          # TOC variables - both flat and structured access
          # - toc (HTML string for backward compatibility)
          # - toc.html (structured access to the same HTML)
          vars["toc"] = Crinja::Value.new(toc)
          toc_obj = {
            "html" => Crinja::Value.new(toc),
          }
          vars["toc_obj"] = Crinja::Value.new(toc_obj)

          vars["pagination"] = Crinja::Value.new(pagination)
          vars["pagination_seo_links"] = Crinja::Value.new(pagination_seo_links)

          if paginator
            # Reuse section_pages_array already built above for paginator.pages
            paginator_obj = {
              "paginate_by"   => Crinja::Value.new(paginator.per_page),
              "base_url"      => Crinja::Value.new(paginator.base_url),
              "number_pagers" => Crinja::Value.new(paginator.total_pages),
              "first"         => Crinja::Value.new(paginator.first_url),
              "last"          => Crinja::Value.new(paginator.last_url),
              "previous"      => Crinja::Value.new(paginator.prev_url),
              "next"          => Crinja::Value.new(paginator.next_url),
              "pages"         => Crinja::Value.new(section_pages_array),
              "current_index" => Crinja::Value.new(paginator.page_number),
              "total_pages"   => Crinja::Value.new(paginator.total_items),
            }
            vars["paginator"] = Crinja::Value.new(paginator_obj)
          end

          # NOTE: highlight_css/js/tags and auto_includes_css/js are now in
          # global_vars (computed once in build_global_vars).

          # OG/Twitter tags (page-specific — depend on page title/description/url/image)
          og_tags = config.og.og_tags(page.title, page.description, effective_url, page.image, config.base_url)
          twitter_tags = config.og.twitter_tags(page.title, page.description, page.image, config.base_url)
          og_all_tags = [og_tags, twitter_tags].reject(&.empty?).join("\n")
          vars["og_tags"] = Crinja::Value.new(og_tags)
          vars["twitter_tags"] = Crinja::Value.new(twitter_tags)
          vars["og_all_tags"] = Crinja::Value.new(og_all_tags)

          # Canonical and Hreflang tags
          canonical_tag = Content::Seo::Tags.canonical_tag(page, config)
          hreflang_tags = Content::Seo::Tags.hreflang_tags(page, config)
          vars["canonical_tag"] = Crinja::Value.new(canonical_tag)
          vars["hreflang_tags"] = Crinja::Value.new(hreflang_tags)

          # JSON-LD structured data — generate breadcrumb only when needed
          jsonld_article = Content::Seo::JsonLd.article(page, config)
          needs_breadcrumb = !page.ancestors.empty? || !page.is_index
          jsonld_breadcrumb = needs_breadcrumb ? Content::Seo::JsonLd.breadcrumb(page, config) : ""
          jsonld_all = needs_breadcrumb ? "#{jsonld_article}\n#{jsonld_breadcrumb}" : jsonld_article
          vars["jsonld_article"] = Crinja::Value.new(jsonld_article)
          vars["jsonld_breadcrumb"] = Crinja::Value.new(jsonld_breadcrumb)
          vars["jsonld"] = Crinja::Value.new(jsonld_all)

          # NOTE: current_year/current_date/current_datetime are now in
          # global_vars (computed once in build_global_vars).

          if global_vars
            vars.merge!(global_vars)
          else
            vars.merge!(build_global_vars(site))
          end

          vars
        end

        # Very conservative HTML minification
        # Only removes: HTML comments, trailing whitespace on lines, excessive blank lines
        # Preserves: all meaningful whitespace, newlines, indentation structure
        private def minify_html(html : String) : String
          # Clean up template-induced whitespace inside pre blocks
          # This handles cases like: <pre>\n  <code>content</code>\n</pre>
          # Converting to: <pre><code>content</code></pre>
          cleaned = html
            .gsub(REGEX_PRE_OPEN, "<pre\\1><code")  # <pre>\n  <code> -> <pre><code>
            .gsub(REGEX_PRE_CLOSE, "</code></pre>") # </code>\n</pre> -> </code></pre>

          # Remove HTML comments (but not conditional comments like <!--[if IE]>)
          # Also preserve <!-- more --> markers used for content summaries
          minified = cleaned.gsub(REGEX_COMMENTS, "")

          # Collapse 3+ consecutive blank lines to 2
          minified = minified.gsub(REGEX_BLANK_LINES, "\n\n")

          minified.strip
        end

        private def write_output(page : Models::Page, output_dir : String, content : String, verbose : Bool)
          output_path = get_output_path(page, output_dir)

          FileUtils.mkdir_p(Path[output_path].dirname)
          File.write(output_path, content)
          Logger.action :create, output_path if verbose
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
            url_path = page.url.sub(/^\//, "")
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
      end
    end
  end
end
