require "yaml"
require "./base"

module Hwaro
  module Services
    module Importers
      class AstroImporter < Base
        # Astro uses content collections in src/content/ directory
        # Frontmatter is YAML between --- delimiters

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0

          unless Dir.exists?(path)
            return ImportResult.new(
              success: false,
              message: "Astro project directory not found: #{path}",
            )
          end

          # Astro content lives in src/content/
          content_dir = File.join(path, "src", "content")
          unless Dir.exists?(content_dir)
            return ImportResult.new(
              success: false,
              message: "Astro content directory not found: #{content_dir}",
            )
          end

          files = collect_markdown_files(content_dir)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No content files found in #{content_dir}",
            )
          end

          files.each do |file_path|
            begin
              result = import_file(file_path, content_dir, output_dir, options.drafts, options.verbose, options.force)
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
            message: "Astro import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        private def collect_markdown_files(dir : String) : Array(String)
          files = [] of String
          scan_dir(dir, files)
          files
        end

        private def scan_dir(dir : String, files : Array(String))
          Dir.each_child(dir) do |entry|
            full_path = File.join(dir, entry)
            if File.directory?(full_path)
              scan_dir(full_path, files)
            elsif entry.ends_with?(".md") || entry.ends_with?(".mdx")
              files << full_path
            end
          end
        end

        private def import_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          raw = File.read(file_path)
          frontmatter_yaml, body = parse_astro_file(raw)

          fields = Hash(String, (String | Bool | Array(String))?).new

          if frontmatter_yaml
            yaml = YAML.parse(frontmatter_yaml)

            # Title
            if title = yaml["title"]?
              fields["title"] = title.as_s? || title.raw.to_s
            end

            # Date (pubDate is Astro's convention)
            if date_val = yaml["pubDate"]? || yaml["date"]? || yaml["publishDate"]?
              case date_val.raw
              when Time
                fields["date"] = format_date(date_val.raw.as(Time))
              when String
                parsed = parse_date(date_val.as_s)
                fields["date"] = format_date(parsed) if parsed
              end
            end

            # Updated date
            if updated = yaml["updatedDate"]? || yaml["updated"]? || yaml["lastmod"]?
              case updated.raw
              when Time
                fields["updated"] = format_date(updated.raw.as(Time))
              when String
                parsed = parse_date(updated.as_s)
                fields["updated"] = format_date(parsed) if parsed
              end
            end

            # Draft
            if draft = yaml["draft"]?
              if draft.raw == true
                unless include_drafts
                  return :skipped
                end
                fields["draft"] = true
              end
            end

            # Description
            if desc = yaml["description"]?
              fields["description"] = desc.as_s? || desc.raw.to_s
            end

            # Tags
            tags = [] of String
            if tags_val = yaml["tags"]?
              case tags_val.raw
              when Array
                tags_val.as_a.each { |t| tags << (t.as_s? || t.raw.to_s) }
              when String
                tags_val.as_s.split(/[\s,]+/).each { |t| tags << t.strip unless t.strip.empty? }
              end
            end

            # Categories
            if cats = yaml["categories"]?
              case cats.raw
              when Array
                cats.as_a.each { |c| tags << (c.as_s? || c.raw.to_s) }
              end
            end

            tags = tags.uniq
            fields["tags"] = tags unless tags.empty?

            # Image (heroImage is Astro's blog template convention)
            if image = yaml["heroImage"]? || yaml["image"]? || yaml["cover"]?
              case image.raw
              when String
                fields["image"] = image.as_s
              when Hash
                # Handle structured image objects (e.g., { src: "...", alt: "..." })
                if src = image["src"]?
                  fields["image"] = src.as_s? || src.raw.to_s
                end
              end
            end

            # Author
            if author = yaml["author"]?
              fields["author"] = author.as_s? || author.raw.to_s
            end
          end

          # Fallback title from filename
          unless fields.has_key?("title")
            name = File.basename(file_path, File.extname(file_path))
            fields["title"] = name.gsub(/[-_]/, " ").split.map(&.capitalize).join(" ")
          end

          # Warn about MDX components in .mdx files
          if file_path.ends_with?(".mdx")
            if body.includes?("import ") || body.matches?(/<[A-Z]/)
              Logger.warn "MDX components detected in #{file_path} — manual conversion may be needed"
            end
            # Strip import statements
            body = body.gsub(/^import\s+.+$\n?/m, "")
          end

          # Determine section from content collection name
          relative = file_path.sub(content_dir, "").lstrip('/')
          parts = relative.split("/")
          section = if parts.size > 1
                      parts[0] # Collection name (e.g., "blog", "posts")
                    else
                      "posts"
                    end

          slug = slugify(File.basename(file_path, File.extname(file_path)))

          frontmatter = generate_frontmatter(fields)
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose, force)
          written ? :imported : :skipped
        end

        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def parse_astro_file(content : String) : Tuple(String?, String)
          if match = YAML_FM_REGEX.match(content)
            yaml_str = match[1].strip
            body = match[2].strip
            return {yaml_str, body}
          end
          {nil, content.strip}
        end
      end
    end
  end
end
