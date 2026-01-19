# Main builder module for site generation
#
# This is the core build logic that orchestrates:
# - Content collection and parsing
# - Template loading and rendering
# - Parallel processing with caching
# - Output generation
#
# The Builder uses the Lifecycle system to allow extensibility
# through hooks at various phases of the build process.

require "file_utils"
require "toml"
require "uri"
require "./cache"
require "./parallel"
require "../../content/seo/feeds"
require "../../content/seo/sitemap"
require "../../content/seo/robots"
require "../../content/seo/llms"
require "../../content/search"
require "../../content/pagination/paginator"
require "../../content/pagination/renderer"
require "../../utils/logger"
require "../../config/options/build_options"
require "../../content/processors/markdown"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../models/toc"
require "../../models/site"
require "../lifecycle"

module Hwaro
  module Core
    module Build
      class Builder
        @site : Models::Site?
        @templates : Hash(String, String)?
        @cache : Cache?
        @lifecycle : Lifecycle::Manager
        @context : Lifecycle::BuildContext?

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
            drafts: options.drafts,
            minify: options.minify,
            parallel: options.parallel,
            cache: options.cache
          )
        end

        def run(
          output_dir : String = "public",
          drafts : Bool = false,
          minify : Bool = false,
          parallel : Bool = true,
          cache : Bool = false,
        )
          Logger.info "Building site..."
          start_time = Time.instant

          # Create build context for lifecycle
          options = Config::Options::BuildOptions.new(
            output_dir: output_dir,
            drafts: drafts,
            minify: minify,
            parallel: parallel,
            cache: cache
          )
          ctx = Lifecycle::BuildContext.new(options)
          ctx.stats.start_time = Time.instant
          @context = ctx

          # Reset internal caches
          @site = nil
          @templates = nil

          # Execute build phases through lifecycle
          result = execute_phases(ctx, drafts, minify, parallel, cache)

          ctx.stats.end_time = Time.instant

          if result == Lifecycle::HookResult::Abort
            Logger.error "Build failed!"
            return
          end

          elapsed = Time.instant - start_time
          Logger.success "Build complete! Generated #{ctx.stats.pages_rendered} pages in #{elapsed.total_milliseconds.round(2)}ms."
        end

        # Execute all build phases with lifecycle hooks
        private def execute_phases(
          ctx : Lifecycle::BuildContext,
          drafts : Bool,
          minify : Bool,
          parallel : Bool,
          cache_enabled : Bool,
        ) : Lifecycle::HookResult
          output_dir = ctx.output_dir

          # Phase: Initialize
          result = @lifecycle.run_phase(Lifecycle::Phase::Initialize, ctx) do
            @cache = Cache.new(enabled: cache_enabled)
            ctx.cache = @cache

            if cache_enabled
              stats = @cache.not_nil!.stats
              Logger.info "  Cache enabled (#{stats[:valid]} valid entries)"
            end

            setup_output_dir(output_dir)
            copy_static_files(output_dir)

            config = Models::Config.load
            @site = Models::Site.new(config)
            ctx.site = @site
            ctx.config = config

            ctx.templates = load_templates
            @templates = ctx.templates
          end
          return result if result != Lifecycle::HookResult::Continue

          site = @site.not_nil!
          templates = @templates.not_nil!
          build_cache = @cache.not_nil!

          # Phase: ReadContent
          result = @lifecycle.run_phase(Lifecycle::Phase::ReadContent, ctx) do
            collect_content_paths(ctx, drafts)
            Logger.info "  Found #{ctx.all_pages.size} pages."
          end
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ParseContent (hooks handle actual parsing)
          result = @lifecycle.run_phase(Lifecycle::Phase::ParseContent, ctx) do
            # Default parsing if no hooks registered
            unless @lifecycle.has_hooks?(Lifecycle::HookPoint::AfterReadContent)
              parse_content_default(ctx)
            end
          end
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Transform
          result = @lifecycle.run_phase(Lifecycle::Phase::Transform, ctx) do
            # Hooks handle transformation (Markdown → HTML)
          end
          return result if result != Lifecycle::HookResult::Continue

          # Populate site with pages and sections from context
          site.pages = ctx.pages
          site.sections = ctx.sections

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

          # Phase: Render
          result = @lifecycle.run_phase(Lifecycle::Phase::Render, ctx) do
            count = if parallel && pages_to_build.size > 1
                      process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache)
                    else
                      process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache)
                    end
            ctx.stats.pages_rendered = count
          end
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Generate (SEO, Search, etc.)
          result = @lifecycle.run_phase(Lifecycle::Phase::Generate, ctx) do
            # Default generation if no SEO hooks registered
            unless @lifecycle.has_hooks?(Lifecycle::HookPoint::BeforeGenerate)
              Content::Seo::Sitemap.generate(all_pages, site, output_dir)
              Content::Seo::Feeds.generate(all_pages, site.config, output_dir)
              Content::Seo::Robots.generate(site.config, output_dir)
              Content::Seo::Llms.generate(site.config, output_dir)
              Content::Search.generate(all_pages, site.config, output_dir)
            end
          end
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Write
          result = @lifecycle.run_phase(Lifecycle::Phase::Write, ctx) do
            generate_404_page(site, templates, output_dir, minify)
          end
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Finalize
          @lifecycle.run_phase(Lifecycle::Phase::Finalize, ctx) do
            build_cache.save if cache_enabled
          end
        end

        # Collect content file paths without parsing
        private def collect_content_paths(ctx : Lifecycle::BuildContext, include_drafts : Bool)
          Dir.glob("content/**/*.md") do |file_path|
            relative_path = Path[file_path].relative_to("content").to_s
            basename = Path[relative_path].basename
            is_index = basename == "index.md" || basename == "_index.md"

            if is_index
              page = Models::Section.new(relative_path)
              ctx.sections << page
            else
              page = Models::Page.new(relative_path)
              ctx.pages << page
            end

            # Set basic path info
            path_parts = Path[relative_path].parts
            page.section = path_parts.size > 1 ? path_parts.first : ""
            page.is_index = is_index
          end
        end

        # Default parsing when no hooks are registered
        private def parse_content_default(ctx : Lifecycle::BuildContext)
          ctx.all_pages.each do |page|
            source_path = File.join("content", page.path)
            next unless File.exists?(source_path)

            raw_content = File.read(source_path)
            data = Processor::Markdown.parse(raw_content, source_path)

            page.title = data[:title]
            page.raw_content = data[:content]
            page.draft = data[:draft]
            page.template = data[:layout]
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

            if page.is_a?(Models::Section)
              page.transparent = data[:transparent]
              page.generate_feeds = data[:generate_feeds]
              page.paginate = data[:paginate]
              page.pagination_enabled = data[:pagination_enabled]
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

        private def calculate_page_url(page : Models::Page)
          relative_path = page.path
          path_parts = Path[relative_path].parts

          if page.custom_path
            custom = page.custom_path.not_nil!.sub(/^\//, "")
            page.url = "/#{custom}"
            page.url += "/" unless page.url.ends_with?("/")
          elsif page.is_index
            if path_parts.size == 1
              page.url = "/"
            else
              parent = Path[relative_path].dirname
              page.url = "/#{parent}/"
            end
          else
            dir = Path[relative_path].dirname
            stem = Path[relative_path].stem
            leaf = page.slug || stem

            if dir == "."
              page.url = "/#{leaf}/"
            else
              page.url = "/#{dir}/#{leaf}/"
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

        private def copy_static_files(output_dir : String)
          if Dir.exists?("static")
            FileUtils.cp_r("static/.", "#{output_dir}/")
            Logger.action :copy, "static files", :blue
          end
        end

        private def load_templates : Hash(String, String)
          return @templates.not_nil! if @templates

          templates = {} of String => String
          if Dir.exists?("templates")
            Dir.glob("templates/**/*.ecr") do |path|
              relative = Path[path].relative_to("templates")
              name = relative.to_s.gsub(/\.ecr$/, "")
              templates[name] = File.read(path)
            end
          end

          unless templates.has_key?("page")
            if templates.has_key?("default")
              templates["page"] = templates["default"]
            end
          end

          @templates = templates
        end

        private def process_files_parallel(
          pages : Array(Models::Page),
          site : Models::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          cache : Cache,
        ) : Int32
          config = ParallelConfig.new(enabled: true)
          processor = Parallel(Models::Page, Bool).new(config)

          results = processor.process(pages) do |page, _idx|
            render_page(page, site, templates, output_dir, minify)
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
        ) : Int32
          count = 0
          pages.each do |page|
            render_page(page, site, templates, output_dir, minify)
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
        )
          return unless page.render

          processed_content = process_shortcodes(page.raw_content, templates)

          html_content, toc_headers = Processor::Markdown.render(processed_content)

          toc_html = if page.toc && !toc_headers.empty?
                       generate_toc_html(toc_headers)
                     else
                       ""
                     end

          template_name = determine_template(page, templates)
          template_content = templates[template_name]? || templates["page"]?

          # Handle section pages with pagination
          if (template_name == "section" || page.template == "section") && page.is_a?(Models::Section)
            render_section_with_pagination(page, site, templates, template_content, output_dir, minify, html_content, toc_html)
          else
            section_list_html = ""

            final_html = if template_content
                           apply_template(template_content, html_content, page, site.config, section_list_html, toc_html, templates)
                         else
                           Logger.warn "  [WARN] No template found for #{page.path}. Using raw content."
                           html_content
                         end

            final_html = minify_html(final_html) if minify

            write_output(page, output_dir, final_html)
          end

          generate_aliases(page, output_dir)
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
        )
          # Get pages in this section
          section_pages = site.pages.select do |p|
            p.section == section.section && !p.is_index
          end

          # Create paginator and render
          paginator = Content::Pagination::Paginator.new(site.config)
          pagination_result = paginator.paginate(section, section_pages)
          renderer = Content::Pagination::Renderer.new(site.config)

          pagination_result.paginated_pages.each do |paginated_page|
            section_list_html = renderer.render_section_list(paginated_page)
            pagination_nav_html = renderer.render_pagination_nav(paginated_page)

            # Combined section list with pagination nav
            combined_section_html = section_list_html + pagination_nav_html

            final_html = if template_content
                           apply_template(template_content, html_content, section, site.config, combined_section_html, toc_html, templates)
                         else
                           Logger.warn "  [WARN] No template found for #{section.path}. Using raw content."
                           html_content
                         end

            final_html = minify_html(final_html) if minify

            # Write output - first page uses section URL, subsequent pages use /page/N/
            if paginated_page.page_number == 1
              write_output(section, output_dir, final_html)
            else
              write_paginated_output(section, paginated_page.page_number, output_dir, final_html)
            end
          end
        end

        private def write_paginated_output(page : Models::Page, page_number : Int32, output_dir : String, content : String)
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
          Logger.action :create, output_path
        end

        # Sanitize path to prevent directory traversal
        # Uses Crystal's Path normalization and filters out unsafe components
        private def sanitize_path(path : String) : String
          # URL-decode the path first to handle encoded traversal attempts
          decoded = URI.decode(path)
          # Remove any parent directory references, null bytes, and normalize slashes
          decoded
            .gsub(/\.\./, "")      # Remove parent directory references
            .gsub(/\0/, "")        # Remove null bytes
            .gsub(/\/+/, "/")      # Normalize multiple slashes
            .gsub(/^\/+|\/+$/, "") # Strip leading/trailing slashes
        end

        private def determine_template(page : Models::Page, templates : Hash(String, String)) : String
          if custom = page.template
            return custom if templates.has_key?(custom)
            Logger.warn "  [WARN] Custom template '#{custom}' not found for #{page.path}."
          end

          if page.is_index && !page.section.empty? && templates.has_key?("section")
            return "section"
          end

          "page"
        end

        private def generate_section_list(current_page : Models::Page, site : Models::Site) : String
          section_pages = site.pages.select do |p|
            p.section == current_page.section && !p.is_index
          end

          section_pages.sort_by! { |p| p.title }

          String.build do |str|
            section_pages.each do |p|
              full_url = "#{site.config.base_url}#{p.url}"
              str << "<li><a href=\"#{full_url}\">#{p.title}</a></li>\n"
            end
          end
        end

        private def generate_aliases(page : Models::Page, output_dir : String)
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
            Logger.action :create, dest_path, :yellow
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

        def resolve_includes(content : String, templates : Hash(String, String), depth : Int32 = 0) : String
          return content if depth > 10

          content.gsub(/<%=\s*render\s+"([^"]+)"\s*%>/) do |match|
            name = $1
            if partial = templates[name]?
              resolve_includes(partial, templates, depth + 1)
            else
              Logger.warn "  [WARN] Partial template '#{name}' not found."
              ""
            end
          end
        end

        def apply_template(
          template : String,
          content : String,
          page : Models::Page,
          config : Models::Config,
          section_list : String,
          toc : String,
          templates : Hash(String, String),
        ) : String
          # First resolve includes (render partials)
          resolved = resolve_includes(template, templates)

          result = resolved
            .gsub(/<%=\s*page_title\s*%>/, page.title)
            .gsub(/<%=\s*page_section\s*%>/, page.section)
            .gsub(/<%=\s*section_list\s*%>/, section_list)
            .gsub(/<%=\s*toc\s*%>/, toc)
            .gsub(/<%=\s*taxonomy_name\s*%>/, page.taxonomy_name || "")
            .gsub(/<%=\s*taxonomy_term\s*%>/, page.taxonomy_term || "")
            .gsub(/<%=\s*site_title\s*%>/, config.title)
            .gsub(/<%=\s*site_description\s*%>/, config.description || "")
            .gsub(/<%=\s*base_url\s*%>/, config.base_url)
            .gsub(/<%=\s*content\s*%>/, content)

          process_shortcodes(result, templates)
        end

        private def process_shortcodes(content : String, templates : Hash(String, String)) : String
          content.gsub(/<%=\s*shortcode\s+"([^"]+)"(?:\s*,\s*(.*?))?\s*%>/) do |match|
            name = $1
            args_str = $2

            template_key = "shortcodes/#{name}"
            if template = templates[template_key]?
              args = parse_args(args_str)
              render_shortcode(template, args)
            else
              Logger.warn "  [WARN] Shortcode template '#{template_key}' not found."
              match
            end
          end
        end

        private def parse_args(args_str : String?) : Hash(String, String)
          args = {} of String => String
          return args unless args_str

          args_str.scan(/(\w+):\s*(?:"([^"]*)"|([^,\s]+))/) do |match|
            key = match[1]
            value = match[2]? || match[3]
            args[key] = value
          end
          args
        end

        private def render_shortcode(template : String, args : Hash(String, String)) : String
          result = template
          args.each do |key, value|
            result = result.gsub(/<%=\s*#{key}(\.upcase)?\s*%>/) do |m|
              if $1? == ".upcase"
                value.upcase
              else
                value
              end
            end
          end
          result
        end

        private def minify_html(html : String) : String
          html.gsub(/\n\s*/, "")
        end

        private def write_output(page : Models::Page, output_dir : String, content : String)
          output_path = get_output_path(page, output_dir)

          FileUtils.mkdir_p(Path[output_path].dirname)
          File.write(output_path, content)
          Logger.action :create, output_path
        end

        private def generate_404_page(site : Models::Site, templates : Hash(String, String), output_dir : String, minify : Bool)
          return unless templates.has_key?("404")

          template = templates["404"]
          page = Models::Page.new("404.html")
          page.title = "404 Not Found"

          content = ""
          section_list = ""
          toc = ""

          final_html = apply_template(template, content, page, site.config, section_list, toc, templates)

          final_html = minify_html(final_html) if minify

          output_path = File.join(output_dir, "404.html")
          FileUtils.mkdir_p(File.dirname(output_path))
          File.write(output_path, final_html)
          Logger.action :create, output_path
        end
      end
    end
  end
end
