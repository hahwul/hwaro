require "yaml"
require "./base"

module Hwaro
  module Services
    module Importers
      class NotionImporter < Base
        # Notion exported markdown uses YAML frontmatter or embedded metadata
        # Notion export structure: folder per page, with .md files and assets

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0

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
            begin
              result = import_file(file_path, path, output_dir, options.verbose)
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
          files = [] of String
          scan_dir(path, files)
          files
        end

        private def scan_dir(dir : String, files : Array(String))
          Dir.each_child(dir) do |entry|
            full_path = File.join(dir, entry)
            if File.directory?(full_path)
              scan_dir(full_path, files)
            elsif entry.ends_with?(".md") || entry.ends_with?(".markdown")
              files << full_path
            end
          end
        end

        private def import_file(
          file_path : String,
          base_path : String,
          output_dir : String,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_path)
          frontmatter_yaml, body = parse_markdown_file(raw)

          fields = Hash(String, String | Bool | Array(String) | Nil).new

          if frontmatter_yaml
            yaml = YAML.parse(frontmatter_yaml)

            if title = yaml["title"]?
              fields["title"] = title.as_s? || title.raw.to_s
            end

            if date_val = yaml["date"]?
              case date_val.raw
              when Time
                fields["date"] = format_date(date_val.raw.as(Time))
              when String
                parsed = parse_date(date_val.as_s)
                fields["date"] = format_date(parsed) if parsed
              end
            end

            if tags_val = yaml["tags"]?
              tags = [] of String
              case tags_val.raw
              when Array
                tags_val.as_a.each { |t| tags << (t.as_s? || t.raw.to_s) }
              when String
                tags_val.as_s.split(/[\s,]+/).each { |t| tags << t.strip unless t.strip.empty? }
              end
              fields["tags"] = tags unless tags.empty?
            end

            if desc = yaml["description"]?
              fields["description"] = desc.as_s? || desc.raw.to_s
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

          section = "posts"

          frontmatter = generate_frontmatter(fields)
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose)
          written ? :imported : :skipped
        end

        # Regex to match YAML frontmatter
        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def parse_markdown_file(content : String) : Tuple(String?, String)
          if match = YAML_FM_REGEX.match(content)
            yaml_str = match[1].strip
            body = match[2].strip
            return {yaml_str, body}
          end
          {nil, content.strip}
        end

        private def extract_title_from_body(body : String) : String?
          if match = /\A#\s+(.+)/.match(body)
            match[1].strip
          else
            nil
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
          result = result.gsub(/^> [^\w\s]\s+(.+)$/m, "> \\1")

          # Convert Notion bookmark embeds to links
          result = result.gsub(/\[bookmark\]\((.+?)\)/, "[\\1](\\1)")

          # Convert Notion image references with captions
          # Notion exports images to subfolders; keep relative paths
          result
        end
      end
    end
  end
end
