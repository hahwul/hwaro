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

        def run(options : Config::Options::ExportOptions) : ExportResult
          content_dir = options.content_dir
          output_dir = options.output_dir
          include_drafts = options.drafts
          verbose = options.verbose

          @written_paths.clear
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

          ExportResult.new(
            success: exported > 0 || errors == 0,
            message: "Exported #{exported} items, skipped #{skipped}, errors #{errors}",
            exported_count: exported,
            skipped_count: skipped,
            error_count: errors
          )
        end

        # Keys emitted explicitly below; everything else passes through as a
        # Jekyll page variable (Jekyll accepts arbitrary front-matter keys, so
        # dropping `slug`, `weight`, `layout`, `extra.*`, … was silent data
        # loss — the same bug class gh#527 fixed for the Hugo exporter).
        HANDLED_KEYS = Set{"title", "date", "description", "draft", "tags", "categories", "authors", "image"}

        private def export_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_path)
          fields, body = parse_content(raw)

          is_draft = fields["draft"]?.try(&.raw) == true
          if is_draft && !include_drafts
            return :skipped
          end

          # Build Jekyll YAML frontmatter
          yaml_lines = [] of String

          if title = fields["title"]?.try(&.as_s?)
            yaml_lines << "title: #{title.inspect}"
          end

          if date = fields["date"]?.try(&.as_s?)
            yaml_lines << "date: #{date}"
          end

          if desc = fields["description"]?.try(&.as_s?)
            yaml_lines << "description: #{desc.inspect}"
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
          end

          # categories from taxonomies if present
          if cats = string_list_field(fields["categories"]?)
            yaml_lines << "categories:"
            cats.each { |c| yaml_lines << "  - #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(c)}" }
          end

          # Jekyll natively understands an `authors` front-matter list, so
          # carry it across instead of dropping author attribution.
          if authors = string_list_field(fields["authors"]?)
            yaml_lines << "authors:"
            authors.each { |a| yaml_lines << "  - #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(a)}" }
          end

          if image = fields["image"]?.try(&.as_s?)
            yaml_lines << "image: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(image)}"
          end

          if passthrough = passthrough_yaml(fields)
            yaml_lines << passthrough
          end

          frontmatter = "---\n#{yaml_lines.join("\n")}\n---"
          body = rewrite_internal_links(body)

          out_path = resolve_jekyll_path(file_path, content_dir, output_dir, fields, is_draft, include_drafts)
          out_path = disambiguate_path(out_path)

          write_file(out_path, "#{frontmatter}\n\n#{body.strip}\n", verbose)
          :exported
        end

        # Serialize the non-allowlisted fields through the YAML emitter (which
        # handles nesting, typing, and quoting), returning frontmatter lines
        # without the `---` fences, or nil when there is nothing to carry.
        private def passthrough_yaml(fields : Hash(String, YAML::Any)) : String?
          leftovers = {} of YAML::Any => YAML::Any
          fields.each do |key, value|
            next if HANDLED_KEYS.includes?(key)
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
