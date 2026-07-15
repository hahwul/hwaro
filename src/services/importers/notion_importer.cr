require "yaml"
require "set"
require "uri"
require "./base"

module Hwaro
  module Services
    module Importers
      class NotionImporter < Base
        # Notion exported markdown uses YAML frontmatter or embedded metadata
        # Notion export structure: folder per page, with .md files and assets

        # Slugs written this run, to disambiguate collisions.
        @used_slugs = Set(String).new

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0

          @used_slugs.clear

          unless Dir.exists?(path)
            return ImportResult.new(
              success: false,
              message: "Notion export directory not found: #{path}",
            )
          end

          files = collect_markdown_files(path)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No Markdown files found in #{path}",
            )
          end

          files.each do |file_path|
            result = import_file(file_path, path, output_dir, options.verbose, options.force)
            case result
            when :imported
              imported += 1
            when :skipped
              skipped += 1
            end
          rescue ex
            errors += 1
            Logger.warn "Error importing #{file_path}: #{ex.message}"
          end

          ImportResult.new(
            success: imported > 0 || errors == 0,
            message: "Notion import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        private def collect_markdown_files(path : String) : Array(String)
          walk_files(path)
        end

        private def import_file(
          file_path : String,
          base_path : String,
          output_dir : String,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          raw = read_text(file_path)
          frontmatter_yaml, body = split_yaml_frontmatter(raw)

          fields = Hash(String, FieldValue).new

          if frontmatter_yaml
            if yaml_hash = YAML.parse(frontmatter_yaml).as_h?
              if title = yaml_hash["title"]?
                fields["title"] = title.as_s? || title.raw.to_s
              end

              if date_val = yaml_hash["date"]?
                case date_val.raw
                when Time
                  fields["date"] = format_date(date_val.raw.as(Time))
                when String
                  parsed = parse_date(date_val.as_s)
                  fields["date"] = format_date(parsed) if parsed
                end
              end

              if tags_val = yaml_hash["tags"]?
                tags = [] of String
                case tags_val.raw
                when Array
                  tags_val.as_a.each { |t| tags << (t.as_s? || t.raw.to_s) }
                when String
                  tags_val.as_s.split(/[\s,]+/).each { |t| tags << t.strip unless t.strip.empty? }
                end
                fields["tags"] = tags unless tags.empty?
              end

              if desc = yaml_hash["description"]?
                fields["description"] = desc.as_s? || desc.raw.to_s
              end
            end
          end

          # Extract title from Notion's H1 heading if not in frontmatter
          unless fields.has_key?("title")
            title = extract_title_from_body(body)
            if title
              fields["title"] = title
              # Remove the H1 from body since it's now in frontmatter
              body = body.sub(/\A#\s+.+\n*/, "")
            else
              # Fall back to filename-based title
              fields["title"] = title_from_filename(file_path)
            end
          end

          # Extract date from file modification time if not in frontmatter
          unless fields.has_key?("date")
            if info = File.info?(file_path)
              fields["date"] = format_date(info.modification_time)
            end
          end

          # Clean up Notion-specific artifacts in body
          body = clean_notion_content(body)

          # Determine slug
          slug = slug_from_notion_filename(file_path)

          # Avoid collision on slug
          unless @used_slugs.add?(slug)
            base_slug = slug
            n = 1
            loop do
              candidate = "#{base_slug}-#{n}"
              if @used_slugs.add?(candidate)
                slug = candidate
                break
              end
              n += 1
            end
            Logger.warn "Slug collision: #{base_slug} already used, renamed to #{slug}"
          end

          section = "posts"

          frontmatter = generate_frontmatter(fields)
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose, force)
          written ? :imported : :skipped
        end

        private def extract_title_from_body(body : String) : String?
          if match = /\A#\s+(.+)/.match(body)
            match[1].strip
          end
        end

        private def title_from_filename(file_path : String) : String
          name = File.basename(file_path, File.extname(file_path))
          # Notion appends a hex ID to filenames, e.g., "My Page abc123def456"
          # Remove the trailing hex ID (16+ hex chars at end)
          name = name.sub(/\s+[0-9a-f]{16,}$/i, "")
          name.strip
        end

        private def slug_from_notion_filename(file_path : String) : String
          title = title_from_filename(file_path)
          slugify(title)
        end

        private def clean_notion_content(body : String) : String
          result = body

          # Convert Notion callout blocks (> emoji text) to plain blockquotes
          # Example: '> 💡 Some tip' -> '> Some tip'
          result = result.gsub(/^> [^\w\s]\x{FE0F}?\s+([^\n]+)$/m, "> \\1")

          # Convert Notion bookmark embeds to links
          result = result.gsub(/\[bookmark\]\((.+?)\)/, "[\\1](\\1)")

          # Rewrite internal subpage links (relative targets ending in .md containing a 32-hex suffix)
          result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do |match|
            text = $1
            target = $2
            if target.ends_with?(".md") && !target.starts_with?("http://") && !target.starts_with?("https://")
              target_decoded = URI.decode(target)
              if /[0-9a-fA-F]{32}/.match(target_decoded)
                filename = File.basename(target_decoded, ".md")
                clean_name = filename.sub(/\s+[0-9a-f]{16,}$/i, "").strip
                slug = slugify(clean_name)
                "[#{text}](/posts/#{slug}/)"
              else
                match
              end
            else
              match
            end
          end

          # Convert Notion image references with captions
          # Notion exports images to subfolders; keep relative paths
          result
        end
      end
    end
  end
end
