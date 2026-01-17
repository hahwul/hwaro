require "yaml"
require "file_utils"
require "markd"
require "toml"
require "../options/build_options"

module Hwaro
  module Core
    # Site configuration loaded from config.toml
    class SiteConfig
      property title : String
      property description : String
      property base_url : String
      property raw : Hash(String, TOML::Any)

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @raw = Hash(String, TOML::Any).new
      end

      def self.load(config_path : String = "config.toml") : SiteConfig
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s) || config.title
          config.description = config.raw["description"]?.try(&.as_s) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s) || config.base_url
        end
        config
      end
    end

    class Build
      @config : SiteConfig?
      @layout_content : String?

      def run(options : Options::BuildOptions)
        run(options.output_dir, options.drafts, options.minify, options.parallel)
      end

      def run(output_dir : String = "public", drafts : Bool = false, minify : Bool = false, parallel : Bool = true)
        puts "Building site..."
        start_time = Time.instant

        # Setup output directory
        setup_output_dir(output_dir)

        # Copy static files
        copy_static_files(output_dir)

        # Load config (cached)
        config = load_config

        # Load layout (cached)
        layout = load_layout

        # Collect all content files
        content_files = collect_content_files

        # Process files
        count = if parallel && content_files.size > 1
                  process_files_parallel(content_files, config, layout, output_dir, drafts, minify)
                else
                  process_files_sequential(content_files, config, layout, output_dir, drafts, minify)
                end

        elapsed = Time.instant - start_time
        puts "Build complete! Generated #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
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
          puts "  -> Copied static files"
        end
      end

      private def load_config : SiteConfig
        @config ||= SiteConfig.load
      end

      private def load_layout : String?
        layout_path = "layouts/default.ecr"
        @layout_content ||= File.exists?(layout_path) ? File.read(layout_path) : nil
      end

      private def collect_content_files : Array(String)
        files = [] of String
        Dir.glob("content/**/*.md") { |f| files << f }
        files
      end

      private def process_files_parallel(files : Array(String), config : SiteConfig, layout : String?, output_dir : String, drafts : Bool, minify : Bool) : Int32
        # Limit concurrency to prevent resource exhaustion
        max_workers = Math.min(files.size, System.cpu_count.to_i * 2)
        max_workers = Math.max(max_workers, 1)

        results = Channel(Bool).new(files.size)
        work_queue = Channel(String).new(files.size)

        # Queue all work
        files.each { |f| work_queue.send(f) }
        work_queue.close

        # Spawn limited number of workers
        max_workers.times do
          spawn do
            while file_path = work_queue.receive?
              result = process_file(file_path, config, layout, output_dir, drafts, minify)
              results.send(result)
            end
          end
        end

        count = 0
        files.size.times do
          count += 1 if results.receive
        end
        count
      end

      private def process_files_sequential(files : Array(String), config : SiteConfig, layout : String?, output_dir : String, drafts : Bool, minify : Bool) : Int32
        count = 0
        files.each do |file_path|
          count += 1 if process_file(file_path, config, layout, output_dir, drafts, minify)
        end
        count
      end

      private def process_file(file_path : String, config : SiteConfig, layout : String?, output_dir : String, include_drafts : Bool, minify : Bool) : Bool
        raw_content = File.read(file_path)

        # Parse Front Matter and Markdown content
        parsed = parse_front_matter(raw_content, file_path)
        return false if parsed.nil?

        title, markdown_content, is_draft = parsed

        if is_draft && !include_drafts
          return false
        end

        # Convert Markdown to HTML
        html_content = Markd.to_html(markdown_content)

        # Render with layout
        final_html = render_with_layout(html_content, title, config, layout)

        # Minify if requested
        if minify
          final_html = minify_html(final_html)
        end

        # Write output file
        write_output(file_path, output_dir, final_html)
        true
      end

      private def parse_front_matter(raw_content : String, file_path : String) : Tuple(String, String, Bool)?
        markdown_content = raw_content
        title = "Untitled"
        is_draft = false

        # Try TOML Front Matter (+++)
        if match = raw_content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
          begin
            toml_fm = TOML.parse(match[1])
            title = toml_fm["title"]?.try(&.as_s) || title
            is_draft = toml_fm["draft"]?.try(&.as_bool) || false
          rescue ex
            puts "  [WARN] Invalid TOML in #{file_path}: #{ex.message}"
          end
          markdown_content = match[2]
        # Try YAML Front Matter (---)
        elsif match = raw_content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
          begin
            yaml_fm = YAML.parse(match[1])
            if yaml_fm.as_h?
              title = yaml_fm["title"]?.try(&.as_s?) || title
              is_draft = yaml_fm["draft"]?.try(&.as_bool?) || false
            end
          rescue ex
            puts "  [WARN] Invalid YAML in #{file_path}: #{ex.message}"
          end
          markdown_content = match[2]
        end

        {title, markdown_content, is_draft}
      end

      private def render_with_layout(content : String, title : String, config : SiteConfig, layout : String?) : String
        if layout
          layout
            .gsub(/<%=\s*page_title\s*%>/, title)
            .gsub(/<%=\s*site_title\s*%>/, config.title)
            .gsub(/<%=\s*site_description\s*%>/, config.description)
            .gsub(/<%=\s*base_url\s*%>/, config.base_url)
            .gsub(/<%=\s*content\s*%>/, content)
        else
          puts "  [WARN] Layout file not found. Using raw content."
          content
        end
      end

      private def minify_html(html : String) : String
        html.gsub(/\n\s*/, "")
      end

      private def write_output(file_path : String, output_dir : String, content : String)
        relative_path = Path[file_path].relative_to("content")
        output_filename = relative_path.to_s.gsub(/\.md$/, ".html")
        output_path = Path[output_dir, output_filename]

        FileUtils.mkdir_p(output_path.dirname)
        File.write(output_path, content)
        puts "  -> #{output_path}"
      end
    end
  end
end
