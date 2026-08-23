require "./base"

module Hwaro
  module Services
    module Exporters
      class JekyllExporter < Base
        # Top-level sections whose dated content maps to Jekyll's `_posts/`
        # collection. `posts` is what the Jekyll importer itself produces
        # (round-trip symmetric) and `blog` is the other common Hwaro layout.
        # Membership in one of these sections — not the mere presence of a
        # `date` — is what makes a file a blog post: Hwaro auto-stamps `date`
        # on every `hwaro new` page, so "has a date" alone misclassified
        # ordinary pages (`about.md`, deep section pages) as posts.
        POST_SECTIONS = %w[posts blog]

        # Destinations already written this run, used to disambiguate
        # collisions (e.g. two same-day leaf bundles both named `index.md`)
        # instead of silently overwriting the earlier export.
        @written_paths = Set(String).new

        # Page-bundle assets left behind this run (see
        # `note_unexported_bundle_assets`), folded into the skipped count so
        # the summary never reports a clean export of a post whose images
        # were not written.
        @unexported_assets = 0

        def run(options : Config::Options::ExportOptions) : ExportResult
          content_dir = options.content_dir
          output_dir = options.output_dir
          include_drafts = options.drafts
          verbose = options.verbose

          @written_paths.clear
          @unexported_assets = 0
          files = scan_content_files(content_dir)

          if files.empty?
            return ExportResult.new(
              success: false,
              message: "No content files found in: #{content_dir}"
            )
          end

          exported = 0
          skipped = 0
          errors = 0

          files.each do |file_path|
            result = export_file(file_path, content_dir, output_dir, include_drafts, verbose)
            case result
            when :exported then exported += 1
            when :skipped  then skipped += 1
            end
          rescue ex
            errors += 1
            Logger.warn "Error exporting #{file_path}: #{ex.message}"
          end

          # Bundle assets that were not carried across count as skipped: they
          # are content the user handed the exporter and did not get back.
          skipped += @unexported_assets

          # Any per-file error fails the run: `exported > 0` used to mask
          # errors, so a partial export reported success and exited 0.
          ExportResult.new(
            success: errors == 0,
            message: errors > 0 ? "#{errors} file(s) could not be exported (#{exported} exported, #{skipped} skipped)" : "Exported #{exported} items, skipped #{skipped}, errors #{errors}",
            exported_count: exported,
            skipped_count: skipped,
            error_count: errors
          )
        end

        # Keys the explicit emitters below may claim; everything else passes
        # through as a Jekyll page variable (Jekyll accepts arbitrary
        # front-matter keys, so dropping `slug`, `weight`, `layout`,
        # `extra.*`, … was silent data loss — the same bug class gh#527 fixed
        # for the Hugo exporter). A key is only excluded from the passthrough
        # when its emitter actually produced a line: a value the emitter
        # cannot represent (hash-valued `tags`, array `title`, …) used to be
        # swallowed — skipped by the emitter AND skipped by name here.
        HANDLED_KEYS = Set{"title", "date", "description", "draft", "tags", "categories", "authors", "image", "template"}

        # Matches the date/timestamp shapes Jekyll's YAML loader reads
        # natively; anything else is emitted via `yaml_scalar` — raw
        # interpolation of an arbitrary string into `date:` let a newline or
        # `: ` inject or break the frontmatter.
        DATE_SHAPE_RE = /\A\d{4}-\d{2}-\d{2}([Tt ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?( ?([Zz]|[+-]\d{2}:?\d{2}))?)?\z/

        private def export_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
        ) : Symbol
          raw = read_content(file_path)
          fields, body = parse_content(raw)
          # Jekyll reads `tags:` / `categories:` at the top level, so a
          # `[taxonomies]` table has to be hoisted or the post loses every
          # taxonomy it belongs to.
          fields = flatten_taxonomies(fields)

          is_draft = fields["draft"]?.try(&.raw) == true
          if is_draft && !include_drafts
            return :skipped
          end

          # Build Jekyll YAML frontmatter. Keys are marked handled only when
          # an emitter actually produced a line, so a value the emitters
          # cannot represent falls through to `passthrough_yaml` instead of
          # being silently dropped.
          yaml_lines = [] of String
          handled = Set(String).new
          # A boolean draft is fully translated (true → `published: false`,
          # false → omitted, Jekyll's default); any other type falls through
          # to passthrough_yaml like every other unrepresentable value.
          handled << "draft" if fields["draft"]?.try(&.raw).is_a?(Bool)

          if title = scalar_string(fields["title"]?)
            yaml_lines << "title: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(title)}"
            handled << "title"
          end

          if date = scalar_string(fields["date"]?)
            yaml_lines << "date: #{yaml_date_value(date)}"
            handled << "date"
          end

          if desc = scalar_string(fields["description"]?)
            yaml_lines << "description: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(desc)}"
            handled << "description"
          end

          # Hwaro's `template` is Jekyll's `layout`, the exact inverse of the
          # Jekyll importer's `layout` → `template` mapping. Passing the key
          # through verbatim meant Jekyll ignored it (rendering the page with
          # no layout at all) and a re-import dropped it entirely.
          if layout = scalar_string(fields["template"]?)
            yaml_lines << "layout: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(layout)}"
            handled << "template"
          end

          # Jekyll uses `published: false` instead of `draft: true`
          if is_draft
            yaml_lines << "published: false"
          end

          # Accept both list (`tags: [a, b]`) and scalar (`tags: crystal`)
          # shorthand — a scalar would otherwise fail the Array(String) cast
          # and silently drop the post's taxonomy membership. Items are
          # YAML-quoted when needed: a bare `- beta: gamma` reparses as a
          # mapping and `- NO` as `false` under Jekyll's YAML 1.1 loader.
          if tags = string_list_field(fields["tags"]?)
            yaml_lines << "tags:"
            tags.each { |t| yaml_lines << "  - #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(t)}" }
            handled << "tags"
          end

          # categories from taxonomies if present
          if cats = string_list_field(fields["categories"]?)
            yaml_lines << "categories:"
            cats.each { |c| yaml_lines << "  - #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(c)}" }
            handled << "categories"
          end

          # Jekyll natively understands an `authors` front-matter list, so
          # carry it across instead of dropping author attribution.
          if authors = string_list_field(fields["authors"]?)
            yaml_lines << "authors:"
            authors.each { |a| yaml_lines << "  - #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(a)}" }
            handled << "authors"
          end

          if image = scalar_string(fields["image"]?)
            yaml_lines << "image: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(image)}"
            handled << "image"
          end

          if passthrough = passthrough_yaml(fields, handled)
            yaml_lines << passthrough
          end

          frontmatter = "---\n#{yaml_lines.join("\n")}\n---"
          body = rewrite_internal_links(body)

          out_path = resolve_jekyll_path(file_path, content_dir, output_dir, fields, is_draft, include_drafts)
          out_path = disambiguate_path(out_path)

          # A refused destination (outside `output_dir`) is reported as
          # skipped; the bundle-asset accounting below only describes files
          # that accompany an exported post, so it is skipped too.
          return :skipped unless write_file(out_path, "#{frontmatter}\n\n#{body.strip}\n", output_dir, verbose)

          @unexported_assets += note_unexported_bundle_assets(file_path, content_dir)
          :exported
        end

        # A page bundle keeps its assets next to `index.md`
        # (`posts/my-post/cover.png`), and the Hugo exporter copies them across
        # because it preserves the bundle directory. Jekyll's `_posts/` layout
        # is FLAT — `_posts/2024-01-15-my-post.md` — so there is no destination
        # that keeps a bare `![](cover.png)` resolving without ALSO rewriting
        # the exported body, which is a separate change with its own spec.
        #
        # Until then the assets stay behind, so name them and return the count:
        # the export used to report `exported: 1 files, 0 skipped` and exit 0
        # for a post whose every image link was dead.
        private def note_unexported_bundle_assets(file_path : String, content_dir : String) : Int32
          basename = File.basename(file_path)
          return 0 unless basename == "index.md" || basename == "index.markdown"

          # The site root is never a bundle: `content/index.md` sits beside
          # every top-level file in the content tree, none of which belongs to
          # it. Same nesting test the Hugo exporter uses before copying.
          relative = file_path.sub(content_dir, "").lstrip('/')
          return 0 unless relative.includes?('/')

          source_dir = File.dirname(file_path)
          assets = Dir.children(source_dir).sort!.reject do |entry|
            entry.ends_with?(".md") || entry.ends_with?(".markdown") ||
              File.directory?(File.join(source_dir, entry))
          end
          return 0 if assets.empty?

          Logger.warn "#{assets.size} bundle asset(s) not exported for #{file_path}: #{assets.join(", ")}. " \
                      "Copy them into the Jekyll site and update the links."
          assets.size
        rescue ex : File::Error
          # The bundle directory vanished or is unreadable between the scan and
          # here — the post itself already exported, so don't fail the run.
          Logger.debug "Could not inspect bundle directory for #{file_path}: #{ex.message}"
          0
        end

        # String form of a scalar front-matter value: strings pass through
        # and Bool/Int/Float stringify (a non-string `title: 2024` used to be
        # silently dropped). Structured or null values return nil so the
        # caller leaves the key to `passthrough_yaml`. Time never reaches
        # here — `parse_content` already normalizes it to a date string.
        private def scalar_string(value : YAML::Any?) : String?
          return unless value
          if str = value.as_s?
            return str
          end
          case raw = value.raw
          when Bool, Int64, Float64
            raw.to_s
          end
        end

        # A well-formed date/timestamp is written raw so Jekyll's YAML loader
        # reads it as a date; anything else goes through `yaml_scalar`.
        private def yaml_date_value(date : String) : String
          date.matches?(DATE_SHAPE_RE) ? date : Hwaro::Utils::FrontmatterWriter.yaml_scalar(date)
        end

        # Serialize the fields no emitter claimed through the YAML emitter
        # (which handles nesting, typing, and quoting), returning frontmatter
        # lines without the `---` fences, or nil when there is nothing to
        # carry. `handled` holds the keys actually emitted above — filtering
        # by the static HANDLED_KEYS list swallowed handled-key values the
        # emitters had skipped as unrepresentable.
        private def passthrough_yaml(fields : Hash(String, YAML::Any), handled : Set(String)) : String?
          leftovers = {} of YAML::Any => YAML::Any
          fields.each do |key, value|
            next if handled.includes?(key)
            next if value.raw.nil?
            leftovers[YAML::Any.new(key)] = value
          end
          return if leftovers.empty?

          YAML::Any.new(leftovers).to_yaml.lchop("---\n").chomp
        end

        # Reserve `path` for this run, appending `-1`, `-2`, … (with a
        # warning) when an earlier file already claimed it. Flattening into
        # `_posts/` makes collisions possible — two leaf bundles published
        # the same day used to silently clobber each other.
        private def disambiguate_path(path : String) : String
          return path if @written_paths.add?(path)

          ext = File.extname(path)
          stem = path.chomp(ext)
          n = 1
          until @written_paths.add?("#{stem}-#{n}#{ext}")
            n += 1
          end
          unique = "#{stem}-#{n}#{ext}"
          Logger.warn "Export destination collision: #{path} already written this run; writing #{File.basename(unique)} instead."
          unique
        end

        # Map a Hwaro content path to its Jekyll-conventional destination.
        # Jekyll has three buckets that look superficially similar but aren't:
        #   - `_posts/<YYYY-MM-DD>-<slug>.md` — dated blog posts, FLAT layout.
        #     Subdirectories under `_posts/` are interpreted by Jekyll as
        #     category hints, so nesting `content/posts/foo.md` under
        #     `_posts/posts/foo.md` would erroneously put every post in a
        #     `posts` category.
        #   - `_drafts/<slug>.md` — drafts, no date prefix.
        #   - Regular pages (`about.md`, `team/engineering/…`) — anything
        #     else, exported with its directory layout preserved.
        # Only dated files under a POST_SECTIONS top-level section become
        # posts; everything else keeps its tree, whatever its `date` says.
        # `_index.md` (Hwaro's section index) maps to `<section>/index.md`,
        # the closest Jekyll equivalent (a normal page that happens to be
        # the section landing page).
        private def resolve_jekyll_path(
          file_path : String,
          content_dir : String,
          output_dir : String,
          fields : Hash(String, YAML::Any),
          is_draft : Bool,
          include_drafts : Bool,
        ) : String
          relative = file_path.sub(content_dir, "").lstrip('/')
          filename = File.basename(relative)
          dir_part = File.dirname(relative)

          # Section indices become regular pages (Jekyll has no `_index`).
          # The site root maps to `index.md` at the export root — an
          # `index/index.md` would be served at `/index/`, leaving `/` empty.
          if filename == "_index.md" || filename == "_index.markdown"
            return File.join(output_dir, "index.md") if dir_part == "." || dir_part.empty?
            return File.join(output_dir, dir_part, "index.md")
          end

          date_str = fields["date"]?.try(&.as_s?)
          date_prefix = date_str && date_str.size >= 10 ? date_str[0, 10] : nil
          dated = date_prefix && date_prefix.matches?(/^\d{4}-\d{2}-\d{2}$/)
          slug = filename.sub(/\.(md|markdown)$/, "")

          # Leaf bundle (`posts/my-post/index.md`): the slug is the bundle
          # directory, not "index" — a literal "index" slug collided across
          # every same-day bundle once flattened into `_posts/`.
          if slug == "index" && dir_part != "." && !dir_part.empty?
            slug = File.basename(dir_part)
          end

          # A source already named `YYYY-MM-DD-slug` (file or bundle dir)
          # would double up (`_posts/2024-01-15-2024-01-15-hello.md`) once the
          # date prefix is re-applied below; Jekyll would then derive a dated
          # slug/URL.
          if dated
            stripped = slug.sub(/\A\d{4}-\d{2}-\d{2}-/, "")
            slug = stripped unless stripped.empty?
          end

          # Content under a posts-like top-level section is a blog post:
          # flat in `_posts/` when dated (or `_drafts/` for drafts — Jekyll
          # draft filenames carry no date, so validity doesn't matter there),
          # collapsing the source subdirectory — Jekyll treats subdirs under
          # `_posts/` as category hints, and re-applying the source folder
          # as a category is almost never what the author meant on a
          # Hwaro→Jekyll migration.
          top_section = relative.includes?('/') ? relative.split('/').first : nil
          if top_section && POST_SECTIONS.includes?(top_section)
            if is_draft && include_drafts
              return File.join(output_dir, "_drafts", "#{slug}.md")
            end
            return File.join(output_dir, "_posts", "#{date_prefix}-#{slug}.md") if dated
          end

          # Everything else (about, team/…, archives, dated or not) → keep
          # the on-disk layout under the export root so Jekyll picks them up
          # as regular pages and their section identity survives.
          File.join(output_dir, relative)
        end
      end
    end
  end
end
