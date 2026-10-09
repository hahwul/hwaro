require "file_utils"
require "json"
require "time"
require "../config/options/new_options"
require "../models/config"
require "../utils/date_utils"
require "../utils/errors"
require "../utils/file_safe"
require "../utils/frontmatter_writer"
require "../utils/logger"
require "../utils/path_utils"
require "../utils/text_utils"

module Hwaro
  module Services
    class Creator
      # Language codes a `<name>.<lang>.md` translation suffix may carry — the
      # site's declared ones, as the build reads them (see `page_name`).
      @language_codes = Set(String).new

      CONTENT_DIR    = "content"
      ARCHETYPES_DIR = "archetypes"

      # `<!-- hwaro: KEY[=VALUE], KEY[=VALUE] -->` directive that an
      # archetype can put on its very first line to declare metadata
      # hwaro should honour (and strip) before applying the template.
      # Keeping it an HTML comment means the archetype still parses
      # cleanly if hwaro isn't the one reading it.
      HWARO_DIRECTIVE_RE = /\A<!--\s*hwaro:\s*(.*?)\s*-->\s*\n?/

      # Keys accepted inside `<!-- hwaro: ... -->`. Anything else is
      # logged as a warning so typos (`bundlr=true`) surface instead of
      # silently becoming no-ops.
      KNOWN_DIRECTIVES = {"bundle"}

      # Validate a user-supplied `<path>` argument to `hwaro new` and
      # return a normalized form relative to `content/` (no prefix),
      # with `./`, `..`, and double-slash segments already collapsed.
      # The result is safe to pass straight into the existing Creator
      # resolution logic, which re-adds the `content/` prefix as needed.
      #
      # Raises `ArgumentError` when the input is empty, absolute, or
      # would resolve outside `content/`. Callers (the CLI) wrap the
      # failure in `HwaroError(HWARO_E_USAGE)` so the classified exit
      # code and `--json` payload match the rest of the tool.
      def self.validate_and_normalize_path!(raw : String) : String
        stripped = raw.strip
        if stripped.empty?
          raise ArgumentError.new("missing <path> argument")
        end

        if Utils::PathUtils.absolute?(stripped)
          raise ArgumentError.new(
            "Absolute path '#{raw}' is not allowed. " \
            "Paths are relative to #{CONTENT_DIR}/, e.g. 'posts/my-article.md'."
          )
        end

        full = Path[File.join(CONTENT_DIR, stripped)].normalize.to_s
        root_prefix = "#{CONTENT_DIR}#{File::SEPARATOR}"

        # The normalized path must sit strictly below content/ — equal
        # to the root is also a reject (no filename) and anything that
        # doesn't start with "content/" means `..` escaped the tree.
        unless full.starts_with?(root_prefix)
          raise ArgumentError.new(
            "Path '#{raw}' escapes the #{CONTENT_DIR}/ directory. " \
            "Use a path inside #{CONTENT_DIR}/, e.g. 'posts/my-article.md'."
          )
        end

        relative = full[root_prefix.size..]

        # Dot-leading segments (`.md`, `.hidden/foo.md`, `...`) are invisible
        # to the build: content discovery globs `content/**/*`, which skips
        # hidden entries. Creating one here would scaffold a page the site
        # then silently never renders — reject it up front instead.
        relative.split(PATH_SEP).each do |segment|
          if segment.starts_with?('.')
            raise ArgumentError.new(
              "Path '#{raw}' contains a hidden segment '#{segment}' (leading dot). " \
              "Hidden files are ignored by the build; use a name that does not start with '.'."
            )
          end
        end

        relative
      end

      # Path separator used by hwaro-managed content paths. Hwaro stores
      # and emits POSIX-style paths internally (the normalizer canonicalizes
      # to this), so URL-safety checks compare against '/' rather than
      # `File::SEPARATOR` to stay consistent on Windows hosts too.
      PATH_SEP = '/'

      # Return true when every segment of `path` is already URL-safe and
      # does not need auto-sanitization. "URL-safe" here means the segment
      # uses only the RFC 3986 unreserved ASCII set (`A-Z a-z 0-9 - . _ ~`)
      # plus CJK / Unicode letters, which static hosts serve without
      # percent-encoding surprises.
      def self.url_safe_path?(path : String) : Bool
        prev = PATH_SEP
        path.each_char do |char|
          unless char == PATH_SEP || url_safe_char?(char, prev)
            return false
          end
          prev = char
        end
        true
      end

      # Rewrite a path so every segment is URL-safe (see `url_safe_path?`).
      # Unsafe characters (spaces, `!@#$%^&*()`, etc.) are collapsed to a
      # single `-`; leading/trailing hyphens per segment are trimmed.
      # Segments that reduce to the empty string after sanitization are
      # dropped so the result never grows spurious `//` or leading-slash
      # artifacts.
      #
      # Preserves original casing — filesystems differ on case sensitivity,
      # and silently lowercasing could clobber existing content. Authors
      # who want an all-lowercase slug can pass one explicitly.
      #
      # Raises `ArgumentError` when every segment sanitizes away — the
      # caller (the CLI) wraps that into a classified usage error.
      def self.sanitize_url_path(path : String) : String
        return path if url_safe_path?(path)

        sanitized_segments = path.split(PATH_SEP).map { |seg| sanitize_url_segment(seg) }.reject(&.empty?)
        if sanitized_segments.empty?
          raise ArgumentError.new(
            "Path '#{path}' contains no URL-safe characters after sanitization. " \
            "Use ASCII letters/digits, CJK, or one of `- . _ ~` in at least one segment."
          )
        end
        sanitized_segments.join(PATH_SEP)
      end

      # Derive a filename-safe slug from a free-text title: lowercase, then
      # collapse every run of non-letter/non-digit Unicode characters to a
      # single hyphen and trim hyphens off the ends. Returns "" when the title
      # has no slug-able characters (the caller decides how to handle that).
      # Single source of truth for the title→filename mapping, shared by the
      # Creator's title-only fallback and the interactive `new` wizard's
      # recommended-path suggestion.
      def self.slugify(title : String) : String
        unless title.ascii_only?
          # Emoji variation selectors / keycap enclosure are not word marks.
          title = title.unicode_normalize(:nfc).gsub(/[\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}\x{20E3}]/, "-")
        end
        # Marks belong to the word they follow; one with no letter/digit before
        # it (the emoji variation selector after "❤") is a separator.
        title.downcase.gsub(/(?<![\p{L}\p{N}\p{M}])\p{M}+/, "-").gsub(/[^\p{L}\p{M}\p{N}]+/, "-").strip("-")
      end

      # Derive a display title from a filename stem (`my-first-post` ->
      # "My First Post"). Empty pieces are dropped so a stem carrying a
      # doubled or trailing hyphen (`emoji-`, `a---b`) cannot leak a
      # trailing/doubled space into `title = "..."`. A stem made only of
      # hyphens has no words to title-case, so it is kept verbatim rather
      # than collapsing to an empty title.
      # Single source of truth for the filename->title mapping used by every
      # `hwaro new` branch that infers a title from the path.
      def self.titleize(stem : String) : String
        words = stem.split("-").reject(&.empty?)
        return stem if words.empty?
        words.map(&.capitalize).join(" ")
      end

      # True when the build's front-matter date parser can produce a real
      # `Time` from `value`, so `hwaro new` fails fast on a `--date` the
      # build would silently drop (`2026-13-45`, `not-a-date`) or, worse,
      # emit as an unquoted-but-invalid TOML datetime that breaks parsing
      # of the whole generated file.
      def self.parseable_content_date?(value : String) : Bool
        !Utils::DateUtils.parse_content_date(value).nil?
      end

      private def self.sanitize_url_segment(segment : String) : String
        return segment if segment.empty?
        result = String.build(segment.bytesize) do |io|
          last_was_hyphen = false
          prev = PATH_SEP
          segment.each_char do |char|
            if url_safe_char?(char, prev)
              io << char unless char == '-' && last_was_hyphen
              # A literal `-` is URL-safe, but it still opens a hyphen run:
              # without this the run-collapse only saw the hyphens it
              # synthesized itself, so a literal hyphen sitting next to
              # unsafe characters emitted `a - b.md` -> `a---b.md` and
              # `emoji-<emoji>.md` -> `emoji-.md`. Treating both spellings as
              # the same run keeps the documented "collapsed to a single -"
              # contract and matches `.slugify`, which collapses hyphen runs
              # the same way.
              last_was_hyphen = (char == '-')
            else
              unless last_was_hyphen
                io << '-'
                last_was_hyphen = true
              end
            end
            prev = char
          end
        end.strip('-')
          # Drop hyphens that landed next to a dot — e.g. punctuation right
          # before an extension (`foo!.md` → `foo-.md`) leaves a dangling
          # hyphen that `strip('-')` cannot reach because the trailing char
          # is the extension, not the hyphen. Collapse both `-.` and `.-`.
          .gsub("-.", ".").gsub(".-", ".")

        # Collapsing hyphens against dots can synthesize a pure-dot segment
        # (`.>.` → `.-.` → `..`) — exactly the traversal shape the caller
        # validated away BEFORE sanitizing, so it would escape content/
        # unchecked. A segment left with only dots has no author-visible
        # name at all; drop it like any other empty segment.
        return "" if result.each_char.all? { |c| c == '.' }
        result
      end

      # `prev` is the character before `char`: a combining mark (Thai/Indic
      # vowel signs, virama) is part of the word only when it follows one.
      private def self.url_safe_char?(char : Char, prev : Char = PATH_SEP) : Bool
        return true if char.ascii_letter? || char.ascii_number?
        return true if char == '-' || char == '_' || char == '.' || char == '~'
        return true if Utils::TextUtils.cjk_char?(char)
        return true if !char.ascii? && char.letter?
        Utils::TextUtils.word_mark?(char) && (prev.alphanumeric? || Utils::TextUtils.word_mark?(prev))
      end

      def run(options : Config::Options::NewOptions, config : Models::Config? = nil)
        path = options.path
        @language_codes = language_codes(config)
        # Strip so a whitespace-only `--title "   "` falls back to deriving
        # the title from the filename instead of scaffolding `title = "   "`.
        title = (options.title || "").strip

        # Fail fast on a date the build cannot parse — otherwise the page is
        # created now and its date silently vanishes at build time.
        if raw_date = options.date
          unless Creator.parseable_content_date?(raw_date)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Invalid --date '#{raw_date}': not a date the build can parse.",
              hint: "Use YYYY-MM-DD, 'YYYY-MM-DD HH:MM:SS', ISO 8601 (2026-03-22T10:00:00), or RFC 3339 with offset.",
            )
          end
        end

        # --section overrides the base directory
        if section = resolve_section(options.section, path)
          if path && page_path?(path)
            filename = File.basename(path)
            full_path = File.join("content", section, filename)
          elsif path
            # When the path already carries the section dir (`new posts/foo
            # -s posts`), don't join it twice into `content/posts/posts/foo`.
            relative = path.starts_with?("#{section}/") ? path : File.join(section, path)
            full_path = File.join("content", relative)
            full_path += ".md" unless page_path?(full_path)
          else
            # No path given; title must be supplied via --title.
            full_path = nil
          end

          if full_path
            base_dir = File.dirname(full_path)
            if title.empty?
              title = default_title(full_path)
            end
          else
            base_dir = File.join("content", section)
          end
        else
          # Determine if path is a file path or directory
          is_file_path = path && page_path?(path)

          # When user types something like `posts/my-cool-post` (with a slash, no .md),
          # **and did not pass an explicit --section**, their clear intent is almost
          # always "create a post at /posts/my-cool-post/", not a nested directory.
          # Default to single-file mode unless they explicitly pass --bundle.
          # If the path contains a directory separator, the user is explicitly
          # specifying the on-disk location (e.g. posts/my-post or even when
          # they also passed a conflicting --section). Honor the path as the
          # target file location (flat) unless they explicitly asked for --bundle.
          # A trailing separator on the raw argument (`hwaro new notes/`) is an
          # explicit "this is a directory" signal, so it opts out of both flat
          # heuristics below and routes to the container branch instead.
          path_is_dir = options.path_is_dir

          user_intends_file_under_section = !path.nil? && !page_path?(path) &&
                                            path.includes?("/") && options.bundle != true &&
                                            !path_is_dir

          # A bare single-segment path (e.g. `hwaro new design-lab --title "..."`)
          # without --section and without forcing --bundle should also be treated
          # as the desired page stem (producing content/design-lab.md → /design-lab/).
          # However, if a directory named after the path already exists under content/
          # (e.g. content/news/ pre-created), treat the bare path as "target container dir"
          # and derive the filename from --title (preserves "new <dir> -t 'Name'" workflow).
          # Only --bundle (or config bundle=true) should interpret the bare path as
          # "the bundle directory name".
          target_dir_for_bare = path && (path.starts_with?("content/") ? path : File.join("content", path))
          bare_dir_exists = target_dir_for_bare ? Dir.exists?(target_dir_for_bare) : false
          user_intends_bare_flat = !path.nil? && !page_path?(path) &&
                                   !path.includes?("/") && options.bundle != true && options.section.nil? &&
                                   !bare_dir_exists && !path_is_dir

          # With explicit --no-bundle (or the section-path / bare-path heuristics above), treat the
          # provided path as the desired file location.
          is_no_bundle_flat = (!path.nil? && options.bundle == false && !page_path?(path)) || user_intends_file_under_section || user_intends_bare_flat

          if is_file_path && path
            # Honor the path the user typed. Previously a bare `foo.md`
            # got silently rerouted to `content/drafts/foo.md`, which
            # surprised users who didn't ask for drafts.
            #
            # Now: `hwaro new foo.md` lands at `content/foo.md`,
            # `hwaro new drafts/foo.md` still lands at `content/drafts/foo.md`
            # (and is_draft picks that up via the path-based heuristic below).

            full_path = path.starts_with?("content/") ? path : File.join("content", path)

            # Extract title from filename if not provided
            title = default_title(full_path) if title.empty?
            base_dir = File.dirname(full_path)
          elsif is_no_bundle_flat && path
            normalized = path.starts_with?("content/") ? path : File.join("content", path)
            full_path = "#{normalized}.md"
            base_dir = File.dirname(full_path)
            if title.empty?
              title = Creator.titleize(page_name(full_path))
            end
          else
            base_dir = path || "content/drafts"
            base_dir = "content/#{base_dir}" unless base_dir.starts_with?("content/")
            full_path = nil
            # `--bundle <dir-path>` means "the path IS the bundle directory",
            # so derive the title from its last segment exactly like the flat
            # heuristics above do. Without this, `hwaro new posts/foo --bundle`
            # demanded --title while the config-driven `bundle = true` derived
            # it — the explicit flag was strictly stricter than the default.
            if title.empty? && path && options.bundle == true
              title = Creator.titleize(File.basename(path))
            end
          end
        end

        # Require `--title` (or an explicit `<path>.md`) whenever the title
        # cannot be inferred. The `new` command is flag-only: no interactive
        # prompts, so behavior is predictable in TTY, CI, and agent runs.
        # When the user did pass a <path> but it has no `.md` suffix, the
        # message names that specifically — "missing --title or <path>.md"
        # was confusing because the user sees they already passed a path.
        if !full_path && title.empty?
          if raw_path = path
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "path '#{raw_path}' has no .md extension and --title is not set",
              hint: "Either append .md to the path (e.g. '#{raw_path}.md'), or pass --title to derive the filename from the title.",
            )
          else
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "missing --title (or <path>.md) argument",
              hint: "Pass --title, or give a path ending in .md (e.g. 'posts/my-post.md').",
            )
          end
        end

        if !full_path
          if title.empty?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Title cannot be empty.",
              hint: "Pass a non-empty --title.",
            )
          end
          slug = Creator.slugify(title)
          if slug.empty?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Title '#{title}' contains no filename-safe characters.",
              hint: "Use a --title with ASCII letters/digits or CJK characters, or pass an explicit <path>.md.",
            )
          end
          filename = slug + ".md"
          full_path = File.join(base_dir, filename)
        end

        # NOTE: the target directory is deliberately NOT created here. For a
        # dir-ish path (`hwaro new zz --bundle`) `base_dir` is already the
        # bundle directory at this point, so creating it up front left
        # `content/zz/` on disk even when the bundle was rejected below for
        # colliding with `content/zz.md` — an empty directory the user never
        # asked for, which then surfaces as a doctor finding. Every mkdir now
        # happens after the last validation, immediately before the write.

        # Draft: CLI flag > path-based detection. Match a path SEGMENT, not a
        # raw substring — `base_dir.includes?("drafts")` flagged unrelated dirs
        # like `content/draftsmanship` or `content/early-drafts-archive` as
        # drafts, silently publishing them as unpublished.
        is_draft = if options.draft.nil?
                     Path[base_dir].parts.includes?("drafts")
                   else
                     options.draft == true
                   end

        # Default to date-only (YYYY-MM-DD). This is what most authors want
        # for blog posts and pages. Users who need time can pass --date explicitly.
        # Full ISO with offset is still accepted if provided via --date.
        date = options.date || Time.local.to_s("%Y-%m-%d")
        tags = options.tags
        description = options.description

        # Find archetype, extracting any hwaro directives (e.g. bundle=true)
        # before substitution so they don't end up in generated content.
        raw_archetype_content = find_archetype(options.archetype, full_path)
        archetype_content, archetype_directives =
          extract_directives(raw_archetype_content)

        content_new = (config || Models::Config.new).content_new

        # Resolve bundle mode: CLI > archetype directive > config default.
        # The CLI form is an explicit tri-state (`Bool?`) so `--no-bundle`
        # really overrides rather than defaulting back.
        bundle_mode = options.bundle
        bundle_mode = archetype_directives["bundle"]?.try { |v| v == "true" } if bundle_mode.nil?
        bundle_mode = content_new.bundle if bundle_mode.nil?

        # Reshape `<dir>/<name>.md` → `<dir>/<name>/index.md` when bundle
        # mode is active. Skipped if the path is already an `index.md`
        # or `_index.md` so repeated invocations (and accidental bundle
        # mode on section indices) don't create `foo/index/index.md`.
        #
        # Special case: when the user gave a dir-ish path like `bundle-post`
        # or `posts/bundled` (no .md, no --section), the earlier directory-
        # fallback already appended a `<title-slug>.md` to it, producing
        # `content/<path>/<slug>.md`. Treating that as a regular `.md` and
        # then bundle-wrapping would stack an extra directory
        # (`content/<path>/<slug>/index.md`). The user's intent with
        # `--bundle` is "the path IS the bundle directory", so collapse the
        # slug layer and land at `<path>/index.md`.
        path_is_dir_bundle = bundle_mode &&
                             options.section.nil? &&
                             options.path.try { |p| !page_path?(p) } == true

        if bundle_mode && !bundle_path?(full_path)
          candidate = if path_is_dir_bundle
                        # For bare paths (no /) that resolve to bundle mode (via CLI, archetype, or config),
                        # the original path segment is the name of the bundle directory itself.
                        # Construct directly from it. This avoids broken collapse when the early
                        # flat-path heuristic (for default non-bundle) set full_path to content/xxx.md
                        # and File.dirname would incorrectly yield "content/index.md".
                        bare = options.path
                        if bare && bare.starts_with?("content/")
                          File.join(bare, "index.md")
                        elsif bare
                          File.join("content", bare, "index.md")
                        else
                          bundle_path_for(full_path)
                        end
                      else
                        bundle_path_for(full_path)
                      end
          if bundle_collides_with_sibling?(candidate)
            sibling = bundle_sibling_path(candidate)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_IO,
              message: "Cannot create bundle at #{candidate}: single-file sibling already exists.",
              hint: "Remove #{sibling}, or omit --bundle to append to the existing file location.",
            )
          end
          full_path = candidate
          base_dir = File.dirname(full_path)
        end

        content = if archetype_content
                    # An archetype supplies its own front matter verbatim, so
                    # `[content.new]`'s format/default_fields do not apply
                    # (CLI > archetype > config, as documented). Every built-in
                    # scaffold ships archetypes/default.md, so a configured
                    # `front_matter_format = "yaml"` would otherwise appear to
                    # do nothing at all with no explanation.
                    warn_archetype_overrides_content_new(content_new)
                    process_archetype(archetype_content, title, date, is_draft, tags, description)
                  else
                    generate_default_content(title, date, is_draft, tags, content_new, description)
                  end

        if File.exists?(full_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "File already exists: #{full_path}",
            hint: "Pass a different <path>, or edit the existing file directly.",
          )
        end

        # Refuse a page that would render to the same URL as an existing
        # one: `<name>.md`, `<name>/index.md` and `<name>/_index.md` (in any
        # page extension) all claim `/<name>/`, and the build then drops one
        # of them with only a warning.
        if sibling = url_sibling(full_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Cannot create #{full_path}: would collide with existing #{sibling} (both resolve to the same URL).",
            hint: "Pick a different <path>, or edit #{sibling} directly.",
          )
        end

        # Last step before the write, so a rejected create never leaves a
        # directory behind (see the note where the path is resolved).
        content_root = Utils::PathUtils.resolved_real_path(CONTENT_DIR)
        resolved_path = Utils::PathUtils.resolved_real_path(full_path)
        within_content = Utils::PathUtils.within?(resolved_path, content_root)
        if File.symlink?(full_path) || !within_content
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Cannot create #{full_path}: destination cannot be safely resolved within #{CONTENT_DIR}/.",
            hint: "Remove the symlink or choose a path that resolves within #{CONTENT_DIR}/.",
          )
        end

        ensure_dir!(base_dir)

        begin
          File.write(full_path, content)
        rescue ex : IO::Error
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Cannot write #{full_path}: #{ex.message}",
            hint: "Check write permissions and that the filename is valid for this filesystem.",
          )
        end
        Logger.outcome("created", full_path)
        full_path
      end

      # `mkdir -p` with the failure surfaced as a classified error. Without
      # this, a file squatting on a parent segment (`content/a.md` when
      # creating `a.md/child.md`) unwound as a bare exception — no error
      # code, exit taxonomy, or JSON payload in `--json` mode.
      private def ensure_dir!(dir : String) : Nil
        Hwaro::Utils::FileSafe.mkdir_p(dir) unless Dir.exists?(dir)
      rescue ex : IO::Error
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_IO,
          message: "Cannot create directory #{dir}: #{ex.message}",
          hint: "A file may already occupy one of the parent path segments, or you may lack write permission.",
        )
      end

      # Returns `{stripped_content, directives}`. When the archetype's first
      # line is `<!-- hwaro: k=v, k2=v2 -->`, that line is removed from the
      # content and the directives are returned as a hash. Shorthand keys
      # without `=VALUE` are treated as `k = "true"`. Unknown keys warn
      # (but don't fail) so typos surface instead of silently no-oping.
      private def extract_directives(content : String?) : {String?, Hash(String, String)}
        directives = {} of String => String
        return {nil, directives} unless content

        match = HWARO_DIRECTIVE_RE.match(content)
        return {content, directives} unless match

        match[1].split(",").each do |pair|
          k, _, v = pair.strip.partition("=")
          key = k.strip
          next if key.empty?
          unless KNOWN_DIRECTIVES.includes?(key)
            Logger.warn "Unknown hwaro directive '#{key}' in archetype; ignoring. Known keys: #{KNOWN_DIRECTIVES.to_a.sort.join(", ")}."
            next
          end
          directives[key] = v.strip.empty? ? "true" : v.strip
        end
        {content.sub(HWARO_DIRECTIVE_RE, ""), directives}
      end

      # `index.md` and `_index.md` are already "in bundle shape" — the
      # former is a page bundle's leaf file and the latter is a section
      # index. Wrapping either into `<name>/index.md` would be nonsense
      # (`posts/_index/index.md` creates a phantom section).
      private def bundle_path?(path : String) : Bool
        {"index", "_index"}.includes?(page_name(path))
      end

      # `posts/bund.ko.md` → `posts/bund/index.ko.md`: the translation of the
      # `bund` bundle, not a bundle named `bund.ko`.
      private def bundle_path_for(path : String) : String
        File.join(File.dirname(path), page_name(path), "index#{language_ext(path)}#{File.extname(path)}")
      end

      private def page_path?(path : String) : Bool
        Core::Build::Phases::ReadContent::PAGE_EXTENSIONS.includes?(File.extname(path))
      end

      private def page_stem(path : String) : String
        File.basename(path, File.extname(path))
      end

      # The site's declared language codes (default included) when it is
      # multilingual, else none: only then does the build read `.<lang>` as a
      # translation rather than part of the name (`v1.2.md`, `setup.mac.md`).
      private def language_codes(config : Models::Config?) : Set(String)
        codes = Set(String).new
        if config && config.multilingual?
          codes.concat(config.languages.keys)
          codes << config.default_language unless config.default_language.empty?
        end
        codes
      end

      # The language code of a `<name>.<lang>.md` translation, or nil.
      private def page_language(path : String) : String?
        Utils::PathUtils.language_suffix(page_stem(path)) { |code| @language_codes.includes?(code) }
      end

      # `.ko` for `hello.ko.md`, "" otherwise.
      private def language_ext(path : String) : String
        (lang = page_language(path)) ? ".#{lang}" : ""
      end

      # The file's name without extension or translation suffix: the page
      # name titles, bundle directories and URLs are built from.
      private def page_name(path : String) : String
        page_stem(path).rchop(language_ext(path))
      end

      # The title `hwaro new` derives for *full_path* (under `content/`):
      # the page name (see `page_name`), and for a bundle / section index
      # (`index` / `_index`) the containing directory's name. An index
      # directly under `content/` has no directory name to use and keeps
      # the stem.
      private def default_title(full_path : String) : String
        name = page_name(full_path)
        dir = File.dirname(full_path)
        if (name == "index" || name == "_index") && dir != CONTENT_DIR && dir != "."
          name = File.basename(dir)
        end
        Creator.titleize(name)
      end

      # An existing page file other than `full_path` that renders to the
      # same URL, if any.
      private def url_sibling(full_path : String) : String?
        stem = page_name(full_path)
        lang = language_ext(full_path)
        dir = File.dirname(full_path)
        page_dir = bundle_path?(full_path) ? dir : File.join(dir, stem)
        Core::Build::Phases::ReadContent::PAGE_EXTENSIONS.each do |ext|
          candidates = [File.join(page_dir, "index#{lang}#{ext}"), File.join(page_dir, "_index#{lang}#{ext}")]
          candidates << "#{page_dir}#{lang}#{ext}" unless page_dir == CONTENT_DIR
          candidates.each do |candidate|
            return candidate if candidate != full_path && File.file?(candidate)
          end
        end
        nil
      end

      # True when switching `<name>.md` to `<name>/index.md` would
      # collide with an existing single-file sibling on disk. Both would
      # render to the same URL, so we refuse rather than silently create
      # a duplicate.
      private def bundle_collides_with_sibling?(full_path : String) : Bool
        sibling_md = bundle_sibling_path(full_path)
        sibling_md != full_path && File.file?(sibling_md)
      end

      # `<dir>/<name>/index[.<lang>].md` → `<dir>/<name>[.<lang>].md`.
      private def bundle_sibling_path(bundle_file : String) : String
        bundle_file.sub(/\/index((?:\.[^.\/]+)?)\.md\z/) { "#{$1}.md" }
      end

      # Reconcile `-s section` with a path argument that already carries
      # a directory. Prior behaviour silently dropped the path's leading
      # directory and used the section — so `hwaro new posts/foo.md -s
      # docs` landed the file at `content/docs/foo.md` with no warning,
      # which made scripted flows and shell-completion surprise users.
      #
      # New behaviour: if the path's leading segment and the section
      # disagree, the path is authoritative (the user wrote the dir, so
      # respect it) and `--section` is dropped with a one-line warning.
      # When they match, or when the path lacks a directory entirely
      # (`-s docs foo.md`), the section is returned as-is.
      private def resolve_section(section : String?, path : String?) : String?
        return unless section
        return section unless path && path.includes?("/")

        first_segment = path.split("/").first
        return section if first_segment == section

        Logger.warn "  --section '#{section}' conflicts with directory '#{first_segment}/' in path '#{path}'; using the path and ignoring --section."
        nil
      end

      private def find_archetype(explicit_archetype : String?, path : String) : String?
        # 1. If explicit archetype is given, use it
        if explicit_archetype
          # Keep the archetype name inside archetypes/. `<path>` and `--section`
          # are already traversal-guarded; --archetype must be too, or it can
          # read arbitrary on-disk `.md` files (e.g. ../../etc/passwd.md).
          # Nested archetypes (tools/develop) stay allowed — only block `..`
          # and absolute paths.
          if explicit_archetype.includes?("..") || Utils::PathUtils.absolute?(explicit_archetype)
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Invalid archetype name: #{explicit_archetype}",
              hint: "Archetype names are relative to archetypes/; '..' and absolute paths are not allowed.",
            )
          end
          archetype_path = File.join(ARCHETYPES_DIR, "#{explicit_archetype}.md")
          if File.exists?(archetype_path)
            Logger.debug "Using archetype: #{archetype_path}"
            return File.read(archetype_path)
          else
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Archetype not found: #{archetype_path}",
              hint: "Run 'hwaro new --list-archetypes' to see archetypes available in this project.",
            )
          end
        end

        # 2. Try to find archetype based on path
        # Extract relative path from content/ directory
        relative_path = path.lchop("content/")
        dir_path = File.dirname(relative_path)

        if dir_path != "."
          # Try progressively shorter paths
          # e.g., tools/develop/mytool.md -> try tools/develop.md, then tools.md
          parts = dir_path.split("/")

          # Try from most specific to least specific
          parts.size.downto(1) do |i|
            archetype_name = parts[0...i].join("/")
            archetype_path = File.join(ARCHETYPES_DIR, "#{archetype_name}.md")

            if File.exists?(archetype_path)
              Logger.debug "Using archetype: #{archetype_path}"
              return File.read(archetype_path)
            end
          end
        end

        # 3. Try default archetype
        default_archetype = File.join(ARCHETYPES_DIR, "default.md")
        if File.exists?(default_archetype)
          Logger.debug "Using default archetype: #{default_archetype}"
          return File.read(default_archetype)
        end

        # 4. No archetype found
        nil
      end

      # Tell the author once, per invocation, that the archetype — not
      # `[content.new]` — decided the front matter. Every built-in scaffold
      # ships `archetypes/default.md`, so a configured
      # `front_matter_format = "yaml"` otherwise appears to do nothing with no
      # explanation. Compared against the built-in defaults so a project that
      # never configured `[content.new]` stays silent.
      private def warn_archetype_overrides_content_new(content_new : Models::ContentNewConfig)
        defaults = Models::ContentNewConfig.new
        return if content_new.front_matter_format == defaults.front_matter_format &&
                  content_new.default_fields == defaults.default_fields

        Logger.warn "  archetype front matter is used as-is; [content.new] front_matter_format/default_fields are not applied. Remove archetypes/default.md (or the matching archetype) to use the built-in template."
      end

      private def process_archetype(archetype_content : String, title : String, date : String, is_draft : Bool, tags : Array(String), description : String? = nil) : String
        # Archetypes wrap these placeholders in quoted TOML fields
        # (`title = "{{ title }}"`), so the substituted values must be escaped
        # the same way `tags` already is — otherwise a title/date containing a
        # double quote (e.g. `My "Quoted" Post`) yields invalid TOML and the
        # generated file fails to build.
        safe_title = escape_string(title)
        safe_date = escape_string(date)
        # An unset description substitutes to "" so an archetype that ships a
        # `description = "{{ description }}"` line still produces valid output.
        safe_description = escape_string(description || "")
        tags_str = tags.empty? ? "[]" : "[#{tags.map { |t| "\"#{escape_string(t)}\"" }.join(", ")}]"
        values = {
          "title"       => safe_title,
          "date"        => safe_date,
          "description" => safe_description,
          "draft"       => is_draft.to_s,
          "tags"        => tags_str,
        }
        # One pass over the archetype: chained `.gsub`s rescanned text an
        # earlier one had just inserted, so a title like "Using {{ tags }}"
        # was expanded again (injecting a raw array into a quoted string).
        # Only `{{ name }}` and `{{name}}` are placeholders.
        content = archetype_content.gsub(/\{\{(?: (title|date|description|draft|tags) |(title|date|description|draft|tags))\}\}/) do |_, match|
          values[match[1]? || match[2]]
        end

        content
      end

      # Built-in scaffold used when no archetype matches. Format and extra
      # fields are driven by `[content.new]` in `config.toml` so the output
      # matches the rest of the site's conventions (TOML by default to align
      # with the shipped scaffolds).
      private def generate_default_content(
        title : String,
        date : String,
        is_draft : Bool,
        tags : Array(String),
        content_new : Models::ContentNewConfig,
        description : String? = nil,
      ) : String
        # Map of extra-field name → value. Today only `description` carries a
        # value (supplied by the interactive `new` wizard); every other extra
        # field still scaffolds an empty placeholder. A provided description is
        # force-included even when the project's `default_fields` omitted it, so
        # the entered value is never silently dropped.
        field_values = {} of String => String
        extra_fields = content_new.extra_fields
        if d = description
          field_values["description"] = d
          extra_fields = ["description"] + extra_fields unless extra_fields.includes?("description")
        end

        if content_new.json?
          build_json_front_matter(title, date, is_draft, tags, extra_fields, field_values)
        elsif content_new.yaml?
          build_yaml_front_matter(title, date, is_draft, tags, extra_fields, field_values)
        else
          build_toml_front_matter(title, date, is_draft, tags, extra_fields, field_values)
        end
      end

      # TOML datetime literal pattern (local-date / local-datetime /
      # offset-datetime per the spec). When the value matches, emit unquoted
      # so the parser returns a real `Time`; otherwise fall back to a quoted
      # string so unusual `--date` inputs still produce valid TOML.
      TOML_DATETIME_RE = /\A\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?\z/

      # Body is intentionally empty after the front matter delimiter. Every
      # built-in scaffold's `page.html` / `post.html` renders the title as
      # `<h1>{{ page.title | e }}</h1>`, so injecting a markdown `# title`
      # here would produce two H1s on every page created via `hwaro new`
      # (gh#525).
      private def build_toml_front_matter(title : String, date : String, is_draft : Bool, tags : Array(String), extra_fields : Array(String), field_values : Hash(String, String) = {} of String => String) : String
        safe_title = escape_string(title)
        date_literal = date.matches?(TOML_DATETIME_RE) ? date : "\"#{escape_string(date)}\""
        String.build do |str|
          str << "+++\n"
          str << "title = \"#{safe_title}\"\n"
          str << "date = #{date_literal}\n"
          extra_fields.each { |f| str << "#{Utils::FrontmatterWriter.format_toml_key(f)} = \"#{escape_string(field_values[f]? || "")}\"\n" }
          str << "draft = true\n" if is_draft
          unless tags.empty?
            rendered = tags.map { |t| "\"#{escape_string(t)}\"" }.join(", ")
            str << "tags = [#{rendered}]\n"
          end
          str << "+++\n\n"
        end
      end

      private def build_yaml_front_matter(title : String, date : String, is_draft : Bool, tags : Array(String), extra_fields : Array(String), field_values : Hash(String, String) = {} of String => String) : String
        safe_title = escape_string(title)
        String.build do |str|
          str << "---\n"
          str << "title: \"#{safe_title}\"\n"
          # Quote+escape the date so an unusual --date (e.g. "2024: weird") is
          # valid YAML, and a normal date parses back as a String scalar (an
          # unquoted YYYY-MM-DD parses as a Time node and is silently dropped).
          str << "date: \"#{escape_string(date)}\"\n"
          extra_fields.each { |f| str << "#{Utils::FrontmatterWriter.yaml_scalar(f)}: \"#{escape_string(field_values[f]? || "")}\"\n" }
          str << "draft: true\n" if is_draft
          unless tags.empty?
            str << "tags:\n"
            tags.each { |tag| str << "  - \"#{escape_string(tag)}\"\n" }
          end
          str << "---\n\n"
        end
      end

      private def build_json_front_matter(title : String, date : String, is_draft : Bool, tags : Array(String), extra_fields : Array(String), field_values : Hash(String, String) = {} of String => String) : String
        fields = {} of String => JSON::Any
        fields["title"] = JSON::Any.new(title)
        fields["date"] = JSON::Any.new(date)
        extra_fields.each { |f| fields[f] = JSON::Any.new(field_values[f]? || "") }
        fields["draft"] = JSON::Any.new(true) if is_draft
        unless tags.empty?
          fields["tags"] = JSON::Any.new(tags.map { |t| JSON::Any.new(t) })
        end
        "#{JSON::Any.new(fields).to_pretty_json}\n\n"
      end

      private def escape_string(value : String) : String
        # Escape backslash FIRST, then quotes — otherwise a value like `C:\path`
        # or a trailing `\` produces invalid TOML/YAML basic strings (e.g. a
        # trailing `\"` escapes the closing quote).
        value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", " ")
      end
    end
  end
end
