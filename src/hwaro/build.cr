require "yaml"
require "file_utils"
require "markd"
require "toml"

module Hwaro
  class Build
    def run
      puts "Building site..."
      start_time = Time.instant

      # Setup public directory
      if Dir.exists?("public")
        FileUtils.rm_rf("public")
      end
      FileUtils.mkdir_p("public")

      # Copy static files
      if Dir.exists?("static")
        FileUtils.cp_r("static/.", "public/")
        puts "  -> Copied static files"
      end

      # Load config
      config = Hash(String, TOML::Any).new
      if File.exists?("config.toml")
        config = TOML.parse_file("config.toml")
      end

      count = 0
      Dir.glob("content/**/*.md") do |file_path|
        process_file(file_path, config)
        count += 1
      end

      elapsed = Time.instant - start_time
      puts "Build complete! Generated #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
    end

    private def process_file(file_path : String, config : Hash(String, TOML::Any))
      raw_content = File.read(file_path)

      # Parse Front Matter and Markdown content
      markdown_content = raw_content
      title = "Untitled"

      # Try TOML Front Matter (+++)
      if match = raw_content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
        begin
          toml_fm = TOML.parse(match[1])
          if toml_fm["title"]?
            title = toml_fm["title"].as_s
          end
        rescue ex
          puts "  [WARN] Invalid TOML in #{file_path}: #{ex.message}"
        end
        markdown_content = match[2]
      # Try YAML Front Matter (---)
      elsif match = raw_content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
        begin
          yaml_fm = YAML.parse(match[1])
          if yaml_fm.as_h? && yaml_fm["title"]?
            title = yaml_fm["title"].as_s? || "Untitled"
          end
        rescue ex
          puts "  [WARN] Invalid YAML in #{file_path}: #{ex.message}"
        end
        markdown_content = match[2]
      end

      # Convert Markdown to HTML
      html_content = Markd.to_html(markdown_content)

      # Render Layout
      # Since we are a CLI tool, we simulate ECR runtime behavior for simple variables
      layout_path = "layouts/default.ecr"
      final_html = html_content

      if File.exists?(layout_path)
        layout = File.read(layout_path)

        # Simple substitution for supported variables
        # This matches the "simple template" requirement without a heavy engine
        final_html = layout
          .gsub(/<%=\s*page_title\s*%>/, title)
          .gsub(/<%=\s*content\s*%>/, html_content)
      else
        puts "  [WARN] Layout file not found: #{layout_path}. Using raw content."
      end

      # Calculate output path
      # content/subdir/page.md -> public/subdir/page.html
      relative_path = Path[file_path].relative_to("content")
      output_filename = relative_path.to_s.gsub(/\.md$/, ".html")
      output_path = Path["public", output_filename]

      # Write file
      FileUtils.mkdir_p(output_path.dirname)
      File.write(output_path, final_html)
      puts "  -> #{output_path}"
    end
  end
end
