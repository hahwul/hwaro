# Doctor — content/ structure and front matter diagnostics.
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Doctor
      # Recursively flag content directories that look like sections
      # but lack an `_index.md`. A directory is treated as a section
      # candidate when it contains at least one markdown file (anywhere
      # underneath it); directories that are pure attachment folders —
      # `images/`, `assets/`, etc. — are skipped automatically. Hidden
      # (`.`) and underscore-prefixed (`_`) directories are also skipped
      # so private/draft trees stay quiet. Issued at `:info` level so
      # CI doesn't gate on it.
      private def check_directory_structure(issues : Array(Issue), config : Models::Config?)
        unless Dir.exists?(@content_dir)
          # A site with no content directory builds zero pages. `hwaro
          # build` says so at the end of a run; doctor used to skip both
          # the structure walk and the front-matter scan in silence and
          # then report "no issues found — your site looks great".
          issues << Issue.new(id: "content-dir-missing", level: :warning, category: "content", file: @content_dir,
            message: "Content directory not found: #{@content_dir} — the build will produce no pages")
          return
        end

        # The per-language index spellings come from the config. Without
        # one, every `index.ko.md` reads as loose markdown and each
        # multilingual page bundle is reported as a broken section — the
        # false positive fixed below, reappearing whenever `config.toml`
        # fails to parse. Report nothing rather than report wrongly; the
        # board renders this check as skipped (`CheckSpec#blocked_by`).
        return unless config

        walk_section_dirs(@content_dir, issues, index_names(config))
      end

      # The base names that count as an index page for this site: always
      # `index`/`_index`, plus one language-suffixed spelling per declared
      # language (`index.ko`, `_index.zh-tw`, …) exactly as
      # `Phases::ReadContent#extract_language_from_filename` resolves them.
      #
      # Without the language variants a perfectly ordinary multilingual
      # page bundle (`index.md` + `index.ko.md`) looked like a section
      # holding loose markdown, so doctor reported "Section directory
      # missing _index.md" for it — reproduced on hwaro's own docs site.
      private def index_names(config : Models::Config?) : Set(String)
        names = Set{"index", "_index"}
        return names unless config && config.multilingual?

        codes = config.languages.keys.dup
        codes << config.default_language unless config.default_language.empty?
        codes.each do |code|
          next if code.empty?
          names << "index.#{code}"
          names << "_index.#{code}"
        end
        names
      end

      private def walk_section_dirs(root : String, issues : Array(Issue), index_names : Set(String))
        Dir.each_child(root) do |entry|
          next if entry.starts_with?(".") || entry.starts_with?("_")
          child = File.join(root, entry)
          # A symlinked directory can close a cycle (`ln -s .. content/x/y`),
          # and this walk follows it: `File.directory?` resolves the link, so
          # the recursion only stops when the kernel gives up at MAXSYMLINKS
          # and `File.info?` raises ELOOP — which used to escape the whole
          # doctor run, printing a raw filesystem error and zero diagnostics.
          # Skip, don't descend, exactly like Importers::Base#walk_files_into.
          # `Dir.glob` (used by the markdown probes below) never follows
          # symlinked directories either, so this keeps the two consistent.
          if File.symlink?(child)
            Logger.debug "Doctor: skipping symlinked content entry #{child}"
            next
          end
          next unless File.directory?(child)
          next unless dir_contains_markdown?(child)

          has_index = section_index?(child, index_names)

          # Many documentation sites use page bundles (index.md directly in
          # a folder) for individual guides rather than true sections with
          # _index.md. Only warn when the folder actually contains other
          # markdown content beneath it (suggesting it intends to be a section).
          has_nested_content = dir_has_markdown_in_subdirs?(child, index_names)

          if !has_index && has_nested_content
            relative = child.lchop(@content_dir).lchop(File::SEPARATOR)
            issues << Issue.new(id: "structure-missing-index", level: :info, category: "structure", file: child,
              message: "Section directory missing _index.md: #{relative}/")
          end

          walk_section_dirs(child, issues, index_names)
        end
      rescue ex : File::Error
        # Belt and braces: an unreadable (or concurrently removed) directory
        # must not take the whole doctor run down. This check is advisory
        # (`:info` level), so a missing sub-branch is far better than no
        # report at all.
        Logger.debug "Doctor: cannot walk #{root}: #{ex.message}"
      end

      # Quick "is there content under here?" check used to filter out
      # plain attachment directories. Returns on the first hit so we
      # don't enumerate the entire subtree.
      private def dir_contains_markdown?(dir : String) : Bool
        Dir.glob(File.join(dir, "**", "*.{md,markdown}")) { |_| return true }
        false
      end

      # Returns true if the directory contains markdown files anywhere
      # besides a direct top-level index page (page bundle), counting the
      # per-language spellings in `index_names`. This helps avoid noisy
      # warnings on documentation-style sites that organize guides as page
      # bundles rather than true sections.
      private def dir_has_markdown_in_subdirs?(dir : String, index_names : Set(String)) : Bool
        # Any markdown deeper than direct children of this dir?
        Dir.glob(File.join(dir, "*/*.{md,markdown}")) { |_| return true }

        # Any direct markdown file that is *not* an index page?
        Dir.glob(File.join(dir, "*.{md,markdown}")) do |path|
          return true unless index_names.includes?(markdown_stem(File.basename(path)))
        end

        false
      end

      # True when `dir` holds a section index (`_index.md`, or a declared
      # per-language spelling such as `_index.ko.md`).
      private def section_index?(dir : String, index_names : Set(String)) : Bool
        return true if File.exists?(File.join(dir, "_index.md")) ||
                       File.exists?(File.join(dir, "_index.markdown"))
        # Only a multilingual site has more spellings to look for, and only
        # then is the extra glob per directory worth paying for.
        return false if index_names.size <= 2

        Dir.glob(File.join(dir, "_index.*.{md,markdown}")) do |path|
          return true if index_names.includes?(markdown_stem(File.basename(path)))
        end
        false
      end

      # `index.ko.md` -> "index.ko". Only the markdown extension is
      # stripped; the language suffix is left on so the caller can match it
      # against the declared codes.
      private def markdown_stem(basename : String) : String
        if basename.ends_with?(".markdown")
          basename[0, basename.size - ".markdown".size]
        elsif basename.ends_with?(".md")
          basename[0, basename.size - ".md".size]
        else
          basename
        end
      end

      # Parse every markdown file's front matter so doctor flags what
      # would otherwise only surface at `hwaro build` time. Reuses the
      # canonical `Processor::Markdown.parse` so the check stays in
      # sync with the parser used by the build pipeline — any
      # front-matter shape the builder rejects as `HWARO_E_CONTENT`
      # appears here as an `:error` issue.
      #
      # Sites in the wild can have thousands of markdown files; this
      # used to scan them serially with a fresh `File.read` +
      # `Processor::Markdown.parse` per entry. Routed through the
      # existing `ParallelHelper.map` which already powers the build
      # pipeline so I/O overlaps and (on `-Dpreview_mt`) parsing
      # actually runs concurrently across cores. Each worker returns
      # the file's issue list (size 0 or 1) so we never share a
      # mutable issues array across fibers.
      private def check_content_frontmatter(issues : Array(Issue), config : Models::Config?)
        return unless Dir.exists?(@content_dir)

        files = [] of String
        Dir.glob(File.join(@content_dir, "**", "*.{md,markdown}")) do |path|
          # Skip things that aren't regular files (symlink to nowhere,
          # directory matching the glob, etc.). `File.file?` FOLLOWS
          # symlinks, so a link cycle (`ln -s loop.md content/loop.md`)
          # raised File::Error (ELOOP) out of the whole doctor run —
          # zero diagnostics, and no JSON payload under --json.
          # `ContentWalk.readable_file?` stats lstat-first, exactly like
          # the sibling `tool validate` walk.
          files << path if ContentWalk.readable_file?(path)
        end
        return if files.empty?

        # Only front matter `menus`/`menu` names get cross-checked against
        # `config.menus` — and only when the config declares at least one
        # menu at all. A site with NO `[[menus.*]]` anywhere is legitimately
        # using front-matter-only, fully ad-hoc menus (Content::Menus builds
        # them regardless of whether config declares that name), so nagging
        # about "undeclared" menus there would be a false positive on a
        # supported, legal setup.
        known_menu_names = config.try(&.menus.keys) || [] of String

        per_file = Hwaro::Core::Build::ParallelHelper.map(files) do |path|
          scan_content_file_for_frontmatter(path, known_menu_names)
        end
        per_file.each { |arr| arr.each { |i| issues << i } }
      end

      # Pure function: read + parse one markdown file, return any issue
      # produced as a small array. Fiber-safe because it touches no
      # shared state. `known_menu_names` is empty when config declares no
      # `[[menus.*]]` at all — see `check_content_frontmatter`.
      private def scan_content_file_for_frontmatter(path : String, known_menu_names : Array(String)) : Array(Issue)
        raw = begin
          File.read(path)
        rescue ex : IO::Error | File::Error
          return [Issue.new(id: "content-read-error", level: :error, category: "content", file: path,
            message: "Failed to read content file: #{ex.message}")]
        end

        data = begin
          Processor::Markdown.parse(raw, path)
        rescue ex : Hwaro::HwaroError
          first_line = (ex.message || "Invalid front matter").lines.first?.to_s.strip
          return [Issue.new(id: "content-frontmatter-invalid", level: :error, category: "content", file: path,
            message: first_line.empty? ? "Invalid front matter" : first_line)]
        rescue ex
          # A parse failure that isn't a classified HwaroError (invalid
          # UTF-8 raising ArgumentError out of the front-matter regex,
          # etc.) used to escape into ParallelHelper.map, whose
          # success-only filter silently dropped the file — doctor said
          # "no issues found" while `hwaro build` fails on the same file.
          first_line = (ex.message || "").lines.first?.to_s.strip
          detail = first_line.empty? ? ex.class.name : first_line
          return [Issue.new(id: "content-frontmatter-invalid", level: :error, category: "content", file: path,
            message: "Cannot parse content file (invalid encoding or front matter): #{detail}")]
        end

        issues = [] of Issue
        unless known_menu_names.empty?
          data[:menus].each_key do |menu_name|
            next if known_menu_names.includes?(menu_name)
            issues << Issue.new(id: "menu-undeclared", level: :warning, category: "content", file: path,
              message: "Front matter registers menu \"#{menu_name}\" but no [[menus.#{menu_name}]] is declared in config.toml (defined: #{known_menu_names.sort.join(", ")})")
          end
        end
        issues
      end
    end
  end
end
