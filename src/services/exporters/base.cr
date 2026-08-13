require "file_utils"
require "yaml"
require "toml"
require "../../config/options/export_options"
require "../../utils/errors"
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

        # Project directories that hold SOURCES, never export output. The
        # exporters write each file with a plain `File.write`, so a destination
        # that lands on one of these rewrites the project in place — front
        # matter re-serialized into the target's dialect, comment lines
        # dropped, `@/page.md` internal links flattened — with no backup and
        # exit 0. Matching is on the RESOLVED path, so a destination that
        # merely shares a prefix with one of these names (`-o contents`,
        # `-o static-site`) is unaffected.
        PROTECTED_SOURCE_DIRS = %w[content templates static data i18n themes archetypes .git]

        # Reject an export destination that isn't a safe place to write into.
        #
        # `hwaro build` has guarded its `-o` since it started wiping the
        # directory (`Phases::Initialize#guard_output_dir!`), but `tool export`
        # had no check at all: `hwaro tool export hugo -o .` resolved every
        # destination straight back onto the source file it had just read and
        # overwrote the whole of `content/`, reporting success.
        #
        # Unlike the build guard this one deliberately PERMITS a repository
        # root and a non-empty directory: exporting into a sibling checkout
        # (`-o ../my-hugo-site`) is the entire point of the command.
        def self.guard_output_dir!(output_dir : String, content_dir : String) : Nil
          # `-o ""` reaches `File.join` as an empty prefix, which leaves every
          # destination relative to the project root — the same in-place
          # rewrite as `-o .`. Normalize it so the checks below see it.
          requested = output_dir.strip.empty? ? "." : output_dir

          expanded = canonical_dir(requested)
          cwd = canonical_dir(Dir.current)
          content_root = canonical_dir(content_dir)

          reason =
            if expanded == File::SEPARATOR_STRING || Path[expanded].parent.to_s == expanded
              "the filesystem root"
            elsif expanded == canonical_dir(Path.home.to_s)
              "the home directory"
            elsif cwd == expanded || cwd.starts_with?(expanded + File::SEPARATOR)
              "the project directory (or a parent of it)"
            elsif expanded == content_root
              "the content directory (the exporter reads it as input)"
            elsif content_root.starts_with?(expanded + File::SEPARATOR)
              # The exporters build destinations as `<output>/content/<rel>`
              # (Hugo) or `<output>/<rel>` (Jekyll), so an output directory
              # that CONTAINS the content directory writes back over the very
              # files being exported. A destination merely nested inside the
              # content directory is not rejected here — with `-c .` that
              # would describe every in-project destination.
              "a parent of the content directory (the export would write back over it)"
            elsif File.basename(expanded) == ".git"
              "a git directory"
            elsif dir = protected_source_dir(expanded, cwd)
              "the project's #{dir.inspect} directory (hwaro reads it as build input)"
            end

          return unless reason

          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Refusing to use #{reason} as the export output directory: output_dir resolves to #{expanded.inspect}.",
            hint: "Point --output at a dedicated directory such as \"export\" (hwaro tool export hugo -o export)."
          )
        end

        # The project source directory `expanded` is, or lives inside, if any.
        # `expanded` arrives symlink-resolved, so the roots must be resolved
        # too: a project whose `static/` is itself a symlink (a shared asset
        # tree) would otherwise never match the lexical `<cwd>/static`.
        private def self.protected_source_dir(expanded : String, cwd : String) : String?
          PROTECTED_SOURCE_DIRS.find do |dir|
            root = canonical_dir(File.join(cwd, dir))
            expanded == root || expanded.starts_with?(root + File::SEPARATOR)
          end
        end

        # Absolute, comparison-ready form of a directory path. `expand_path`
        # resolves `.`/`..` but PRESERVES a trailing separator, so `content/`
        # and `content` must be normalized to the same string before the
        # prefix comparisons above can be trusted.
        #
        # `expand_path` is also purely LEXICAL — it never follows symlinks —
        # so every comparison above was decided on the spelling rather than
        # the destination: `ln -s . selfdir && hwaro tool export hugo -o
        # selfdir` read as a dedicated sibling directory, passed the guard,
        # and rewrote `content/` in place (YAML front matter replaced by TOML,
        # comment lines dropped, `@/g.md#i` links rewritten) — the exact
        # irreversible loss this guard exists to prevent. `ln -s content clink`
        # likewise slipped past the content-directory check. The build guard
        # already judges the RESOLVED destination; both guards must, or the
        # cheaper one is the way in.
        private def self.canonical_dir(path : String) : String
          expanded = Hwaro::Utils::PathUtils.resolved_real_path(File.expand_path(path))
          return expanded if expanded == File::SEPARATOR_STRING
          expanded.rstrip(File::SEPARATOR)
        end

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

        # Write a file, creating parent directories as needed.
        #
        # Every destination is re-checked against `output_dir` immediately
        # before the write. `ExportCommand` already refuses a dangerous
        # `--output` up front, but that guard only ever sees the directory the
        # user typed: the per-file destinations are string-joined from a
        # CONTENT-derived relative path (`<output>/content/<rel>` for Hugo,
        # `<output>/<rel>` for Jekyll), so a `..` surviving in that relative
        # path still resolves outside the export root no matter how safe the
        # `-o` was. This is the same containment check `copy_bundle_assets`
        # above and the build's own page writer already apply, and it is the
        # last line before `File.write` — an exporter cannot write outside its
        # destination whatever the caller passed.
        #
        # Returns false when the write was refused (`safe_output_path` has
        # already warned), so the caller reports the file as skipped instead
        # of counting a write that never happened.
        protected def write_file(path : String, content : String, output_dir : String, verbose : Bool = false) : Bool
          safe_path = Hwaro::Utils::OutputGuard.safe_output_path(path, output_dir)
          return false unless safe_path

          Hwaro::Utils::FileSafe.mkdir_p(File.dirname(safe_path))
          File.write(safe_path, content)
          Logger.debug "Exported: #{path}" if verbose
          true
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
