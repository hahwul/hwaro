require "file_utils"
require "yaml"
require "json"
require "toml"
require "../content_lister"
require "../file_action"
require "../../models/config"
require "../../content/processors/fence_tracker"
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
            elsif Hwaro::Utils::PathUtils.within?(cwd, expanded)
              "the project directory (or a parent of it)"
            elsif expanded == content_root
              "the content directory (the exporter reads it as input)"
            elsif content_root != expanded && Hwaro::Utils::PathUtils.within?(content_root, expanded)
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
            Hwaro::Utils::PathUtils.within?(expanded, root)
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
          Hwaro::Utils::PathUtils.chomp_separator(Hwaro::Utils::PathUtils.resolved_real_path(File.expand_path(path)))
        end

        abstract def run(options : Config::Options::ExportOptions) : ExportResult

        # When set, the run resolves and reports every destination (counts,
        # manifest) but writes nothing to disk.
        property dry_run : Bool = false

        # Per-file manifest of this run, in write order. Unlike import, an
        # export OVERWRITES an existing destination by design (re-exporting
        # into the same directory is the normal refresh workflow) — the
        # manifest marks those rows `overwritten` so the caller can see
        # exactly which pre-existing files a run replaced.
        getter file_actions = [] of FileAction

        # Expanded paths a default build treats as drafts, including pages
        # under a section's `[cascade] draft = true` (ContentLister is the
        # publish-state source of truth). Filled by `load_draft_paths`.
        @draft_paths = Set(String).new

        protected def load_draft_paths(content_dir : String) : Nil
          @draft_paths = ContentLister.new(content_dir).draft_paths
        end

        # The page's own `draft = true`, or one cascaded from a section.
        protected def draft?(file_path : String, fields : Hash(String, YAML::Any)) : Bool
          fields["draft"]?.try(&.raw) == true || @draft_paths.includes?(File.expand_path(file_path))
        end

        # Scan content directory for markdown files
        protected def scan_content_files(content_dir : String) : Array(String)
          files = [] of String
          return files unless Dir.exists?(content_dir)
          project_root = Utils::PathUtils.find_project_root(content_dir)
          Dir.glob(File.join(content_dir, "**", "*.md")) do |file|
            next if File.symlink?(file) && !Utils::PathUtils.resolves_within?(file, project_root)
            files << file
          end
          Dir.glob(File.join(content_dir, "**", "*.markdown")) do |file|
            next if File.symlink?(file) && !Utils::PathUtils.resolves_within?(file, project_root)
            files << file
          end
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

        # `index.md`, `_index.md` and their translations: the pages whose
        # directory is a bundle (or section) with files of its own.
        INDEX_PAGE_RE = /\A_?index(?:\.[^.\/]+)?\.(?:md|markdown)\z/

        # Expanded directories of the index pages this run exported. A build
        # publishes a bundle's or section's files beside a page it renders,
        # so a skipped draft index leaves its files behind too.
        @exported_index_dirs = Set(String).new

        # Record an exported page that owns its directory's files. The
        # content root is never a bundle (`Page#collect_assets`).
        protected def note_exported_index(file_path : String, content_dir : String) : Nil
          return unless File.basename(file_path).matches?(INDEX_PAGE_RE)
          dir = File.expand_path(File.dirname(file_path))
          @exported_index_dirs << dir unless dir == File.expand_path(content_dir)
        end

        # Yields `{source, content-relative path, owning index directory}` for
        # every non-Markdown file under `content_dir` that a build publishes:
        #   - a file of a bundle or section whose index page this run
        #     exported — its nearest index directory owns it, as
        #     `Page#collect_assets` stops at nested bundles — filtered by
        #     `[content.files]` when that is configured;
        #   - anywhere, a `[content.files]` match or a raw `.json`/`.xml`
        #     file (`ReadContent#collect_content_paths`).
        # Only leaf-bundle siblings used to be exported, so a section's or the
        # root's published images were silently dropped. Symlinks are
        # skipped, as bundle copies always have been.
        protected def each_published_asset(content_dir : String, pages : Array(String), & : String, String, String? ->) : Nil
          root = File.expand_path(content_dir)
          index_dirs = pages.compact_map do |page|
            next unless File.basename(page).matches?(INDEX_PAGE_RE)
            dir = File.expand_path(File.dirname(page))
            dir unless dir == root
          end.to_set
          rules = content_files_rules(content_dir)

          Dir.glob(File.join(content_dir, "**", "*")).sort!.each do |src|
            info = File.info?(src, follow_symlinks: false)
            next unless info && info.file?
            next if ContentWalk.markdown?(src)

            relative = src.sub(content_dir, "").lstrip('/')
            owner = nil
            dir = File.dirname(File.expand_path(src))
            while dir.size > root.size
              if index_dirs.includes?(dir)
                owner = dir
                break
              end
              dir = File.dirname(dir)
            end

            ext = File.extname(src).downcase
            standalone = (rules.enabled? && rules.publish?(relative)) ||
                         ((ext == ".json" || ext == ".xml") && !rules.denied?(relative))
            bundled = !owner.nil? && @exported_index_dirs.includes?(owner) &&
                      (!rules.enabled? || rules.publish?(relative))
            yield src, relative, owner if standalone || bundled
          end
        end

        # Copy one content asset to `dest` through `write_file`'s guards.
        protected def copy_asset(src : String, dest : String, output_dir : String, verbose : Bool) : Nil
          write_file(dest, File.read(src), output_dir, verbose)
        rescue ex : File::Error
          Logger.warn "Could not export asset #{src}: #{ex.message}"
        end

        # The project's `[content.files]` rules: `config.toml` beside the
        # content directory, else the working directory's (ContentLister's
        # lookup). Defaults (disabled) when there is none or it won't load.
        private def content_files_rules(content_dir : String) : Models::ContentFilesConfig
          parent = File.dirname(content_dir.rstrip(File::SEPARATOR))
          path = {File.join(parent, "config.toml"), "config.toml"}.find { |candidate| File.exists?(candidate) }
          return Models::ContentFilesConfig.new unless path
          # The build owns config diagnostics; here they would only repeat.
          previous = Logger.level
          Logger.level = Logger::Level::Error
          begin
            Models::Config.load(path).content_files
          ensure
            Logger.level = previous
          end
        rescue Exception
          Models::ContentFilesConfig.new
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
            # A leading `---` pair around prose (a list, a scalar, text that
            # is not valid YAML) is a thematic break the build renders as
            # body — keep the whole document rather than failing the file.
            return {fields, content} unless Utils::FrontmatterScanner.yaml_front_matter?(match[1])
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
          elsif content.matches?(/\A\{\s*["}]/)
            # Match the build's JSON-intent rule so shortcodes, Jinja tags,
            # and Markdown attribute lists remain body text. The scanner's
            # offset is in bytes, including for Unicode frontmatter.
            end_idx = Utils::FrontmatterScanner.find_json_end(content)
            raise ArgumentError.new("Invalid JSON frontmatter: unbalanced braces") unless end_idx
            if json_fields = JSON.parse(content.byte_slice(0, end_idx)).as_h?
              json_fields.each do |key, value|
                fields[key] = json_to_yaml_any(value)
              end
            end
            return {fields, content.byte_slice(end_idx).lstrip('\n')}
          end

          {fields, content}
        end

        private def json_to_yaml_any(value : JSON::Any, depth : Int32 = 0) : YAML::Any
          Utils::Nesting.check!(depth)
          case raw = value.raw
          when Array
            YAML::Any.new(raw.map { |item| json_to_yaml_any(item, depth + 1) })
          when Hash
            hash = {} of YAML::Any => YAML::Any
            raw.each { |key, item| hash[YAML::Any.new(key)] = json_to_yaml_any(item, depth + 1) }
            YAML::Any.new(hash)
          else
            YAML::Any.new(raw)
          end
        end

        # Hoist a `[taxonomies]` table's entries to top-level front-matter
        # keys, the shape both Hugo and Jekyll actually read.
        #
        # Hwaro (like Zola) declares taxonomy membership as
        # `[taxonomies] tags = [...] categories = [...]`; neither target
        # understands that nesting, so passing the table through verbatim
        # meant EVERY tag and category silently became an opaque `taxonomies`
        # param — and re-importing the export dropped them entirely. A
        # top-level key already present wins, matching the build's own
        # precedence (`Processors::Markdown` only falls back to the table).
        protected def flatten_taxonomies(fields : Hash(String, YAML::Any)) : Hash(String, YAML::Any)
          table = fields["taxonomies"]?.try(&.as_h?)
          return fields unless table

          flattened = {} of String => YAML::Any
          fields.each do |key, value|
            next if key == "taxonomies"
            flattened[key] = value
          end

          table.each do |key, value|
            name = key.as_s? || key.to_s
            next if name.empty?
            existing = flattened[name]?
            # A declared-but-null key (`tags:` with no value) is NOT a
            # declaration that wins: the Hugo exporter drops null values
            # outright, so treating it as present lost the terms entirely.
            # An empty array loses too, matching the build's `tags.empty?`
            # fallback.
            next if existing && !existing.raw.nil? && !(existing.as_a?.try(&.empty?))
            flattened[name] = value
          end

          flattened
        end

        # Recursively replace Time leaves with frontmatter date strings.
        # `depth` guards a cyclic YAML::Any (self-referencing anchor in the
        # exported file's front matter); see `Utils::Nesting`.
        private def normalize_scalar_times(value : YAML::Any, depth : Int32 = 0) : YAML::Any
          Utils::Nesting.check!(depth)
          raw = value.raw
          case raw
          when Time
            YAML::Any.new(Hwaro::Utils::FrontmatterWriter.serialize_time(raw))
          when Array
            YAML::Any.new(value.as_a.map { |v| normalize_scalar_times(v, depth + 1) })
          when Hash
            hash = {} of YAML::Any => YAML::Any
            value.as_h.each { |k, v| hash[k] = normalize_scalar_times(v, depth + 1) }
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
        # `-o` was. This is the same containment check the build's own page
        # writer applies, and it is the last line before `File.write` — an
        # exporter cannot write outside its destination whatever the caller
        # passed. Content assets are copied through here too.
        #
        # Returns false when the write was refused (`safe_output_path` has
        # already warned), so the caller reports the file as skipped instead
        # of counting a write that never happened.
        protected def write_file(path : String, content : String, output_dir : String, verbose : Bool = false) : Bool
          safe_path = Hwaro::Utils::OutputGuard.safe_output_path(path, output_dir)
          return false unless safe_path

          # `safe_output_path` is lexical; `mkdir_p` + `File.write` follow a
          # pre-existing symlinked directory (or file) inside the destination,
          # routing the write outside `output_dir`. Re-check the RESOLVED
          # destination — deepest-existing-ancestor resolution, so a
          # not-yet-created path still resolves.
          resolved = Hwaro::Utils::PathUtils.resolved_real_path(safe_path)
          resolved_root = Hwaro::Utils::PathUtils.resolved_real_path(output_dir)
          unless Hwaro::Utils::PathUtils.within?(resolved, resolved_root)
            Logger.warn "Skipping output outside output directory (symlinked destination): #{path}"
            return false
          end

          action = File.exists?(safe_path) ? "overwritten" : "exported"
          unless @dry_run
            Hwaro::Utils::FileSafe.mkdir_p(File.dirname(safe_path))
            File.write(safe_path, content)
          end
          @file_actions << FileAction.new(safe_path, action)
          Logger.debug "#{@dry_run ? "Would export" : "Exported"}: #{path}" if verbose
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

        INTERNAL_LINK_RE = /\[([^\]]*)\]\(@\/([^\)]+)\)/

        # A reference-style link definition (`[ref]: @/posts/a.md "Title"`),
        # which the build resolves exactly like an inline link.
        REFERENCE_DEF_RE = /^( {0,3}\[[^\]]+\]:[ \t]*)@\/(\S+)/m

        # The `aliases` the build would actually publish, as strings, or nil
        # when the value is not an alias list at all. An absolute URL, a
        # protocol-relative `//host/…` or a traversing path is dropped with
        # the build's own warning — the build skips those, and passed through
        # they broke the target (Hugo refuses to build a site with an
        # `http*` alias; `../up` became a local redirect the source never had).
        protected def publishable_aliases(value : YAML::Any?, source : String) : Array(String)?
          aliases = string_list_field(value)
          return unless aliases
          aliases.reject do |a|
            next false unless reason = Hwaro::Utils::PathUtils.alias_refusal(a)
            Logger.warn "Skipping alias #{a.inspect} on #{source}: #{reason}."
            true
          end
        end

        # Convert @/ internal links to relative paths.
        #
        # The build resolves `@/` only in rendered link hrefs, so an `@/` link
        # shown inside a fenced/indented code block or an inline code span is
        # literal text there — and must stay literal here, or every exported
        # code sample documenting the syntax is silently rewritten. The
        # substitution still runs over the whole body (link text may wrap
        # across lines); matches that START inside code are kept verbatim.
        protected def rewrite_internal_links(body : String) : String
          return body unless body.includes?("@/")

          code = code_byte_ranges(body)
          body = body.gsub(INTERNAL_LINK_RE) do |whole, match|
            start = match.byte_begin(0)
            next whole if code.any?(&.includes?(start))
            "[#{match[1]}](#{rewrite_link_target(match[2])})"
          end
          return body unless body.includes?("@/")

          # Offsets moved with the inline rewrites, so re-measure the code.
          code = code_byte_ranges(body)
          body.gsub(REFERENCE_DEF_RE) do |whole, match|
            next whole if code.any?(&.includes?(match.byte_begin(0)))
            "#{match[1]}#{rewrite_link_target(match[2])}"
          end
        end

        # Byte ranges of `body` that Markdown renders as code: fenced and
        # indented code blocks (per the build's own FenceTracker) and inline
        # code spans — a backtick run closed by a run of the same length on
        # the same line.
        private def code_byte_ranges(body : String) : Array(Range(Int32, Int32))
          ranges = [] of Range(Int32, Int32)
          tracker = Content::Processors::FenceTracker.new
          offset = 0
          body.each_line(chomp: false) do |line|
            if tracker.fence_line?(line)
              ranges << (offset...(offset + line.bytesize))
            elsif line.includes?('`')
              each_code_span(line) { |from, to| ranges << ((offset + from)...(offset + to)) }
            end
            offset += line.bytesize
          end
          ranges
        end

        # Yields the [from, to) byte range of every inline code span in `line`.
        private def each_code_span(line : String, &) : Nil
          bytes = line.to_slice
          pos = 0
          while pos < bytes.size
            unless bytes[pos] == '`'.ord
              pos += 1
              next
            end
            run_start = pos
            while pos < bytes.size && bytes[pos] == '`'.ord
              pos += 1
            end
            run = pos - run_start
            # Look for a closing run of exactly the same length; an unmatched
            # run is literal backticks, and scanning resumes right after it.
            scan = pos
            while scan < bytes.size
              unless bytes[scan] == '`'.ord
                scan += 1
                next
              end
              close_start = scan
              while scan < bytes.size && bytes[scan] == '`'.ord
                scan += 1
              end
              if scan - close_start == run
                yield run_start, scan
                pos = scan
                break
              end
            end
          end
        end

        # The exported destination (plus any title) for an `@/` target.
        private def rewrite_link_target(target : String) : String
          # A link title (`[x](@/a.md "Title")`) follows the destination
          # after whitespace; left attached, it hid the `.md` from the
          # suffix strip below.
          title = ""
          if ws = target.index(/\s/)
            title = target[ws..]
            target = target[0...ws]
          end
          # Peel off any #anchor or ?query suffix *before* stripping the .md /
          # _index, otherwise `.md$` no longer anchors and links like
          # @/guide.md#sec or @/page.md?x=1 keep their .md and 404.
          suffix = ""
          if idx = target.index(/[#?]/)
            suffix = target[idx..]
            target = target[0...idx]
          end
          # A section `_index` and a page-bundle `index` both publish at
          # their directory's URL (`@/posts/my-post/index.md` →
          # `/posts/my-post/`), as the build resolves them.
          path = target.sub(/\.(?:md|markdown)$/, "").sub(/(\A|\/)_?index$/, "\\1")
          "/#{path}#{suffix}#{title}"
        end
      end
    end
  end
end
