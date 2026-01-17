require "markd"
require "yaml"
require "toml"

module Hwaro
  module Processor
    module Markdown
      extend self

      def render(content : String) : String
        Markd.to_html(content)
      end

      # Returns {title, content, draft, layout}
      def parse(raw_content : String, file_path : String = "") : Tuple(String, String, Bool, String?)?
        markdown_content = raw_content
        title = "Untitled"
        is_draft = false
        layout = nil

        # Try TOML Front Matter (+++)
        if match = raw_content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
          begin
            toml_fm = TOML.parse(match[1])
            title = toml_fm["title"]?.try(&.as_s) || title
            is_draft = toml_fm["draft"]?.try(&.as_bool) || false
            layout = toml_fm["layout"]?.try(&.as_s)
          rescue ex
            puts "  [WARN] Invalid TOML in #{file_path}: #{ex.message}" unless file_path.empty?
          end
          markdown_content = match[2]
        # Try YAML Front Matter (---)
        elsif match = raw_content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
          begin
            yaml_fm = YAML.parse(match[1])
            if yaml_fm.as_h?
              title = yaml_fm["title"]?.try(&.as_s?) || title
              is_draft = yaml_fm["draft"]?.try(&.as_bool?) || false
              layout = yaml_fm["layout"]?.try(&.as_s?)
            end
          rescue ex
            puts "  [WARN] Invalid YAML in #{file_path}: #{ex.message}" unless file_path.empty?
          end
          markdown_content = match[2]
        end

        {title, markdown_content, is_draft, layout}
      end
    end
  end
end
