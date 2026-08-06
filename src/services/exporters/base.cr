require "file_utils"
require "yaml"
require "toml"
require "../../config/options/export_options"
require "../../utils/file_safe"
require "../../utils/frontmatter_scanner"
require "../../utils/frontmatter_writer"
require "../../utils/logger"
require "../../utils/output_guard"
require "../../utils/path_utils"
require "../../utils/text_utils"

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
        TOML_FRONTMATTER_RE = Utils::FrontmatterScanner::TOML_FRONTMATTER_RE
        YAML_FRONTMATTER_RE = Utils::FrontmatterScanner::YAML_FRONTMATTER_RE

        abstract def run(options : Config::Options::ExportOptions) : ExportResult

        # Scan content directory for markdown files
        protected def scan_content_files(content_dir : String) : Array(String)
          files = [] of String
          return files unless Dir.exists?(content_dir)
          Dir.glob(File.join(content_dir, "**", "*.md")) { |f| files << f }
          Dir.glob(File.join(content_dir, "**", "*.markdown")) { |f| files << f }
          files.sort
        end

        # Read a content file for export, stripping a UTF-8 BOM. A leading
        # U+FEFF defeats the `\A---` / `\A+++` anchors below, which silently
        # produced an empty frontmatter block with the whole document — raw
        # fences and all — dumped into the body, and (having lost `date`)
        # misfiled posts as pages. `hwaro build` already strips it via
        # `TextUtils.strip_bom`, so such a file builds fine and only breaks
        # on export.
        protected def read_content(path : String) : String
          Hwaro::Utils::TextUtils.strip_bom(File.read(path))
        end

        # Copy a page bundle's co-located assets — every non-Markdown sibling
        # of the bundle's `index.md` — into the bundle's export directory.
        # The exporter preserves the bundle layout, so without this every
        # `![](cover.png)` in the exported post points at a file that was
        # never written. Symlinks are skipped and every destination is
        # re-checked against `output_dir`.
        protected def copy_bundle_assets(source_dir : String, dest_dir : String, output_dir : String, verbose : Bool = false) : Int32
          return 0 unless Dir.exists?(source_dir)
          return 0 unless Hwaro::Utils::OutputGuard.within_output_dir?(dest_dir, output_dir)
          # `within_output_dir?` is lexical. If the destination directory —
          # or any ancestor — is a symlink out of the tree, `Dir.exists?`
          # follows it and `File.copy` would write straight through it.
          return 0 unless Hwaro::Utils::PathUtils.resolves_within?(dest_dir, output_dir)

          copied = 0
          Dir.children(source_dir).sort!.each do |entry|
            src = File.join(source_dir, entry)
            next if File.directory?(src) || File.symlink?(src)
            next if entry.ends_with?(".md") || entry.ends_with?(".markdown")

            dest = File.join(dest_dir, entry)
            next unless Hwaro::Utils::OutputGuard.within_output_dir?(dest, output_dir)

            Hwaro::Utils::FileSafe.mkdir_p(dest_dir) unless Dir.exists?(dest_dir)
            File.copy(src, dest)
            Logger.debug "Exported bundle asset: #{dest}" if verbose
            copied += 1
          rescue ex
            Logger.warn "Could not export bundle asset #{src}: #{ex.message}"
          end
          copied
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
