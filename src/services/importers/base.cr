require "file_utils"
require "json"
require "set"
require "../file_action"
require "../../config/options/import_options"
require "../../utils/date_utils"
require "../../utils/file_safe"
require "../../utils/frontmatter_writer"
require "../../utils/logger"
require "../../utils/text_utils"
require "../../utils/path_utils"
require "../../utils/output_guard"

module Hwaro
  module Services
    module Importers
      # Value union for the normalized frontmatter each importer builds before
      # `generate_frontmatter` renders it as TOML.
      alias FieldValue = (String | Bool | Int64 | Array(String))?

      # Every importer computes `success: imported > 0 || errors == 0` —
      # DELIBERATELY more lenient than the exporters' `errors == 0` rule.
      # Imports digest messy third-party dumps where some items are simply
      # unimportable; a best-effort partial migration is the expected
      # outcome, and per-item failures are counted and reported alongside
      # it. Exports and conversions operate on the user's own valid content,
      # where any error means the run must fail.
      struct ImportResult
        property success : Bool
        property message : String
        property imported_count : Int32
        property skipped_count : Int32
        property error_count : Int32

        def initialize(
          @success : Bool = true,
          @message : String = "",
          @imported_count : Int32 = 0,
          @skipped_count : Int32 = 0,
          @error_count : Int32 = 0,
        )
        end
      end

      abstract class Base
        abstract def run(options : Config::Options::ImportOptions) : ImportResult

        # When set, the run resolves and reports every destination (counts,
        # manifest, collision renames) but writes nothing to disk.
        property dry_run : Bool = false

        # Per-file manifest of this run, in write order.
        getter file_actions = [] of FileAction

        # Regex matching YAML frontmatter: opening `---` on the first line and a
        # closing `---` on its own line (multiline mode so ^ matches line starts).
        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        # Read a content file for import, stripping a UTF-8 BOM and
        # normalizing CRLF line endings. Windows-authored sources (or
        # `core.autocrlf=true` checkouts) would otherwise defeat the
        # `\n`-anchored frontmatter regexes, silently dropping every field and
        # leaking raw YAML into the page body. A leading U+FEFF does the same
        # to the `\A---` / `\A+++` anchors — every other reader hwaro hands
        # file text to already goes through `TextUtils.strip_bom`.
        #
        # `scrub` because sources are third-party exports: a single invalid
        # UTF-8 byte made every downstream regex pass raise ArgumentError,
        # dropping the whole file with a cryptic error. This is the single
        # choke point, so scrubbing here protects every importer.
        protected def read_text(path : String) : String
          Utils::TextUtils.strip_bom(File.read(path).scrub).gsub("\r\n", "\n")
        end

        # Split YAML frontmatter from a document body. Returns {frontmatter, body}
        # with both stripped, or {nil, ...} when no frontmatter is present — an
        # empty or whitespace-only block (`---\n---`) counts as absent, since
        # `YAML.parse("")` yields a nil document whose `[]?` raises.
        protected def split_yaml_frontmatter(content : String) : {String?, String}
          if match = YAML_FM_REGEX.match(content)
            fm = match[1].strip
            return {fm.empty? ? nil : fm, match[2].strip}
          end
          {nil, content.strip}
        end

        # Recursively collect files under `dir` whose name ends with one of
        # `extensions`. `skip_dir`, when given, receives each subdirectory's
        # basename and skips recursion into it when it returns true.
        #
        # Entries are walked in sorted order. `Dir.each_child` yields in
        # filesystem order, which varies by platform and by directory history
        # — and since destination collisions are resolved in walk order, an
        # unsorted walk made *which* file got the `-1` suffix differ between
        # machines for the same source tree.
        protected def walk_files(dir : String, extensions : Array(String) = [".md", ".markdown"], skip_dir : Proc(String, Bool)? = nil) : Array(String)
          files = [] of String
          walk_files_into(dir, files, extensions, skip_dir)
          files
        end

        private def walk_files_into(dir : String, files : Array(String), extensions : Array(String), skip_dir : Proc(String, Bool)?)
          # An unreadable subdirectory (permissions, or one removed mid-walk)
          # raised straight out of the recursion and aborted the entire
          # import. Skip it and keep importing everything that is readable.
          entries = begin
            Dir.children(dir).sort!
          rescue ex : File::Error
            Logger.warn "Skipped unreadable directory: #{dir} (#{ex.message})"
            return
          end

          entries.each do |entry|
            full_path = File.join(dir, entry)
            if File.directory?(full_path)
              # A symlinked directory can close a cycle (`ln -s .. sub`), and
              # following it raises ELOOP straight out of this walk — killing
              # the whole import before a single file is read. It can also
              # point outside the source tree entirely. Skip, don't descend.
              if File.symlink?(full_path)
                Logger.warn "Skipped symlinked directory: #{full_path}"
                next
              end
              next if skip_dir && skip_dir.call(entry)
              walk_files_into(full_path, files, extensions, skip_dir)
            elsif extensions.any? { |ext| entry.ends_with?(ext) }
              files << full_path
            end
          end
        end

        # Split a file's path (relative to base_path) into {section, filename},
        # where section is the parent-directory chain joined with "/" (or
        # `default` for a top-level file) and filename is the last path segment.
        protected def section_from_path(file_path : String, base_path : String, default : String) : {String, String}
          relative = file_path.sub(base_path, "").lstrip('/')
          parts = relative.split("/")
          if parts.size > 1
            {parts[0..-2].join("/"), parts.last}
          else
            {default, parts.first}
          end
        end

        # The top-level section (first path segment) for a file relative to
        # base_path, or `default` for a top-level file.
        protected def top_section_from_path(file_path : String, base_path : String, default : String = "posts") : String
          relative = file_path.sub(base_path, "").lstrip('/')
          parts = relative.split("/")
          parts.size > 1 ? parts[0] : default
        end

        # Generate TOML frontmatter string from fields hash. Strings go
        # through the shared TOML escaper — Crystal's `String#inspect` emits
        # escapes TOML rejects (`\a`, `\e`, `\v`, and `\uXXXX` sequences that
        # toml.cr misreads before a hex digit), which made the imported file
        # break the user's own build.
        protected def generate_frontmatter(fields : Hash(String, FieldValue)) : String
          lines = [] of String
          lines << "+++"

          fields.each do |key, value|
            k = Hwaro::Utils::FrontmatterWriter.format_toml_key(key)
            case value
            when Nil
              next
            when Bool, Int64
              lines << "#{k} = #{value}"
            when String
              next if value.empty?
              lines << "#{k} = \"#{Hwaro::Utils::FrontmatterWriter.escape_toml_string(value)}\""
            when Array(String)
              next if value.empty?
              formatted = value.map { |v| "\"#{Hwaro::Utils::FrontmatterWriter.escape_toml_string(v)}\"" }.join(", ")
              lines << "#{k} = [#{formatted}]"
            end
          end

          lines << "+++"
          lines.join("\n")
        end

        # Convert title to a URL-safe slug
        protected def slugify(title : String) : String
          Utils::TextUtils.slugify(title)
        end

        # If the imported body's first non-blank line is an H1 matching the
        # front-matter title, drop it. Hwaro page templates render
        # `<h1>{{ page.title }}</h1>` themselves, so keeping the body H1
        # produces two H1 elements on the same page — same problem that
        # gh#525 fixed for `hwaro new`. Importers from Hugo/Jekyll/Obsidian
        # all hit this because those engines typically render the title from
        # the body H1 rather than from front matter.
        protected def strip_redundant_title_h1(body : String, title : String?) : String
          return body if title.nil? || title.empty?
          # Match `# Title`, ATX-style only — setext H1 (`=====` underline)
          # is rare in imported content and ambiguous to detect without a
          # second-line peek. Authors using setext can clean up by hand.
          normalized_title = title.strip
          # `chomp: false` keeps the trailing `\n` on each line so joining
          # afterwards reproduces the original byte sequence exactly — the
          # default behavior strips newlines and would smash paragraphs
          # together when we rejoin.
          lines = body.lines(chomp: false)
          # Skip leading blank lines so a body that begins with `\n# Title` works.
          idx = 0
          while idx < lines.size && lines[idx].strip.empty?
            idx += 1
          end
          return body if idx >= lines.size

          first = lines[idx]
          if match = first.match(/\A#\s+(.+?)\s*#*\s*\z/)
            return body if match[1].strip != normalized_title
            # Drop the H1 line and exactly one trailing blank line if present,
            # so the body doesn't gain a leading blank gap.
            lines.delete_at(idx)
            lines.delete_at(idx) if idx < lines.size && lines[idx].strip.empty?
            return lines.join
          end
          body
        end

        # Destinations already claimed by this importer instance. Two source
        # files can normalize to one destination (a stripped `YYYY-MM-DD-`
        # prefix, a duplicate `slug`, two same-titled notes, two collection
        # subfolders flattened into one section) — without this the second
        # one was silently dropped, or silently CLOBBERED under `--force`
        # while still being counted as imported.
        @claimed_paths = Set(String).new

        # Last suffix handed out per colliding stem, so claiming is O(1)
        # instead of rescanning `-1`, `-2`, … from the start for every
        # collision (quadratic once a section has thousands of them).
        @claim_suffixes = Hash(String, Int32).new

        # Number of destinations disambiguated this run. Reported once in the
        # summary rather than as one warning line per file — a large import
        # with many collisions otherwise buries every other diagnostic.
        @collision_count = 0

        # Reset per-run state. Importers call this at the top of `run` so a
        # reused importer instance doesn't disambiguate against a previous
        # run's destinations.
        protected def reset_written_paths : Nil
          @claimed_paths.clear
          @claim_suffixes.clear
          @collision_count = 0
          @file_actions.clear
        end

        # The per-item import loop every importer runs: yield each item,
        # tally the outcome it returns (:imported / :imported_wrapped /
        # :skipped), turn a raised exception into a counted error (see
        # `import_error_message`), then warn once about files that kept
        # engine-specific syntax verbatim (`wrapped_note`, the sentence after
        # "N file(s)"), report path collisions and build the ImportResult
        # (`summary_message`). Both messages have per-engine overrides.
        protected def import_each(items : Array(T), engine : String, wrapped_note : String? = nil, & : T -> Symbol) : ImportResult forall T
          imported = 0
          skipped = 0
          errors = 0
          wrapped = 0

          items.each do |item|
            result = yield item
            case result
            when :imported
              imported += 1
            when :imported_wrapped
              imported += 1
              wrapped += 1
            when :skipped
              skipped += 1
            end
          rescue ex
            errors += 1
            Logger.warn import_error_message(item, ex)
          end

          if wrapped > 0 && wrapped_note
            Logger.warn "#{wrapped} file(s) #{wrapped_note}"
          end

          report_collisions

          ImportResult.new(
            success: imported > 0 || errors == 0,
            message: summary_message(engine, imported, skipped, errors),
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        protected def import_error_message(item : String, ex : Exception) : String
          "Error importing #{item}: #{ex.message}"
        end

        protected def import_error_message(item : NamedTuple, ex : Exception) : String
          "Error importing #{item[:path]}: #{ex.message}"
        end

        protected def summary_message(engine : String, imported : Int32, skipped : Int32, errors : Int32) : String
          "#{engine} import complete: #{imported} imported, #{skipped} skipped, #{errors} errors"
        end

        # Emit the single end-of-run collision summary, if any. Importers call
        # this from `run` alongside their other summary warnings.
        protected def report_collisions : Nil
          return if @collision_count == 0
          Logger.warn "#{@collision_count} destination(s) renamed because an earlier source in this run claimed the same filename (re-run with --verbose to see each one)."
        end

        # Resolve the on-disk destination for a section/slug pair, or nil when
        # the components sanitize to something unsafe.
        #
        # Importers consume third-party exports, so `section` and `slug` are
        # UNTRUSTED. A malicious WordPress `<wp:post_name>` or Hugo front
        # matter `slug` of "../../../etc/x" would otherwise let `File.write`
        # escape `output_dir` and plant or overwrite files anywhere the
        # running user can write. Neutralise traversal at this single sink so
        # every current and future importer is protected.
        protected def resolve_content_path(output_dir : String, section : String, slug : String, verbose : Bool = false) : String?
          safe_section = Utils::PathUtils.sanitize_path(section)
          safe_slug = safe_filename_component(slug)
          if safe_slug.empty?
            Logger.warn "Skipped (unsafe slug #{slug.inspect})" if verbose
            return
          end

          dir = safe_section.empty? ? output_dir : File.join(output_dir, safe_section)
          filename = safe_slug.ends_with?(".md") ? safe_slug : "#{safe_slug}.md"
          path = File.join(dir, filename)

          # Belt-and-suspenders: refuse to write outside output_dir even if a
          # component slipped past the sanitisers above.
          unless Utils::OutputGuard.within_output_dir?(path, output_dir)
            Logger.warn "Skipped (escapes output directory): #{path}"
            return
          end

          path
        end

        # Claim `path` for this run, appending `-1`, `-2`, … when an earlier
        # source already took it. Importers that disambiguate their own slugs
        # (Jekyll's date re-attachment, Notion, Eleventy) hand over paths that
        # are already unique, so this never fires for them — it's the backstop
        # for the importers that don't.
        #
        # Claims are resolved in walk order, which `walk_files` sorts so a run
        # is reproducible. Note the suffix namespace is shared with real
        # slugs: sources `x`, `x`, `x-1` yield `x`, `x-1`, `x-1-1`, so the
        # genuine `x-1` is the one that moves. Nothing is lost or overwritten
        # either way, and resolving it properly would mean computing every
        # destination before writing any — a two-pass restructure of all eight
        # importers for a cosmetic difference.
        private def claim_path(path : String) : String
          return path if @claimed_paths.add?(path)

          ext = File.extname(path)
          stem = path.chomp(ext)
          n = @claim_suffixes[stem]? || 0
          loop do
            n += 1
            break if @claimed_paths.add?("#{stem}-#{n}#{ext}")
          end
          @claim_suffixes[stem] = n
          "#{stem}-#{n}#{ext}"
        end

        # Write a content file. Skips if it already exists unless `force`
        # is true, in which case the existing file is overwritten. Returns
        # true when a file was written, false when it was skipped.
        #
        # `force` means "overwrite a file that was already on disk before this
        # import" — never "clobber a file this same run just wrote", which is
        # why the destination is claimed before the existence check. Claiming
        # first also keeps re-imports idempotent: on a second run every source
        # resolves to the same destination it did the first time and is
        # skipped, rather than piling up `-1` copies.
        protected def write_content_file(
          output_dir : String,
          section : String,
          slug : String,
          frontmatter : String,
          body : String,
          verbose : Bool = false,
          force : Bool = false,
        ) : Bool
          write_content_file_to(output_dir, section, slug, frontmatter, body, verbose, force)[0]
        end

        # Same as `write_content_file`, but also reports the destination it
        # settled on — including when the write was skipped. Callers that
        # manage sibling files (page-bundle assets) need the directory that
        # was actually chosen, which `claim_path` and the slug sanitisers can
        # move away from the naive `output_dir/section` guess.
        protected def write_content_file_to(
          output_dir : String,
          section : String,
          slug : String,
          frontmatter : String,
          body : String,
          verbose : Bool = false,
          force : Bool = false,
        ) : {Bool, String?}
          resolved = resolve_content_path(output_dir, section, slug, verbose)
          return {false, nil} unless resolved

          path = claim_path(resolved)
          dir = File.dirname(path)

          Hwaro::Utils::FileSafe.mkdir_p(dir) unless @dry_run || Dir.exists?(dir)

          # `within_output_dir?` above is lexical. If the section directory
          # (or any ancestor) is a symlink pointing out of the tree, that
          # check still passes and `File.write` follows the link straight out
          # of `output_dir`. Re-check with symlinks resolved now that the
          # directory exists. A dry run creates no directories, so it can only
          # perform this resolved check against directories that already exist
          # — which is exactly the pre-existing-symlink case the real run
          # would refuse, keeping the dry-run manifest honest.
          if Dir.exists?(dir) && !Utils::PathUtils.resolves_within?(dir, output_dir)
            Logger.warn "Skipped (destination directory resolves outside the output directory): #{dir}"
            return {false, nil}
          end

          if File.exists?(path) && !force
            Logger.warn "Skipped (already exists): #{path}" if verbose
            @file_actions << FileAction.new(path, "skipped")
            return {false, path}
          end

          action = File.exists?(path) ? "overwritten" : "imported"

          unless @dry_run
            content = "#{frontmatter}\n\n#{body}\n"
            File.write(path, content)
          end

          # Only now is the rename real. Counting/announcing it at claim time
          # asserted a write that never happened when the disambiguated
          # destination also already existed on disk.
          if path != resolved
            @collision_count += 1
            Logger.debug "Renamed: #{File.basename(resolved)} → #{File.basename(path)} (claimed by an earlier source in this run)" if verbose
          end

          @file_actions << FileAction.new(path, action)
          if verbose
            label = @dry_run ? "Would import" : (action == "overwritten" ? "Overwrote" : "Imported")
            Logger.debug "#{label}: #{path}"
          end
          {true, path}
        end

        # Copy a page bundle's co-located assets — every non-Markdown sibling
        # of the bundle's `index.md` — into the bundle's destination
        # directory. Hwaro serves those files straight out of the bundle, so
        # an import that carries only the `.md` leaves every
        # `![](cover.png)` in the post 404ing. Symlinks are skipped for the
        # same reason `walk_files_into` skips them, and every destination is
        # re-checked against `output_dir`.
        protected def copy_bundle_assets(
          source_dir : String,
          dest_dir : String,
          output_dir : String,
          verbose : Bool = false,
          force : Bool = false,
        ) : Int32
          return 0 unless Dir.exists?(source_dir)
          return 0 unless Utils::OutputGuard.within_output_dir?(dest_dir, output_dir)
          # `within_output_dir?` is lexical. If the destination directory —
          # or any ancestor — is a symlink out of the tree, `Dir.exists?`
          # follows it and `File.copy` would write straight through it.
          # A dry run never created `dest_dir`, so it can only apply the
          # resolved check to a directory that already exists — the same
          # pre-existing-symlink case the real run refuses.
          if @dry_run
            return 0 if Dir.exists?(dest_dir) && !Utils::PathUtils.resolves_within?(dest_dir, output_dir)
          else
            return 0 unless Utils::PathUtils.resolves_within?(dest_dir, output_dir)
          end

          copied = 0
          Dir.children(source_dir).sort!.each do |entry|
            src = File.join(source_dir, entry)
            next if File.directory?(src) || File.symlink?(src)
            next if entry.ends_with?(".md") || entry.ends_with?(".markdown")

            # `entry` is a single directory component — it can never contain
            # `/`, `.` or `..`, so the guard below is the real protection.
            # Running it through `safe_filename_component` only split on `\`,
            # renaming a legitimate `C:\photo.png` to `photo.png` and leaving
            # the `![](C:\photo.png)` reference this copy exists to repair
            # still broken. The exporter twin does the same.
            dest = File.join(dest_dir, entry)
            next unless Utils::OutputGuard.within_output_dir?(dest, output_dir)
            if File.exists?(dest) && !force
              @file_actions << FileAction.new(dest, "skipped")
              next
            end

            action = File.exists?(dest) ? "overwritten" : "imported"
            unless @dry_run
              Hwaro::Utils::FileSafe.mkdir_p(dest_dir) unless Dir.exists?(dest_dir)
              File.copy(src, dest)
            end
            @file_actions << FileAction.new(dest, action)
            Logger.debug "#{@dry_run ? "Would copy" : "Copied"} bundle asset: #{dest}" if verbose
            copied += 1
          rescue ex
            Logger.warn "Could not copy bundle asset #{src}: #{ex.message}"
          end
          copied
        end

        # Collapse an untrusted slug to a single safe filename component so it
        # can never traverse out of the section directory. Drops null bytes,
        # splits on both `/` and `\` separators, removes "."/".."/empty
        # segments, and keeps the last remaining segment (which may legitimately
        # carry a trailing ".md"). Unicode is preserved. We intentionally do NOT
        # URL-decode: the filesystem treats `%2f` as a literal, so decoding
        # would only manufacture separators that aren't really there.
        # `scrub` first: URI-decoded slugs (`a%ffb`) can carry invalid UTF-8,
        # and the split regex raises ArgumentError on an invalid byte
        # sequence — scrubbing here protects every caller.
        protected def safe_filename_component(value : String) : String
          value.scrub
            .delete(Char::ZERO)
            .split(/[\/\\]/)
            .reject { |seg| seg.empty? || seg == "." || seg == ".." }
            .last? || ""
        end

        # Parse a date string in common formats, returns nil on failure.
        protected def parse_date(date_str : String) : Time?
          Utils::DateUtils.parse_lenient(date_str, Utils::DateUtils::IMPORT_FORMATS)
        end

        # Format a Time to the standard frontmatter date format, keeping the
        # source's zone offset — the previous zone-less `%Y-%m-%d %H:%M:%S`
        # dropped the offset, so a `+09:00` post re-parsed as UTC shifted by
        # nine hours in feeds and sort order.
        protected def format_date(time : Time) : String
          Hwaro::Utils::FrontmatterWriter.serialize_time(time)
        end

        # YAML::Any scalar → String: string scalars pass through, anything
        # else falls back to its raw representation.
        protected def yaml_string(value : YAML::Any) : String
          value.as_s? || value.raw.to_s
        end

        # Assign a date-valued frontmatter field that may be a YAML timestamp
        # (already a Time) or a string in any of the lenient `parse_date`
        # formats. An unparseable string leaves `fields[key]` unset.
        protected def assign_date_field(fields : Hash(String, FieldValue), key : String, value : YAML::Any) : Nil
          case raw = value.raw
          when Time
            fields[key] = format_date(raw)
          when String
            parsed = parse_date(raw)
            fields[key] = format_date(parsed) if parsed
          end
        end

        # Append entries from a list-valued frontmatter field that may be an
        # array of scalars or a comma/space-separated string.
        protected def collect_string_list(value : YAML::Any, into list : Array(String)) : Nil
          case value.raw
          when Array
            # Filter blank items like the string branch below does — an
            # empty array element otherwise became an empty taxonomy term.
            value.as_a.each do |v|
              s = yaml_string(v)
              list << s unless s.blank?
            end
          when String
            value.as_s.split(/[\s,]+/).each { |v| list << v.strip unless v.strip.empty? }
          end
        end

        # First value among `keys` that is present AND non-null. The naive
        # `yaml["a"]? || yaml["b"]?` chain can't express this: YAML::Any is a
        # struct, so a present-but-null key (`pubDate:` with no value) is
        # truthy and silently discards every fallback after it.
        protected def first_present(yaml : YAML::Any, *keys : String) : YAML::Any?
          keys.each do |key|
            value = yaml[key]?
            return value if value && !value.raw.nil?
          end
          nil
        end

        # :ditto:
        protected def first_present(yaml : Hash(YAML::Any, YAML::Any), *keys : String) : YAML::Any?
          keys.each do |key|
            value = yaml[key]?
            return value if value && !value.raw.nil?
          end
          nil
        end
      end
    end
  end
end
