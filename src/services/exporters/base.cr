require "file_utils"
require "yaml"
require "toml"
require "../../config/options/export_options"
require "../../utils/file_safe"
require "../../utils/logger"

module Hwaro
  module Services
    module Exporters
      struct ExportResult
        property success : Bool
        property message : String
        property exported_count : Int32
        property skipped_count : Int32
        property error_count : Int32

        def initialize(
          @success : Bool = true,
          @message : String = "",
          @exported_count : Int32 = 0,
          @skipped_count : Int32 = 0,
          @error_count : Int32 = 0,
        )
        end
      end

      abstract class Base
        TOML_FRONTMATTER_RE = /\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?/m
        YAML_FRONTMATTER_RE = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

        abstract def run(options : Config::Options::ExportOptions) : ExportResult

        # Scan content directory for markdown files
        protected def scan_content_files(content_dir : String) : Array(String)
          files = [] of String
          return files unless Dir.exists?(content_dir)
          Dir.glob(File.join(content_dir, "**", "*.md")) { |f| files << f }
          Dir.glob(File.join(content_dir, "**", "*.markdown")) { |f| files << f }
          files.sort
        end

        # Parse frontmatter from content, returns {fields_hash, body}
        protected def parse_content(content : String) : {Hash(String, (String | Bool | Array(String))?), String}
          fields = {} of String => (String | Bool | Array(String))?

          if match = content.match(TOML_FRONTMATTER_RE)
            body = content.sub(TOML_FRONTMATTER_RE, "").lstrip('\n')
            begin
              toml_data = TOML.parse(match[1])
              toml_data.each do |key, value|
                raw = value.raw
                case raw
                when String  then fields[key] = raw
                when Bool    then fields[key] = raw
                when Int64   then fields[key] = raw.to_s
                when Float64 then fields[key] = raw.to_s
                when Time    then fields[key] = raw.to_s("%Y-%m-%dT%H:%M:%S%:z")
                when Array
                  arr = raw.compact_map { |item| item.as(TOML::Any).raw.as?(String) }
                  fields[key] = arr unless arr.empty?
                end
              end
            rescue TOML::ParseException
              # Malformed TOML front matter: surface no fields, keep body.
            end
            return {fields, body}
          elsif match = content.match(YAML_FRONTMATTER_RE)
            body = content.sub(YAML_FRONTMATTER_RE, "").lstrip('\n')
            begin
              yaml_data = YAML.parse(match[1])
              if h = yaml_data.as_h?
                h.each do |key, value|
                  k = key.as_s? || next
                  if s = value.as_s?
                    fields[k] = s
                  elsif b = value.as_bool?
                    fields[k] = b
                  elsif i = value.as_i?
                    fields[k] = i.to_s
                  elsif f = value.as_f?
                    fields[k] = f.to_s
                  elsif t = value.as_time?
                    fields[k] = t.to_s("%Y-%m-%dT%H:%M:%S%:z")
                  elsif arr = value.as_a?
                    strs = arr.compact_map(&.as_s?)
                    fields[k] = strs unless strs.empty?
                  end
                end
              end
            rescue YAML::ParseException
              # Malformed YAML front matter: surface no fields, keep body.
            end
            return {fields, body}
          end

          {fields, content}
        end

        # Write a file, creating parent directories as needed
        protected def write_file(path : String, content : String, verbose : Bool = false)
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(path))
          File.write(path, content)
          Logger.debug "Exported: #{path}" if verbose
        end

        # Normalize a front-matter field that may be authored as either a list
        # (`tags: [a, b]`) or a single scalar (`tags: crystal`) into an array,
        # so the scalar shorthand isn't silently dropped on export. Returns nil
        # when the value is absent or empty.
        protected def string_list_field(value : (String | Bool | Array(String))?) : Array(String)?
          case value
          when Array(String) then value.empty? ? nil : value
          when String        then value.empty? ? nil : [value]
          end
        end

        # Convert @/ internal links to relative paths
        protected def rewrite_internal_links(body : String) : String
          body.gsub(/\[([^\]]*)\]\(@\/([^\)]+)\)/) do |_, match|
            text = match[1]
            target = match[2]
            # Peel off any #anchor or ?query suffix *before* stripping the .md /
            # _index, otherwise `.md$` no longer anchors and links like
            # @/guide.md#sec or @/page.md?x=1 keep their .md and 404.
            suffix = ""
            if idx = target.index(/[#?]/)
              suffix = target[idx..]
              target = target[0...idx]
            end
            path = target.sub(/\.md$/, "").sub(/_index$/, "")
            "[#{text}](/#{path}#{suffix})"
          end
        end
      end
    end
  end
end
