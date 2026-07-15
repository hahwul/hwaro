require "file_utils"
require "yaml"
require "toml"
require "../../config/options/export_options"
require "../../utils/file_safe"
require "../../utils/frontmatter_writer"
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

        # Parse frontmatter from content, returns {fields_hash, body}.
        #
        # The full parsed tree is preserved as `YAML::Any` values — nested
        # tables (`[extra]`, `[taxonomies]`), typed scalars, and non-string
        # arrays used to be flattened through a `String | Bool | Array(String)`
        # union and silently dropped from every export. Time values are
        # normalized to frontmatter date strings so downstream date logic can
        # treat `date` uniformly.
        #
        # Malformed frontmatter RAISES (surfacing as a per-file export error)
        # instead of exporting the file with all metadata stripped.
        protected def parse_content(content : String) : {Hash(String, YAML::Any), String}
          fields = {} of String => YAML::Any

          if match = content.match(TOML_FRONTMATTER_RE)
            body = content.sub(TOML_FRONTMATTER_RE, "").lstrip('\n')
            TOML.parse(match[1]).each do |key, value|
              fields[key] = Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(value)
            end
            return {fields, body}
          elsif match = content.match(YAML_FRONTMATTER_RE)
            yaml_data = YAML.parse(match[1])
            if h = yaml_data.as_h?
              body = content.sub(YAML_FRONTMATTER_RE, "").lstrip('\n')
              h.each do |key, value|
                k = key.as_s? || key.to_s
                fields[k] = normalize_scalar_times(value)
              end
              return {fields, body}
            elsif yaml_data.raw.nil?
              # Genuinely empty frontmatter block.
              return {fields, content.sub(YAML_FRONTMATTER_RE, "").lstrip('\n')}
            else
              # A leading `---` pair around non-mapping text is a horizontal
              # rule, not frontmatter — keep the whole document as body.
              return {fields, content}
            end
          end

          {fields, content}
        end

        # Recursively replace Time leaves with frontmatter date strings.
        private def normalize_scalar_times(value : YAML::Any) : YAML::Any
          raw = value.raw
          case raw
          when Time
            YAML::Any.new(Hwaro::Utils::FrontmatterWriter.serialize_time(raw))
          when Array
            YAML::Any.new(value.as_a.map { |v| normalize_scalar_times(v) })
          when Hash
            hash = {} of YAML::Any => YAML::Any
            value.as_h.each { |k, v| hash[k] = normalize_scalar_times(v) }
            YAML::Any.new(hash)
          else
            value
          end
        end

        # Write a file, creating parent directories as needed
        protected def write_file(path : String, content : String, verbose : Bool = false)
          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(path))
          File.write(path, content)
          Logger.debug "Exported: #{path}" if verbose
        end

        # Normalize a front-matter field that may be authored as either a list
        # (`tags: [a, b]`) or a single scalar (`tags: crystal`, `tags: 2024`)
        # into an array of strings, so shorthand isn't silently dropped on
        # export. Returns nil when the value is absent or empty.
        protected def string_list_field(value : YAML::Any?) : Array(String)?
          return unless value

          case raw = value.raw
          when Array
            strs = value.as_a.compact_map do |item|
              item.as_s? || begin
                item_raw = item.raw
                item_raw.is_a?(Hash) || item_raw.is_a?(Array) || item_raw.nil? ? nil : item_raw.to_s
              end
            end
            strs.empty? ? nil : strs
          when String
            raw.empty? ? nil : [raw]
          when Nil, Hash
            nil
          else
            [raw.to_s]
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
