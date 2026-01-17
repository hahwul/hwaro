require "file_utils"
require "toml"
require "../logger/logger"
require "../options/build_options"
require "../processor/markdown"

module Hwaro
  module Core
    # Site configuration loaded from config.toml
    class SiteConfig
      property title : String
      property description : String
      property base_url : String
      property sitemap : Bool
      property raw : Hash(String, TOML::Any)

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @sitemap = false
        @raw = Hash(String, TOML::Any).new
      end

      def self.load(config_path : String = "config.toml") : SiteConfig
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s) || config.title
          config.description = config.raw["description"]?.try(&.as_s) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s) || config.base_url
          config.sitemap = config.raw["sitemap"]?.try(&.as_bool) || config.sitemap
        end
        config
      end
    end

    class Page
      property title : String
      property content : String
      property raw_content : String
      property path : String       # Relative path from content/ (e.g. "projects/a.md")
      property section : String    # First directory component (e.g. "projects")
      property layout : String?    # Custom layout name
      property draft : Bool
      property url : String        # Calculated relative URL (e.g. "/projects/a/")
      property is_index : Bool     # Is this an index.md?
      property in_sitemap : Bool   # Include in sitemap.xml?

      def initialize(@path : String)
        @title = "Untitled"
        @content = ""
        @raw_content = ""
        @section = ""
        @draft = false
        @url = ""
        @is_index = false
        @in_sitemap = true
      end
    end

    class Build
      @config : SiteConfig?
      @templates : Hash(String, String)?
      @pages : Array(Page)?

      def run(options : Options::BuildOptions)
        run(options.output_dir, options.drafts, options.minify, options.parallel)
      end

      def run(output_dir : String = "public", drafts : Bool = false, minify : Bool = false, parallel : Bool = true)
        Logger.info "Building site..."
        start_time = Time.instant

        # Reset caches
        @config = nil
        @templates = nil
        @pages = nil

        # Setup output directory
        setup_output_dir(output_dir)

        # Copy static files
        copy_static_files(output_dir)

        # Load config (cached)
        config = load_config

        # Load templates (cached)
        templates = load_templates

        # Collect and parse all content files
        all_pages = collect_pages(config, drafts)
        @pages = all_pages

        Logger.info "  Found #{all_pages.size} pages."

        # Process files
        count = if parallel && all_pages.size > 1
                  process_files_parallel(all_pages, config, templates, output_dir, minify)
                else
                  process_files_sequential(all_pages, config, templates, output_dir, minify)
                end

        # Generate sitemap if enabled
        if config.sitemap
          generate_sitemap(all_pages, config, output_dir)
        end

        elapsed = Time.instant - start_time
        Logger.success "Build complete! Generated #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
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

      private def load_config : SiteConfig
        @config ||= SiteConfig.load
      end

      private def load_templates : Hash(String, String)
        return @templates.not_nil! if @templates

        templates = {} of String => String
        if Dir.exists?("templates")
          Dir.glob("templates/*.ecr") do |path|
            name = File.basename(path, ".ecr")
            templates[name] = File.read(path)
          end
        end

        # Ensure we have at least defaults if not provided
        unless templates.has_key?("page")
             # Fallback if user deleted page.ecr or it's an old project
             if templates.has_key?("default")
                 templates["page"] = templates["default"]
             end
        end

        @templates = templates
      end

      private def collect_pages(config : SiteConfig, include_drafts : Bool) : Array(Page)
        pages = [] of Page

        Dir.glob("content/**/*.md") do |file_path|
          relative_path = Path[file_path].relative_to("content").to_s
          raw_content = File.read(file_path)

          parsed = Processor::Markdown.parse(raw_content, file_path)
          next unless parsed

          title, markdown_content, draft, layout_name, in_sitemap = parsed

          if draft && !include_drafts
            next
          end

          page = Page.new(relative_path)
          page.title = title
          page.raw_content = markdown_content
          page.draft = draft
          page.layout = layout_name
          page.in_sitemap = in_sitemap

          # Calculate path metadata
          path_parts = Path[relative_path].parts
          page.section = path_parts.size > 1 ? path_parts.first : ""
          page.is_index = Path[relative_path].basename == "index.md"

          # Calculate URL
          if page.is_index
            if path_parts.size == 1 # root index.md
               page.url = "/"
            else
               # e.g. projects/index.md -> /projects/
               parent = Path[relative_path].dirname
               page.url = "/#{parent}/"
            end
          else
            # e.g. projects/a.md -> /projects/a/
            dir = Path[relative_path].dirname
            stem = Path[relative_path].stem
            if dir == "."
                page.url = "/#{stem}/"
            else
                page.url = "/#{dir}/#{stem}/"
            end
          end

          pages << page
        end

        pages
      end

      private def process_files_parallel(pages : Array(Page), config : SiteConfig, templates : Hash(String, String), output_dir : String, minify : Bool) : Int32
        cpu_count = System.cpu_count || 1
        max_workers = Math.min(pages.size, cpu_count.to_i * 2)
        max_workers = Math.max(max_workers, 1)

        results = Channel(Bool).new(pages.size)
        work_queue = Channel(Page).new(pages.size)

        pages.each { |p| work_queue.send(p) }
        work_queue.close

        max_workers.times do
          spawn do
            while page = work_queue.receive?
              render_page(page, config, templates, output_dir, minify)
              results.send(true)
            end
          end
        end

        count = 0
        pages.size.times do
          count += 1 if results.receive
        end
        count
      end

      private def process_files_sequential(pages : Array(Page), config : SiteConfig, templates : Hash(String, String), output_dir : String, minify : Bool) : Int32
        count = 0
        pages.each do |page|
          render_page(page, config, templates, output_dir, minify)
          count += 1
        end
        count
      end

      private def render_page(page : Page, config : SiteConfig, templates : Hash(String, String), output_dir : String, minify : Bool)
        # Convert Markdown
        html_content = Processor::Markdown.render(page.raw_content)

        # Select Template
        template_name = determine_template(page, templates)
        template_content = templates[template_name]? || templates["page"]?

        # Generate variables
        section_list_html = ""
        if template_name == "section" || page.layout == "section"
             section_list_html = generate_section_list(page, config)
        end

        # Render
        final_html = if template_content
                       full_template = resolve_includes(template_content, templates)
                       apply_template(full_template, html_content, page, config, section_list_html)
                     else
                       Logger.warn "  [WARN] No template found for #{page.path}. Using raw content."
                       html_content
                     end

        # Minify
        final_html = minify_html(final_html) if minify

        # Write
        write_output(page, output_dir, final_html)
      end

      private def determine_template(page : Page, templates : Hash(String, String)) : String
        # 1. Frontmatter layout
        if custom = page.layout
          return custom if templates.has_key?(custom)
          Logger.warn "  [WARN] Custom template '#{custom}' not found for #{page.path}."
        end

        # 2. Section template (for index pages in subdirectories)
        if page.is_index && !page.section.empty? && templates.has_key?("section")
          return "section"
        end

        # 3. Default page template
        "page"
      end

      private def generate_section_list(current_page : Page, config : SiteConfig) : String
        return "" unless @pages

        # Find pages in the same section, excluding the index itself
        # And usually we want direct children or recursive?
        # For now, let's just grab all pages with the same section string.

        section_pages = @pages.not_nil!.select do |p|
          p.section == current_page.section && !p.is_index
        end

        # Sort by title for now
        section_pages.sort_by! { |p| p.title }

        String.build do |str|
          section_pages.each do |p|
             full_url = "#{config.base_url}#{p.url}"
             str << "<li><a href=\"#{full_url}\">#{p.title}</a></li>\n"
          end
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

      private def apply_template(template : String, content : String, page : Page, config : SiteConfig, section_list : String) : String
        template
          .gsub(/<%=\s*page_title\s*%>/, page.title)
          .gsub(/<%=\s*page_section\s*%>/, page.section)
          .gsub(/<%=\s*section_list\s*%>/, section_list)
          .gsub(/<%=\s*site_title\s*%>/, config.title)
          .gsub(/<%=\s*site_description\s*%>/, config.description)
          .gsub(/<%=\s*base_url\s*%>/, config.base_url)
          .gsub(/<%=\s*content\s*%>/, content)
      end

      private def minify_html(html : String) : String
        html.gsub(/\n\s*/, "")
      end

      private def write_output(page : Page, output_dir : String, content : String)
        if page.is_index
             # content/projects/index.md -> public/projects/index.html
             # content/index.md -> public/index.html
             output_path = Path[output_dir, page.path].to_s.gsub(/\.md$/, ".html")
        else
             # content/projects/a.md -> public/projects/a/index.html
             clean_path = page.path.gsub(/\.md$/, "")
             output_path = Path[output_dir, clean_path, "index.html"].to_s
        end

        FileUtils.mkdir_p(Path[output_path].dirname)
        File.write(output_path, content)
        Logger.action :create, output_path
      end

      private def escape_xml(text : String) : String
        text.gsub(/[&<>"']/) do |match|
          case match
          when "&"  then "&amp;"
          when "<"  then "&lt;"
          when ">"  then "&gt;"
          when "\"" then "&quot;"
          when "'"  then "&apos;"
          else           match
          end
        end
      end

      private def generate_sitemap(pages : Array(Page), config : SiteConfig, output_dir : String)
        # Filter pages that should be included in sitemap
        sitemap_pages = pages.select { |p| p.in_sitemap }

        if sitemap_pages.empty?
          Logger.info "  No pages to include in sitemap."
          return
        end

        # Warn if base_url is empty
        if config.base_url.empty?
          Logger.warn "  [WARN] base_url is empty. Sitemap will contain relative URLs instead of absolute URLs."
        end

        xml_content = String.build do |str|
          str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          str << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"

          sitemap_pages.each do |page|
            # Properly join base_url and page.url
            base = config.base_url.rstrip('/')
            path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
            full_url = base.empty? ? path : base + path
            
            # Escape XML special characters
            escaped_url = escape_xml(full_url)
            
            str << "  <url>\n"
            str << "    <loc>#{escaped_url}</loc>\n"
            str << "  </url>\n"
          end

          str << "</urlset>\n"
        end

        sitemap_path = Path[output_dir, "sitemap.xml"].to_s
        File.write(sitemap_path, xml_content)
        Logger.action :create, sitemap_path
        Logger.info "  Generated sitemap with #{sitemap_pages.size} URLs."
      end
    end
  end
end
