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

          is_draft = fields["draft"]?.try { |v| v == true }
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

          if tags = fields["tags"]?.as?(Array(String))
            yaml_lines << "tags:"
            tags.each { |t| yaml_lines << "  - #{t}" }
          end

          # categories from taxonomies if present
          if cats = fields["categories"]?.as?(Array(String))
            yaml_lines << "categories:"
            cats.each { |c| yaml_lines << "  - #{c}" }
          end

          if image = fields["image"]?.as?(String)
            yaml_lines << "image: #{image}"
          end

          frontmatter = "---\n#{yaml_lines.join("\n")}\n---"
          body = rewrite_internal_links(body)

          # Determine output path
          relative = file_path.sub(content_dir, "").lstrip('/')
          filename = File.basename(relative)
          dir_part = File.dirname(relative)

          # For regular posts (not _index), use Jekyll's date-based naming
          if filename != "_index.md" && filename != "_index.markdown"
            if date_str = fields["date"]?.as?(String)
              # Extract YYYY-MM-DD from date
              date_prefix = date_str.size >= 10 ? date_str[0, 10] : ""
              if date_prefix.matches?(/^\d{4}-\d{2}-\d{2}$/)
                slug = filename.sub(/\.(md|markdown)$/, "")
                filename = "#{date_prefix}-#{slug}.md"
              end
            end

            # Posts go to _posts directory
            if dir_part == "." || dir_part.empty?
              out_path = File.join(output_dir, "_posts", filename)
            else
              out_path = File.join(output_dir, "_posts", dir_part, filename)
            end
          else
            # Section index files -> Jekyll pages
            slug = dir_part == "." ? "index" : dir_part
            out_path = File.join(output_dir, slug, "index.md")
          end

          # Drafts go to _drafts without date prefix
          if is_draft && include_drafts
            out_path = out_path.sub("/_posts/", "/_drafts/")
            # Remove date prefix for drafts
            draft_basename = File.basename(out_path)
            if draft_basename.matches?(/^\d{4}-\d{2}-\d{2}-/)
              draft_basename = draft_basename.sub(/^\d{4}-\d{2}-\d{2}-/, "")
              out_path = File.join(File.dirname(out_path), draft_basename)
            end
          end

          write_file(out_path, "#{frontmatter}\n\n#{body.strip}\n", verbose)
          :exported
        end
      end
    end
  end
end
