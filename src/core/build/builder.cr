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

require "file_utils"
require "set"
require "toml"
require "uri"
require "crinja"
require "./cache"
require "./parallel"
require "../../content/seo/feeds"
require "../../content/seo/sitemap"
require "../../content/seo/robots"
require "../../content/seo/llms"
require "../../content/seo/tags"
require "../../content/search"
require "../../content/pagination/paginator"
require "../../content/pagination/renderer"
require "../../utils/logger"
require "../../utils/profiler"
require "../../config/options/build_options"
require "../../content/processors/markdown"
require "../../content/processors/content_files"
require "../../content/processors/template"
require "../../content/multilingual"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../models/toc"
require "../../models/site"
require "../lifecycle"
require "../../utils/debug_printer"

module Hwaro
  module Core
    module Build
      class Builder
        @site : Models::Site?
        @templates : Hash(String, String)?
        @cache : Cache?
        @config : Models::Config?
        @lifecycle : Lifecycle::Manager
        @context : Lifecycle::BuildContext?
        @profiler : Profiler?
        @crinja_env : Crinja?

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
            debug: options.debug
          )
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
        )
          # Load config early to get build hooks
          config = Models::Config.load
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
            debug: debug
          )
          ctx = Lifecycle::BuildContext.new(options)
          ctx.stats.start_time = Time.instant
          @context = ctx

          # Reset internal caches
          @site = nil
          @templates = nil

          # Execute build phases through lifecycle
          result = execute_phases(ctx, drafts, minify, parallel, cache, highlight, verbose, profiler, base_url)

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
          drafts : Bool,
          minify : Bool,
          parallel : Bool,
          cache_enabled : Bool,
          highlight : Bool,
          verbose : Bool,
          profiler : Profiler,
          base_url_override : String?,
        ) : Lifecycle::HookResult
          output_dir = ctx.output_dir

          # Phase: Initialize
          profiler.start_phase("Initialize")
          result = @lifecycle.run_phase(Lifecycle::Phase::Initialize, ctx) do
            @cache = Cache.new(enabled: cache_enabled)
            ctx.cache = @cache

            if cache_enabled
              stats = @cache.not_nil!.stats
              Logger.info "  Cache enabled (#{stats[:valid]} valid entries)"
            end

            setup_output_dir(output_dir)
            copy_static_files(output_dir, verbose)

            config = Models::Config.load
            if url = base_url_override
              override = url.strip
              config.base_url = override unless override.empty?
            end
            @site = Models::Site.new(config)
            @config = config
            ctx.site = @site
            ctx.config = config

            ctx.templates = load_templates
            @templates = ctx.templates
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          site = @site.not_nil!
          templates = @templates.not_nil!
          build_cache = @cache.not_nil!

          # Phase: ReadContent
          profiler.start_phase("ReadContent")
          result = @lifecycle.run_phase(Lifecycle::Phase::ReadContent, ctx) do
            collect_content_paths(ctx, drafts)
            Logger.info "  Found #{ctx.all_pages.size} pages."
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ParseContent (hooks handle actual parsing)
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

          # Phase: Transform
          profiler.start_phase("Transform")
          result = @lifecycle.run_phase(Lifecycle::Phase::Transform, ctx) do
            # Hooks handle transformation (Markdown → HTML)
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          # Populate site with pages and sections from context
          site.pages = ctx.pages
          site.sections = ctx.sections

          # Build optimized lookup indices
          site.build_lookup_index

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

          # Phase: Render
          profiler.start_phase("Render")
          result = @lifecycle.run_phase(Lifecycle::Phase::Render, ctx) do
            global_vars = build_global_vars(site)
            count = if parallel && pages_to_build.size > 1
                      process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars)
                    else
                      process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache, use_highlight, verbose, global_vars)
                    end
            ctx.stats.pages_rendered = count
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Generate (SEO, Search, etc.)
          profiler.start_phase("Generate")
          result = @lifecycle.run_phase(Lifecycle::Phase::Generate, ctx) do
            # Default generation if no SEO hooks registered
            unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeGenerate)
              Content::Seo::Sitemap.generate(all_pages, site, output_dir)
              Content::Seo::Feeds.generate(all_pages, site.config, output_dir)
              Content::Seo::Robots.generate(site.config, output_dir)
              Content::Seo::Llms.generate(site.config, all_pages, output_dir)
              Content::Search.generate(all_pages, site.config, output_dir)
            end
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Write
          profiler.start_phase("Write")
          result = @lifecycle.run_phase(Lifecycle::Phase::Write, ctx) do
            generate_404_page(site, templates, output_dir, minify, verbose)

            # Process raw files (JSON, XML)
            raw_count = process_raw_files(ctx.raw_files, output_dir, minify, verbose)
            ctx.stats.raw_files_processed = raw_count

            # Process co-located assets (images, etc. in page bundles)
            process_assets(ctx.all_pages, output_dir, verbose)
          end
          profiler.end_phase
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Finalize
          profiler.start_phase("Finalize")
          result = @lifecycle.run_phase(Lifecycle::Phase::Finalize, ctx) do
            build_cache.save if cache_enabled
          end
          profiler.end_phase
          result
        end

        # Collect content file paths without parsing
        private def collect_content_paths(ctx : Lifecycle::BuildContext, include_drafts : Bool)
          config = ctx.config

          # Collect markdown files
          Dir.glob("content/**/*.md") do |file_path|
            relative_path = Path[file_path].relative_to("content").to_s
            basename = Path[relative_path].basename

            # Extract language from filename (e.g., "about.ko.md" -> "ko", "_index.ko.md" -> "ko")
            language = extract_language_from_filename(basename, config)

            # Remove language suffix from basename for is_index check
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

            # Set basic path info
            path_parts = Path[relative_path].parts
            # For nested sections, section is the full path to the directory
            if is_section_index
              # For _index.md, section is the directory path
              page.section = path_parts.size > 1 ? path_parts[0..-2].join("/") : ""
            elsif is_index
              # For index.md, section is the parent directory
              page.section = path_parts.size > 2 ? path_parts[0..-3].join("/") : ""
            else
              # For regular pages, section is the directory path
              page.section = path_parts.size > 1 ? path_parts[0..-2].join("/") : ""
            end
            page.is_index = is_index
            page.language = language
          end

          # Collect raw files (JSON, XML) for processing
          collect_raw_files(ctx)
        end

        # Collect JSON and XML files from content directory
        private def collect_raw_files(ctx : Lifecycle::BuildContext)
          seen = Set(String).new

          add_raw_file = ->(file_path : String) do
            relative_path = Path[file_path].relative_to("content").to_s
            return if seen.includes?(relative_path)
            ctx.raw_files << Lifecycle::RawFile.new(file_path, relative_path)
            seen << relative_path
          end

          # JSON files
          Dir.glob("content/**/*.json") { |file_path| add_raw_file.call(file_path) }

          # XML files
          Dir.glob("content/**/*.xml") { |file_path| add_raw_file.call(file_path) }

          # Publish configured non-Markdown content files as-is (images, PDFs, etc.)
          if config = ctx.config
            return unless config.content_files.enabled?

            Dir.glob("content/**/*") do |file_path|
              next if File.directory?(file_path)
              relative_path = Path[file_path].relative_to("content").to_s
              next unless Content::Processors::ContentFiles.publish?(relative_path, config)
              add_raw_file.call(file_path)
            end
          end
        end

        # Extract language code from filename if it matches configured languages
        private def extract_language_from_filename(basename : String, config : Models::Config?) : String?
          return nil unless config
          return nil unless config.multilingual?

          # Match pattern: filename.lang.md (e.g., "about.ko.md" -> "ko", "_index.ko.md" -> "ko")
          if match = basename.match(/^(.+)\.([a-z]{2,3})\.md$/)
            lang_code = match[2]
            return lang_code if config.languages.has_key?(lang_code) || lang_code == config.default_language
          end

          nil
        end

        # Default parsing when no hooks are registered
        private def parse_content_default(ctx : Lifecycle::BuildContext)
          ctx.all_pages.each do |page|
            source_path = File.join("content", page.path)
            next unless File.exists?(source_path)

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
              page.redirect_to = data[:redirect_to]
            end

            # Calculate URL
            calculate_page_url(page)
          end

          # Filter drafts
          unless ctx.options.drafts
            ctx.pages.reject! { |p| p.draft }
            ctx.sections.reject! { |s| s.draft }
          end
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

        # Populate site.taxonomies from all pages
        private def populate_taxonomies(ctx : Lifecycle::BuildContext)
          site = ctx.site.not_nil!
          site.taxonomies.clear

          ctx.all_pages.each do |page|
            page.taxonomies.each do |name, terms|
              site.taxonomies[name] ||= {} of String => Array(Models::Page)
              terms.each do |term|
                site.taxonomies[name][term] ||= [] of Models::Page
                site.taxonomies[name][term] << page
              end
            end
          end

          # Sort pages in taxonomies (default by date)
          site.taxonomies.each_value do |terms|
            terms.each_value do |pages|
              sorted = Utils::SortUtils.sort_pages(pages, "date", false)
              pages.clear
              pages.concat(sorted)
            end
          end
        end

        private def calculate_page_url(page : Models::Page)
          relative_path = page.path
          path_parts = Path[relative_path].parts

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
            if path_parts.size == 1
              page.url = lang_prefix.empty? ? "/" : "#{lang_prefix}/"
            else
              parent = Path[relative_path].dirname
              page.url = "#{lang_prefix}/#{parent}/"
            end
          else
            dir = Path[relative_path].dirname
            stem = Path[relative_path].stem

            # Remove language suffix from stem (e.g., "hello-world.ko" -> "hello-world")
            clean_stem = if page.language
                           stem.sub(/\.#{page.language}$/, "")
                         else
                           stem
                         end

            leaf = page.slug || clean_stem

            if dir == "."
              page.url = "#{lang_prefix}/#{leaf}/"
            else
              page.url = "#{lang_prefix}/#{dir}/#{leaf}/"
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
          url_path = page.url.sub(/^\//, "")
          File.join(output_dir, url_path, "index.html")
        end

        private def setup_output_dir(output_dir : String)
          if Dir.exists?(output_dir)
            FileUtils.rm_rf(output_dir)
          end
          FileUtils.mkdir_p(output_dir)
        end

        private def copy_static_files(output_dir : String, verbose : Bool)
          if Dir.exists?("static")
            FileUtils.cp_r("static/.", "#{output_dir}/")
            Logger.action :copy, "static files", :blue if verbose
          end
        end

        private def load_templates : Hash(String, String)
          return @templates.not_nil! if @templates

          templates = {} of String => String
          if Dir.exists?("templates")
            # Support multiple template extensions: .html (recommended), .j2, .jinja2, .jinja
            # Note: .ecr files are loaded but processed as Jinja2 templates (legacy filename support only)
            extensions = ["html", "j2", "jinja2", "jinja", "ecr"]
            extensions.each do |ext|
              Dir.glob("templates/**/*.#{ext}") do |path|
                relative = Path[path].relative_to("templates")
                name = relative.to_s.gsub(/\.(html|j2|jinja2|jinja|ecr)$/, "")
                # Don't overwrite if already loaded (priority: html > j2 > jinja2 > jinja > ecr)
                templates[name] ||= File.read(path)
              end
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
        ) : Int32
          config = ParallelConfig.new(enabled: true)
          processor = Parallel(Models::Page, Bool).new(config)

          safe = site.config.markdown.safe
          results = processor.process(pages) do |page, _idx|
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars)
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.update(source_path, output_path)
            true
          end

          results.count(&.success)
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
        ) : Int32
          count = 0
          safe = site.config.markdown.safe
          pages.each do |page|
            render_page(page, site, templates, output_dir, minify, highlight, safe, verbose, global_vars)
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
        )
          return unless page.render

          # Handle redirect_to for sections
          if page.is_a?(Models::Section) && page.has_redirect?
            generate_redirect_page(page, output_dir, verbose)
            return
          end

          # Build initial context for shortcodes (without content/toc)
          shortcode_context = build_template_variables(page, site, "", "", "", "", nil, nil, global_vars)

          shortcode_results = {} of String => String
          processed_content = process_shortcodes_jinja(page.raw_content, templates, shortcode_context, shortcode_results)

          # Use anchor links if enabled
          html_content, toc_headers = if page.insert_anchor_links
                                        Content::Processors::Markdown.new.render_with_anchors(processed_content, highlight, safe, "after")
                                      else
                                        Processor::Markdown.render(processed_content, highlight, safe)
                                      end

          # Replace shortcode placeholders with their rendered HTML content
          html_content = replace_shortcode_placeholders(html_content, shortcode_results)

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
            render_section_with_pagination(page.as(Models::Section), site, templates, template_content, output_dir, minify, html_content, toc_html, verbose, global_vars)
          else
            section_list_html = ""

            final_html = if template_content
                           apply_template(template_content, html_content, page, site, section_list_html, toc_html, templates, global_vars: global_vars)
                         else
                           Logger.warn "  [WARN] No template found for #{page.path}. Using raw content."
                           html_content
                         end

            final_html = minify_html(final_html) if minify

            write_output(page, output_dir, final_html, verbose)
          end

          generate_aliases(page, output_dir, verbose)
        end

        # Generate redirect page for sections with redirect_to
        private def generate_redirect_page(
          section : Models::Section,
          output_dir : String,
          verbose : Bool = false,
        )
          redirect_url = section.redirect_to
          return unless redirect_url

          redirect_html = <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta http-equiv="refresh" content="0; url=#{redirect_url}">
            <link rel="canonical" href="#{redirect_url}">
            <title>Redirecting...</title>
          </head>
          <body>
            <p>Redirecting to <a href="#{redirect_url}">#{redirect_url}</a>...</p>
            <script>window.location.href = "#{redirect_url}";</script>
          </body>
          </html>
          HTML

          output_path = File.join(output_dir, section.url.sub(/^\//, ""), "index.html")
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
        )
          # Get pages in this section using the site utility method
          section_name = Path[section.path].dirname
          section_name = "" if section_name == "."
          section_pages = site.pages_for_section(section_name, section.language).dup

          section_pages.sort_by! { |p| p.title }

          # Create paginator and render
          paginator = Content::Pagination::Paginator.new(site.config)
          pagination_result = paginator.paginate(section, section_pages)
          renderer = Content::Pagination::Renderer.new(site.config)

          pagination_result.paginated_pages.each do |paginated_page|
            section_list_html = renderer.render_section_list(paginated_page)
            pagination_nav_html = renderer.render_pagination_nav(paginated_page)

            # Use the correct URL for each paginated page during rendering (important for SEO tags, nav, etc.)
            base = section.url.rstrip("/")
            current_url = if paginated_page.page_number == 1
                            "#{base}/"
                          else
                            "#{base}/page/#{paginated_page.page_number}/"
                          end

            final_html = if template_content
                           apply_template(template_content, html_content, section, site, section_list_html, toc_html, templates, pagination_nav_html, current_url, paginated_page, global_vars)
                         else
                           Logger.warn "  [WARN] No template found for #{section.path}. Using raw content."
                           html_content
                         end

            final_html = minify_html(final_html) if minify

            # Write output - first page uses section URL, subsequent pages use /page/N/
            if paginated_page.page_number == 1
              write_output(section, output_dir, final_html, verbose)
            else
              write_paginated_output(section, paginated_page.page_number, output_dir, final_html, verbose)
            end
          end
        end

        private def write_paginated_output(page : Models::Page, page_number : Int32, output_dir : String, content : String, verbose : Bool)
          # Sanitize URL to prevent path traversal
          url_path = sanitize_path(page.url.sub(/^\//, "").rstrip("/"))
          output_path = File.join(output_dir, url_path, "page", page_number.to_s, "index.html")

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

        # Sanitize path to prevent directory traversal
        # Uses Crystal's Path normalization and filters out unsafe components
        private def sanitize_path(path : String) : String
          # URL-decode the path first to handle encoded traversal attempts
          decoded = URI.decode(path)
          # Remove any parent directory references, null bytes, and normalize slashes
          decoded
            .gsub(/\.\./, "")       # Remove parent directory references
            .gsub(/\0/, "")         # Remove null bytes
            .gsub(/\/+/, "/")       # Normalize multiple slashes
            .gsub(/^\/+|^\/+$/, "") # Strip leading/trailing slashes
        end

        private def determine_template(page : Models::Page, templates : Hash(String, String)) : String
          if custom = page.template
            return custom if templates.has_key?(custom)
            Logger.warn "  [WARN] Custom template '#{custom}' not found for #{page.path}."
          end

          if page.is_a?(Models::Section)
            return "section" if templates.has_key?("section")
          end

          if page.is_index && page.section.empty? && templates.has_key?("index")
            return "index"
          end

          "page"
        end

        private def generate_section_list(current_page : Models::Page, site : Models::Site) : String
          # Use the site utility method to get pages for the current section
          section_name = current_page.section
          section_pages = site.pages_for_section(section_name, current_page.language)

          # Exclude the current page if it was included
          section_pages.reject! { |p| p == current_page }

          section_pages.sort_by! { |p| p.title }

          String.build do |str|
            section_pages.each do |p|
              full_url = "#{site.config.base_url}#{p.url}"
              str << "<li><a href=\"#{full_url}\">#{p.title}</a></li>\n"
            end
          end
        end

        private def generate_aliases(page : Models::Page, output_dir : String, verbose : Bool)
          page.aliases.each do |alias_path|
            alias_clean = alias_path.sub(/^\//, "")
            dest_path = File.join(output_dir, alias_clean, "index.html")
            FileUtils.mkdir_p(File.dirname(dest_path))

            redirect_url = page.url

            content = <<-HTML
            <!DOCTYPE html>
            <html>
            <head>
              <meta http-equiv="refresh" content="0; url=#{redirect_url}" />
              <title>Redirecting to #{redirect_url}</title>
            </head>
            <body>
              <p>Redirecting to <a href="#{redirect_url}">#{redirect_url}</a>.</p>
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
        ) : String
          # Use Crinja for Jinja2-style templates
          env = crinja_env

          # Build template variables
          vars = build_template_variables(page, site, content, section_list, toc, pagination, page_url_override, paginator, global_vars)

          # Process shortcodes in template first (convert to Jinja2 include syntax)
          processed_template = process_shortcodes_jinja(template, templates, vars)

          begin
            crinja_template = env.from_string(processed_template)
            crinja_template.render(vars)
          rescue ex : Crinja::TemplateError
            Logger.warn "  [WARN] Template error for #{page.path}: #{ex.message}"
            # Fallback to content only
            content
          end
        end

        # Build global template variables once
        private def build_global_vars(site : Models::Site) : Hash(String, Crinja::Value)
          config = site.config
          vars = {} of String => Crinja::Value

          # Hidden variables for get_page/get_section/get_taxonomy functions
          # These are prefixed with __ to indicate they're internal
          all_pages_array = site.pages.map do |p|
            Crinja::Value.new({
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
          end
          vars["__all_pages__"] = Crinja::Value.new(all_pages_array)

          all_sections_array = site.sections.map do |s|
            section_pages = s.pages.map do |sp|
              Crinja::Value.new({
                "title" => Crinja::Value.new(sp.title),
                "url"   => Crinja::Value.new(sp.url),
                "date"  => Crinja::Value.new(sp.date.try(&.to_s("%Y-%m-%d")) || ""),
              })
            end
            Crinja::Value.new({
              "path"        => Crinja::Value.new(s.path),
              "name"        => Crinja::Value.new(s.section),
              "title"       => Crinja::Value.new(s.title),
              "description" => Crinja::Value.new(s.description || ""),
              "url"         => Crinja::Value.new(s.url),
              "pages"       => Crinja::Value.new(section_pages),
              "pages_count" => Crinja::Value.new(s.pages.size),
              "assets"      => Crinja::Value.new(s.assets.map { |a| Crinja::Value.new(a) }),
            })
          end
          vars["__all_sections__"] = Crinja::Value.new(all_sections_array)

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
          }
          vars["site"] = Crinja::Value.new(site_obj)

          vars
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
        ) : Hash(String, Crinja::Value)
          config = site.config
          vars = {} of String => Crinja::Value

          effective_url = page_url_override || page.url

          # Page variables (flat for convenience)
          vars["page_title"] = Crinja::Value.new(page.title)
          vars["page_description"] = Crinja::Value.new(page.description || config.description || "")
          vars["page_url"] = Crinja::Value.new(effective_url)
          vars["page_section"] = Crinja::Value.new(page.section)
          vars["page_date"] = Crinja::Value.new(page.date.try(&.to_s("%Y-%m-%d")) || "")
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

          # Generate permalink
          page.generate_permalink(config.base_url)

          # Convert authors to Crinja array
          authors_array = page.authors.map { |a| Crinja::Value.new(a) }

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
            "date"         => Crinja::Value.new(page.date.try(&.to_s("%Y-%m-%d")) || ""),
            "updated"      => Crinja::Value.new(page.updated.try(&.to_s("%Y-%m-%d")) || ""),
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
          vars["page_weight"] = Crinja::Value.new(page.weight)

          # Site variables (flat for convenience)
          vars["site_title"] = Crinja::Value.new(config.title)
          vars["site_description"] = Crinja::Value.new(config.description || "")
          vars["base_url"] = Crinja::Value.new(config.base_url)

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
            # For regular pages, find the parent section
            section_page = (site.pages + site.sections).find { |p| p.section == page.section && p.is_index }
            if section_page
              section_title = section_page.title
              section_description = section_page.description || ""
              current_section = page.section
              # Use the section page's assets
              section_assets_array = section_page.assets.map { |a| Crinja::Value.new(a) }
            end
          end

          if !current_section.empty?
            # Use paginated pages if provided (for section pages with pagination)
            # Otherwise, fall back to full section pages list
            section_pages = if paginator
                              paginator.pages
                            else
                              pages = site.pages_for_section(current_section, page.language).dup
                              # Exclude the current page if it was included
                              pages.reject! { |p| p == page }
                              pages.sort_by! { |p| p.title }
                              pages
                            end

            section_pages_array = section_pages.map do |p|
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
                "language"    => Crinja::Value.new(p.language || config.default_language),
              })
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

          if paginator
            paginator_obj = {
              "paginate_by"   => Crinja::Value.new(paginator.per_page),
              "base_url"      => Crinja::Value.new(paginator.base_url),
              "number_pagers" => Crinja::Value.new(paginator.total_pages),
              "first"         => Crinja::Value.new(paginator.first_url),
              "last"          => Crinja::Value.new(paginator.last_url),
              "previous"      => Crinja::Value.new(paginator.prev_url),
              "next"          => Crinja::Value.new(paginator.next_url),
              "pages"         => Crinja::Value.new(paginator.pages.map do |p|
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
                  "language"    => Crinja::Value.new(p.language || config.default_language),
                  "summary"     => Crinja::Value.new(p.effective_summary || ""),
                  "word_count"  => Crinja::Value.new(p.word_count),
                  "reading_time"=> Crinja::Value.new(p.reading_time),
                  "permalink"   => Crinja::Value.new(p.permalink || ""),
                  "weight"      => Crinja::Value.new(p.weight),
                  "authors"     => Crinja::Value.new(p.authors.map { |a| Crinja::Value.new(a) }),
                })
              end),
              "current_index" => Crinja::Value.new(paginator.page_number),
              "total_pages"   => Crinja::Value.new(paginator.total_items),
            }
            vars["paginator"] = Crinja::Value.new(paginator_obj)
          end

          # Highlight tags
          vars["highlight_css"] = Crinja::Value.new(config.highlight.css_tag)
          vars["highlight_js"] = Crinja::Value.new(config.highlight.js_tag)
          vars["highlight_tags"] = Crinja::Value.new(config.highlight.tags)

          # Auto includes
          vars["auto_includes_css"] = Crinja::Value.new(config.auto_includes.css_tags(config.base_url))
          vars["auto_includes_js"] = Crinja::Value.new(config.auto_includes.js_tags(config.base_url))
          vars["auto_includes"] = Crinja::Value.new(config.auto_includes.all_tags(config.base_url))

          # OG/Twitter tags
          og_tags = config.og.og_tags(page.title, page.description, effective_url, page.image, config.base_url)
          twitter_tags = config.og.twitter_tags(page.title, page.description, page.image, config.base_url)
          og_all_tags = config.og.all_tags(page.title, page.description, effective_url, page.image, config.base_url)
          vars["og_tags"] = Crinja::Value.new(og_tags)
          vars["twitter_tags"] = Crinja::Value.new(twitter_tags)
          vars["og_all_tags"] = Crinja::Value.new(og_all_tags)

          # Canonical and Hreflang tags
          canonical_tag = Content::Seo::Tags.canonical_tag(page, config)
          hreflang_tags = Content::Seo::Tags.hreflang_tags(page, config)
          vars["canonical_tag"] = Crinja::Value.new(canonical_tag)
          vars["hreflang_tags"] = Crinja::Value.new(hreflang_tags)

          # Time-related variables
          now = Time.local
          vars["current_year"] = Crinja::Value.new(now.year)
          vars["current_date"] = Crinja::Value.new(now.to_s("%Y-%m-%d"))
          vars["current_datetime"] = Crinja::Value.new(now.to_s("%Y-%m-%d %H:%M:%S"))

          if global_vars
            vars.merge!(global_vars)
          else
            vars.merge!(build_global_vars(site))
          end

          vars
        end

        # Process shortcodes in content (Jinja2/Crinja style)
        # Supports two syntax patterns:
        # 1. Explicit: {{ shortcode("name", arg1="value1", arg2="value2") }}
        # 2. Direct:   {{ name(arg1="value1", arg2="value2") }}
        private def process_shortcodes_jinja(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil) : String
          # Avoid processing shortcodes inside fenced code blocks (``` / ~~~),
          # so documentation can show literal `{{ ... }}` examples safely.
          String.build do |io|
            in_fence = false
            fence_marker = ""
            buffer = String::Builder.new

            content.each_line(chomp: false) do |line|
              if in_fence
                io << line
                if line.match(/^\s*#{Regex.escape(fence_marker)}\s*$/)
                  in_fence = false
                  fence_marker = ""
                end
                next
              end

              if match = line.match(/^\s*(`{3,}|~{3,})/)
                io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results)
                buffer = String::Builder.new
                in_fence = true
                fence_marker = match[1]
                io << line
              else
                buffer << line
              end
            end

            io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results)
          end
        end

        private def process_shortcodes_in_text(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil) : String
          processed = content.gsub(/\{\%\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\%\}(.*?)\{\%\s*end\s*\%\}/m) do |match|
            name = $1
            args_str = $2
            body = $3.strip

            template_key = "shortcodes/#{name}"
            if template = templates[template_key]?
              args = parse_shortcode_args_jinja(args_str)
              args["body"] = body
              html = render_shortcode_jinja(template, args, context)
              if results = shortcode_results
                placeholder = "HWARO-SHORTCODE-PLACEHOLDER-#{results.size}"
                results[placeholder] = html
                placeholder
              else
                html
              end
            else
              Logger.warn "  [WARN] Shortcode template '#{template_key}' not found."
              match
            end
          end

          processed = processed.gsub(/\{\{\s*shortcode\s*\(\s*"([^"]+)"(?:\s*,\s*(.*?))?\s*\)\s*\}\}/) do |match|
            name = $1
            args_str = $2?

            template_key = "shortcodes/#{name}"
            if template = templates[template_key]?
              args = parse_shortcode_args_jinja(args_str)
              html = render_shortcode_jinja(template, args, context)
              if results = shortcode_results
                placeholder = "HWARO-SHORTCODE-PLACEHOLDER-#{results.size}"
                results[placeholder] = html
                placeholder
              else
                html
              end
            else
              Logger.warn "  [WARN] Shortcode template '#{template_key}' not found."
              match
            end
          end

          processed = processed.gsub(/\{\{\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\}\}/) do |match|
            name = $1
            args_str = $2

            template_key = "shortcodes/#{name}"
            if template = templates[template_key]?
              args = parse_shortcode_args_jinja(args_str)
              html = render_shortcode_jinja(template, args, context)
              if results = shortcode_results
                placeholder = "HWARO-SHORTCODE-PLACEHOLDER-#{results.size}"
                results[placeholder] = html
                placeholder
              else
                html
              end
            else
              match
            end
          end
        end

        # Parse shortcode arguments (key="value" or key='value' or key=value)
        private def parse_shortcode_args_jinja(args_str : String?) : Hash(String, String)
          args = {} of String => String
          return args unless args_str

          # Match: key="value", key='value', or key=value (unquoted)
          args_str.scan(/(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^,\s]+))/) do |match|
            key = match[1]
            value = match[2]? || match[3]? || match[4]? || ""
            args[key] = value
          end
          args
        end

        # Render a shortcode template with Crinja
        private def render_shortcode_jinja(template : String, args : Hash(String, String), context : Hash(String, Crinja::Value)) : String
          env = crinja_env
          vars = context.dup
          args.each do |key, value|
            vars[key] = Crinja::Value.new(value)
          end

          begin
            crinja_template = env.from_string(template)
            crinja_template.render(vars)
          rescue ex : Crinja::TemplateError
            Logger.warn "  [WARN] Shortcode template error: #{ex.message}"
            ""
          end
        end

        # Replace shortcode placeholders with their rendered HTML content
        private def replace_shortcode_placeholders(html : String, shortcode_results : Hash(String, String)) : String
          return html if shortcode_results.empty?
          html.gsub(/HWARO-SHORTCODE-PLACEHOLDER-\d+/) do |match|
            shortcode_results[match]? || match
          end
        end

        private def minify_html(html : String) : String
          html.gsub(/\n\s*/, "")
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
