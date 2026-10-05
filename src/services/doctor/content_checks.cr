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
      # don't enumerate the entire subtree. Extensions compare
      # case-insensitively, like `ReadContent`: a `*.{md,markdown}` glob
      # missed `Post.MD`, which the build publishes.
      private def dir_contains_markdown?(dir : String) : Bool
        Dir.glob(File.join(dir, "**", "*")) { |path| return true if ContentWalk.markdown?(path) }
        false
      end

      # Returns true if the directory contains markdown files anywhere
      # besides a direct top-level index page (page bundle), counting the
      # per-language spellings in `index_names`. This helps avoid noisy
      # warnings on documentation-style sites that organize guides as page
      # bundles rather than true sections.
      private def dir_has_markdown_in_subdirs?(dir : String, index_names : Set(String)) : Bool
        # Any markdown deeper than direct children of this dir?
        Dir.glob(File.join(dir, "*", "*")) { |path| return true if ContentWalk.markdown?(path) }

        # Any direct markdown file that is *not* an index page?
        Dir.glob(File.join(dir, "*")) do |path|
          next unless ContentWalk.markdown?(path)
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
      # against the declared codes. An upper-case extension is left on too:
      # `ReadContent` compares the basename against `index.md` verbatim, so
      # `index.MD` is an ordinary page, not an index.
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
      #
      # `templates` is the loader-name set from `check_templates`, nil when
      # there is no templates/ to check against — that is reported (as an
      # error) by the templates group already.
      private def check_content_frontmatter(issues : Array(Issue), config : Models::Config?, templates : Set(String)?)
        return unless Dir.exists?(@content_dir)

        # The same walk `tool validate`/`list`/`stats` use: extensions
        # compared case-insensitively like `ReadContent` (a lowercase-only
        # glob skipped `Post.MD`, so doctor reported a clean site the build
        # then failed on), and lstat-first so a symlink cycle
        # (`ln -s loop.md content/loop.md`) can't raise ELOOP out of the run.
        files = ContentWalk.find_content_files(@content_dir)
        return if files.empty?

        menus = MenuScope.new(config)

        per_file = Hwaro::Core::Build::ParallelHelper.map(files) do |path|
          scan_content_file_for_frontmatter(path, menus, templates)
        end
        per_file.each { |arr| arr.each { |i| issues << i } }
      end

      # `[[content.schema]]` violations, one error per violation.
      private def check_content_schema(issues : Array(Issue), config : Models::Config)
        Doctor.content_schema_results(@content_dir, config).each do |_, result|
          issues.concat(result.violations.map { |v| Doctor.schema_issue(v) })
        end
      end

      def self.schema_issue(v : Content::FrontMatterSchema::Violation) : Issue
        message = "field #{v.field.inspect}: #{v.message}"
        message = "line #{v.line}: #{message}" if v.line
        Issue.new(id: "content-schema-violation", level: :error, category: "content", file: v.file, message: message, line: v.line)
      end

      # The build's `[[content.schema]]` check over the regular pages a
      # default build publishes (ContentLister, plus `[[content.generate]]`
      # pages), with section cascades resolved by the build's own
      # `build_cascade_map` / `merged_cascade_for`. {file, result} per
      # checked page, in path order. Shared by doctor and `tool validate`.
      def self.content_schema_results(content_dir : String, config : Models::Config) : Array({String, Content::FrontMatterSchema::Result})
        results = [] of {String, Content::FrontMatterSchema::Result}
        return results if config.content_schema.empty? || !Dir.exists?(content_dir)

        # Re-parsing replays the build's front-matter warnings; those belong
        # to `hwaro build` (see PageRouteIndex).
        previous = Logger.level
        Logger.level = Logger::Level::Error
        begin
          menus = MenuScope.new(config)
          sections = [] of Models::Section
          pages = [] of {Models::Page, String, String, Hash(String, Models::ExtraValue), Bool}
          ContentLister.new(content_dir, GeneratedContent.infos(content_dir)).list_all.each do |info|
            generated = !info.generated_from.nil?
            relative = generated ? info.path : Path[info.path].relative_to(content_dir).to_s
            file = generated ? File.join(content_dir, info.path) : info.path
            source = generated ? (info.generated_source || next) : File.read(info.path)
            data = begin
              Processor::Markdown.parse(source, file)
            rescue Hwaro::HwaroError
              next # doctor's parse check and the build report it
            end

            # Section / language placement, as ReadContent assigns it.
            language = menus.filename_language(file)
            basename = File.basename(relative)
            ext = File.extname(basename)
            clean = language ? "#{basename.rchop(".#{language}#{ext}")}#{ext}" : basename
            parts = Path[relative].parts
            if clean == "_index#{ext}"
              section = Models::Section.new(relative)
              section.cascade = data[:cascade]
              section.language = language == config.default_language ? nil : language
              sections << section
              next
            end
            next unless info.published?
            page = Models::Page.new(relative)
            depth = clean == "index#{ext}" ? 2 : 1
            page.section = parts.size > depth ? parts[0..-(depth + 1)].join("/") : ""
            page.language = language == config.default_language ? nil : language
            pages << {page, file, source, data[:extra], generated}
          end

          builder = Core::Build::Builder.new
          cascade_map = builder.build_cascade_map(sections)
          taxonomies = Content::FrontMatterSchema.taxonomy_names(config)
          checked = Hwaro::Core::Build::ParallelHelper.map(pages.sort_by!(&.[1])) do |page, file, source, extra, generated|
            rule = Content::FrontMatterSchema.rule_for(config, page.section)
            cascade = builder.merged_cascade_for(page, cascade_map)
            {file, rule.try { |r| Content::FrontMatterSchema.check(r, file, source, extra, cascade, locate: !generated, taxonomies: taxonomies) }}
          end
          checked.each { |file, result| results << {file, result} if result }
        ensure
          Logger.level = previous
        end
        results
      end

      # Pages and sections that exist in the default language but not in
      # another configured one, and translations with no default-language
      # original. Pairing is the build's own: `Multilingual.link_translations!`
      # over the files a default build publishes (ContentLister, so drafts and
      # future/expired pages never count either way), with each file's
      # language read the way ReadContent reads it. Info only: a partial
      # translation is a normal state, not a defect `--strict` should fail on.
      private def check_translations(issues : Array(Issue), config : Models::Config)
        return unless config.multilingual? && Dir.exists?(@content_dir)

        default = config.default_language
        others = Content::Multilingual.ordered_language_codes(config) - [default]
        menus = MenuScope.new(config)
        entries = ContentLister.new(@content_dir).list_all.select(&.published?).sort_by!(&.path).map do |info|
          page = Models::Page.new(Path[info.path].relative_to(@content_dir).to_s)
          language = menus.filename_language(info.path)
          page.language = language == default ? nil : language
          {page, info.path}
        end
        Content::Multilingual.link_translations!(entries.map(&.[0]), config)

        # Grouped per language, in configured order.
        others.each do |other|
          entries.each do |page, file|
            code = Content::Multilingual.language_code(page, config)
            codes = page.translations.empty? ? [code] : page.translations.map(&.code)
            if code == default && !codes.includes?(other)
              issues << Issue.new(id: "translation-missing", level: :info, category: "i18n", file: file,
                message: "No '#{other}' translation", language: other)
            elsif code == other && !codes.includes?(default)
              issues << Issue.new(id: "translation-orphan", level: :info, category: "i18n", file: file,
                message: "'#{other}' translation has no '#{default}' original", language: other)
            end
          end
        end
      end

      # The `[[menus.*]]` names a page may register into, resolved per
      # language exactly like `Content::Menus.build_for_language`: a
      # `[languages.<code>]` block with its own `menus` table REPLACES the
      # global set for that language, one without inherits it. Checking every
      # page against the global names alone flagged a Korean page that
      # registers into `[[languages.ko.menus.footer]]` as undeclared, and let
      # a Korean page register into a global-only menu ko never renders.
      #
      # A language whose resolved set is empty is using front-matter-only,
      # ad-hoc menus (`Content::Menus` builds those regardless), so nothing
      # is checked for it.
      record MenuScope, config : Models::Config? do
        def default_language : String
          config.try(&.default_language) || ""
        end

        # The language code a file name carries, mirroring
        # `ReadContent#extract_language_from_filename`: only on a
        # multilingual site, and only a declared code (or the default).
        # nil otherwise — then the suffix is part of an ordinary page name.
        def filename_language(path : String) : String?
          cfg = config
          return unless cfg && cfg.multilingual?
          basename = File.basename(path)
          stem = basename[0, basename.size - File.extname(basename).size]
          idx = stem.rindex('.')
          return unless idx && idx > 0
          code = stem[(idx + 1)..]
          code if cfg.languages.has_key?(code) || code == default_language
        end

        # The language a page renders in.
        def language_for(path : String) : String
          filename_language(path) || default_language
        end

        # {names, the table spelling to cite in the message}.
        def names_for(language : String) : {Array(String), String}
          cfg = config
          return {[] of String, "menus"} unless cfg
          names, table = if lang_menus = cfg.language(language).try(&.menus)
                           {lang_menus.keys, "languages.#{language}.menus"}
                         else
                           {cfg.menus.keys, "menus"}
                         end
          # `[menus] auto_sections` declares its menu too.
          if (auto = cfg.menus_auto_sections) && !names.empty? && !names.includes?(auto)
            names += [auto]
          end
          {names, table}
        end
      end

      # Pure function: read + parse one markdown file, return any issue
      # produced as a small array. Fiber-safe because it touches no
      # shared state (`menus` and `templates` are read-only).
      private def scan_content_file_for_frontmatter(path : String, menus : MenuScope, templates : Set(String)?) : Array(Issue)
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
        unless data[:menus].empty?
          language = menus.language_for(path)
          known, table = menus.names_for(language)
          unless known.empty?
            data[:menus].each_key do |menu_name|
              next if known.includes?(menu_name)
              issues << Issue.new(id: "menu-undeclared", level: :warning, category: "content", file: path,
                message: "Front matter registers menu \"#{menu_name}\" but no [[#{table}.#{menu_name}]] is declared in config.toml (defined: #{known.sort.join(", ")})")
            end
          end
        end

        if templates
          check_template_reference(issues, path, "template", data[:template], templates,
            "the page renders with the default template instead")
          # `page_template` and `[cascade]` only mean something on a section
          # index; the build ignores them anywhere else.
          if section_index_file?(path, menus)
            check_template_reference(issues, path, "page_template", data[:page_template], templates,
              "pages in this section render with the page template instead")
            check_template_reference(issues, path, "cascade.template", data[:cascade]["template"]?.try(&.as?(String)), templates,
              "pages below this section render with the default template instead")
          end
        end
        issues
      end

      # A front matter template name with no matching file. The build
      # normalizes the extension away (`post.html` -> "post") and, on a miss,
      # falls back to the default with only a build-log warning — or, for
      # `page_template`, with no message at all.
      private def check_template_reference(issues : Array(Issue), path : String, key : String, value : String?, templates : Set(String), consequence : String)
        return unless value
        # An empty name (`template = ".html"`) is a miss for the build too.
        return if templates.includes?(value.sub(Core::Build::Builder::TEMPLATE_EXTENSION_REGEX, ""))
        issues << Issue.new(id: "content-template-missing", level: :warning, category: "content", file: path,
          message: "Front matter #{key} \"#{value}\" matches no file in #{@templates_dir}/ — #{consequence}")
      end

      # `_index.md` / `_index.<lang>.md`, as `ReadContent` classifies it
      # (the extension compared case-sensitively, like its basename check).
      private def section_index_file?(path : String, menus : MenuScope) : Bool
        stem = markdown_stem(File.basename(path))
        return true if stem == "_index"
        code = menus.filename_language(path)
        !code.nil? && stem == "_index.#{code}"
      end
    end
  end
end
