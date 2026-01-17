require "yaml"
require "file_utils"
require "markd"

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

      count = 0
      Dir.glob("content/**/*.md") do |file_path|
        process_file(file_path)
        count += 1
      end

      elapsed = Time.instant - start_time
      puts "Build complete! Generated #{count} pages in #{elapsed.total_milliseconds.round(2)}ms."
    end

    private def process_file(file_path : String)
      raw_content = File.read(file_path)

      # Parse Front Matter and Markdown content
      # Checks for YAML block bounded by "---" at the start of the file
      front_matter = YAML::Any.new(Hash(YAML::Any, YAML::Any).new)
      markdown_content = raw_content

      # Regex to match Front Matter:
      # \A start of string
      # ---\s*\n start delimiter
      # (.*?\n?) non-greedy match for YAML content
      # ^---\s*$ end delimiter (multiline mode handles start of line)
      # \n? optional newline after delimiter
      # (.*)\z rest of file is content
      if match = raw_content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
        begin
          front_matter = YAML.parse(match[1])
        rescue ex
          puts "  [WARN] Invalid YAML in #{file_path}: #{ex.message}"
        end
        markdown_content = match[2]
      end

      # Convert Markdown to HTML
      html_content = Markd.to_html(markdown_content)

      # Extract metadata
      title = "Untitled"
      if front_matter.as_h? && front_matter["title"]?
        title = front_matter["title"].as_s? || "Untitled"
      end

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
