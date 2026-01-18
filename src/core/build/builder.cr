# Main builder module for site generation
#
# This is the core build logic that orchestrates:
# - Content collection and parsing
# - Template loading and rendering
# - Parallel processing with caching
# - Output generation

require "file_utils"
require "toml"
require "./cache"
require "./parallel"
require "./seo/feeds"
require "./seo/sitemap"
require "../../utils/logger"
require "../../options/build_options"
require "../../plugins/processors/markdown"
require "../../schemas/config"
require "../../schemas/page"
require "../../schemas/section"
require "../../schemas/toc"
require "../../schemas/site"

module Hwaro
  module Core
    module Build
      class Builder
        @site : Schemas::Site?
        @templates : Hash(String, String)?
        @cache : Cache?

        def run(options : Options::BuildOptions)
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
          cache : Bool = false
        )
          Logger.info "Building site..."
          start_time = Time.instant

          # Reset caches
          @site = nil
          @templates = nil

          # Initialize build cache
          @cache = Cache.new(enabled: cache)
          build_cache = @cache.not_nil!

          if cache
            stats = build_cache.stats
            Logger.info "  Cache enabled (#{stats[:valid]} valid entries)"
          end

          # Setup output directory
          setup_output_dir(output_dir)

          # Copy static files
          copy_static_files(output_dir)

          # Initialize site
          config = Schemas::Config.load
          @site = Schemas::Site.new(config)
          site = @site.not_nil!

          # Load templates (cached)
          templates = load_templates

          # Collect and parse all content files
          collect_content(site, drafts)
          all_pages = (site.pages + site.sections).as(Array(Schemas::Page))

          Logger.info "  Found #{all_pages.size} pages."

          # Filter pages that need rebuilding if caching is enabled
          pages_to_build = if cache
                             filter_changed_pages(all_pages, output_dir, build_cache)
                           else
                             all_pages
                           end

          if cache && pages_to_build.size < all_pages.size
            Logger.info "  Skipping #{all_pages.size - pages_to_build.size} unchanged pages."
          end

          # Process files
          count = if parallel && pages_to_build.size > 1
                    process_files_parallel(pages_to_build, site, templates, output_dir, minify, build_cache)
                  else
                    process_files_sequential(pages_to_build, site, templates, output_dir, minify, build_cache)
                  end

          # Generate sitemap if enabled
          if site.config.sitemap
            Seo::Sitemap.generate(all_pages, site, output_dir)
          end

          # Generate feeds if enabled
          if site.config.feeds.generate
            Seo::Feeds.generate(all_pages, site.config, output_dir)
          end

          # Generate 404 page
          generate_404_page(site, templates, output_dir, minify)

          # Save cache
          build_cache.save if cache

          elapsed = Time.instant - start_time
          Logger.success "Build complete! Generated #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
        end

        private def filter_changed_pages(pages : Array(Schemas::Page), output_dir : String, cache : Cache) : Array(Schemas::Page)
          pages.select do |page|
            source_path = File.join("content", page.path)
            output_path = get_output_path(page, output_dir)
            cache.changed?(source_path, output_path)
          end
        end

        private def get_output_path(page : Schemas::Page, output_dir : String) : String
          if page.is_index
            Path[output_dir, page.path].to_s.gsub(/\.md$/, ".html")
          else
            clean_path = page.path.gsub(/\.md$/, "")
            Path[output_dir, clean_path, "index.html"].to_s
          end
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

        private def collect_content(site : Schemas::Site, include_drafts : Bool)
          Dir.glob("content/**/*.md") do |file_path|
            relative_path = Path[file_path].relative_to("content").to_s
            raw_content = File.read(file_path)

            parsed = Processor::Markdown.parse(raw_content, file_path)
            next unless parsed

            title, markdown_content, draft, layout_name, in_sitemap, toc = parsed

            if draft && !include_drafts
              next
            end

            is_index = Path[relative_path].basename == "index.md"

            if is_index
              page = Schemas::Section.new(relative_path)
              site.sections << page
            else
              page = Schemas::Page.new(relative_path)
              site.pages << page
            end

            page.title = title
            page.raw_content = markdown_content
            page.draft = draft
            page.template = layout_name
            page.in_sitemap = in_sitemap
            page.toc = toc

            path_parts = Path[relative_path].parts
            page.section = path_parts.size > 1 ? path_parts.first : ""
            page.is_index = is_index

            if page.is_index
              if path_parts.size == 1
                page.url = "/"
              else
                parent = Path[relative_path].dirname
                page.url = "/#{parent}/"
              end
            else
              dir = Path[relative_path].dirname
              stem = Path[relative_path].stem
              if dir == "."
                page.url = "/#{stem}/"
              else
                page.url = "/#{dir}/#{stem}/"
              end
            end
          end
        end

        private def process_files_parallel(
          pages : Array(Schemas::Page),
          site : Schemas::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          cache : Cache
        ) : Int32
          config = ParallelConfig.new(enabled: true)
          processor = Parallel(Schemas::Page, Bool).new(config)

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
          pages : Array(Schemas::Page),
          site : Schemas::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool,
          cache : Cache
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
          page : Schemas::Page,
          site : Schemas::Site,
          templates : Hash(String, String),
          output_dir : String,
          minify : Bool
        )
          processed_content = process_shortcodes(page.raw_content, templates)

          html_content, toc_headers = Processor::Markdown.render(processed_content)

          toc_html = if page.toc && !toc_headers.empty?
                       generate_toc_html(toc_headers)
                     else
                       ""
                     end

          template_name = determine_template(page, templates)
          template_content = templates[template_name]? || templates["page"]?

          section_list_html = ""
          if template_name == "section" || page.template == "section"
            section_list_html = generate_section_list(page, site)
          end

          final_html = if template_content
                         full_template = resolve_includes(template_content, templates)
                         apply_template(full_template, html_content, page, site.config, section_list_html, toc_html, templates)
                       else
                         Logger.warn "  [WARN] No template found for #{page.path}. Using raw content."
                         html_content
                       end

          final_html = minify_html(final_html) if minify

          write_output(page, output_dir, final_html)
        end

        private def determine_template(page : Schemas::Page, templates : Hash(String, String)) : String
          if custom = page.template
            return custom if templates.has_key?(custom)
            Logger.warn "  [WARN] Custom template '#{custom}' not found for #{page.path}."
          end

          if page.is_index && !page.section.empty? && templates.has_key?("section")
            return "section"
          end

          "page"
        end

        private def generate_section_list(current_page : Schemas::Page, site : Schemas::Site) : String
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

        private def generate_toc_html(headers : Array(Schemas::TocHeader)) : String
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

        private def resolve_includes(content : String, templates : Hash(String, String), depth : Int32 = 0) : String
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

        private def apply_template(
          template : String,
          content : String,
          page : Schemas::Page,
          config : Schemas::Config,
          section_list : String,
          toc : String,
          templates : Hash(String, String)
        ) : String
          result = template
            .gsub(/<%=\s*page_title\s*%>/, page.title)
            .gsub(/<%=\s*page_section\s*%>/, page.section)
            .gsub(/<%=\s*section_list\s*%>/, section_list)
            .gsub(/<%=\s*toc\s*%>/, toc)
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

        private def write_output(page : Schemas::Page, output_dir : String, content : String)
          output_path = get_output_path(page, output_dir)

          FileUtils.mkdir_p(Path[output_path].dirname)
          File.write(output_path, content)
          Logger.action :create, output_path
        end



        private def generate_404_page(site : Schemas::Site, templates : Hash(String, String), output_dir : String, minify : Bool)
          return unless templates.has_key?("404")

          template = templates["404"]
          page = Schemas::Page.new("404.html")
          page.title = "404 Not Found"

          content = ""
          section_list = ""
          toc = ""

          full_template = resolve_includes(template, templates)
          final_html = apply_template(full_template, content, page, site.config, section_list, toc, templates)

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
