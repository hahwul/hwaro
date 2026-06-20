require "./base"

module Hwaro
  module Services
    module Exporters
      class JekyllExporter < Base
        def run(options : Config::Options::ExportOptions) : ExportResult
          content_dir = options.content_dir
          output_dir = options.output_dir
          include_drafts = options.drafts
          verbose = options.verbose

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
            begin
              result = export_file(file_path, content_dir, output_dir, include_drafts, verbose)
              case result
              when :exported then exported += 1
              when :skipped  then skipped += 1
              end
            rescue ex
              errors += 1
              Logger.warn "Error exporting #{file_path}: #{ex.message}"
            end
          end

          ExportResult.new(
            success: exported > 0 || errors == 0,
            message: "Exported #{exported} items, skipped #{skipped}, errors #{errors}",
            exported_count: exported,
            skipped_count: skipped,
            error_count: errors
          )
        end

        private def export_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_path)
          fields, body = parse_content(raw)

          is_draft = (fields["draft"]?.try { |v| v == true }) == true
          if is_draft && !include_drafts
            return :skipped
          end

          # Build Jekyll YAML frontmatter
          yaml_lines = [] of String

          if title = fields["title"]?.as?(String)
            yaml_lines << "title: #{title.inspect}"
          end

          if date = fields["date"]?.as?(String)
            yaml_lines << "date: #{date}"
          end

          if desc = fields["description"]?.as?(String)
            yaml_lines << "description: #{desc.inspect}"
          end

          # Jekyll uses `published: false` instead of `draft: true`
          if is_draft
            yaml_lines << "published: false"
          end

          # Accept both list (`tags: [a, b]`) and scalar (`tags: crystal`)
          # shorthand — a scalar would otherwise fail the Array(String) cast
          # and silently drop the post's taxonomy membership.
          if tags = string_list_field(fields["tags"]?)
            yaml_lines << "tags:"
            tags.each { |t| yaml_lines << "  - #{t}" }
          end

          # categories from taxonomies if present
          if cats = string_list_field(fields["categories"]?)
            yaml_lines << "categories:"
            cats.each { |c| yaml_lines << "  - #{c}" }
          end

          if image = fields["image"]?.as?(String)
            yaml_lines << "image: #{image}"
          end

          frontmatter = "---\n#{yaml_lines.join("\n")}\n---"
          body = rewrite_internal_links(body)

          out_path = resolve_jekyll_path(file_path, content_dir, output_dir, fields, is_draft, include_drafts)

          write_file(out_path, "#{frontmatter}\n\n#{body.strip}\n", verbose)
          :exported
        end

        # Map a Hwaro content path to its Jekyll-conventional destination.
        # Jekyll has three buckets that look superficially similar but aren't:
        #   - `_posts/<YYYY-MM-DD>-<slug>.md` — dated blog posts, FLAT layout.
        #     Subdirectories under `_posts/` are interpreted by Jekyll as
        #     category hints, so nesting `content/posts/foo.md` under
        #     `_posts/posts/foo.md` would erroneously put every post in a
        #     `posts` category.
        #   - `_drafts/<slug>.md` — drafts, no date prefix.
        #   - Root pages (`about.md`, `index.md`, ...) — anything else.
        # `_index.md` (Hwaro's section index) maps to `<section>/index.md`,
        # the closest Jekyll equivalent (a normal page that happens to be
        # the section landing page).
        private def resolve_jekyll_path(
          file_path : String,
          content_dir : String,
          output_dir : String,
          fields : Hash(String, (String | Bool | Array(String))?),
          is_draft : Bool,
          include_drafts : Bool,
        ) : String
          relative = file_path.sub(content_dir, "").lstrip('/')
          filename = File.basename(relative)
          dir_part = File.dirname(relative)

          # Section indices become regular pages (Jekyll has no `_index`).
          if filename == "_index.md" || filename == "_index.markdown"
            slug = (dir_part == "." || dir_part.empty?) ? "index" : dir_part
            return File.join(output_dir, slug, "index.md")
          end

          date_str = fields["date"]?.as?(String)
          date_prefix = date_str && date_str.size >= 10 ? date_str[0, 10] : nil
          dated = date_prefix && date_prefix.matches?(/^\d{4}-\d{2}-\d{2}$/)
          slug = filename.sub(/\.(md|markdown)$/, "")

          # Files with a `date` are blog posts. Place them flat in `_posts/`
          # (or `_drafts/` for drafts) — any source subdirectory like
          # `content/posts/` or `content/blog/` is collapsed, because Jekyll
          # treats subdirs under `_posts/` as category hints and re-applying
          # the source folder as a category is almost never what the author
          # meant on a Hwaro→Jekyll migration.
          if dated
            if is_draft && include_drafts
              return File.join(output_dir, "_drafts", "#{slug}.md")
            end
            return File.join(output_dir, "_posts", "#{date_prefix}-#{slug}.md")
          end

          # Non-dated content (about, index, archives, etc.) → keep the
          # on-disk layout under the export root so Jekyll picks them up as
          # regular pages (not as posts hidden under `_posts/`).
          File.join(output_dir, relative)
        end
      end
    end
  end
end
