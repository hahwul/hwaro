require "yaml"
require "./base"

module Hwaro
  module Services
    module Importers
      class JekyllImporter < Base
        # Regex to match Jekyll post filenames: YYYY-MM-DD-slug.md
        FILENAME_PATTERN = /^(\d{4}-\d{2}-\d{2})-(.+)\.(md|markdown)$/

        # Regex to detect Liquid tags in content
        LIQUID_TAG_PATTERN = /\{[%{].*?[%}]\}/

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0

          unless Dir.exists?(path)
            return ImportResult.new(
              success: false,
              message: "Jekyll site directory not found: #{path}",
            )
          end

          files = collect_files(path, options.drafts)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No Jekyll posts found in #{path}",
            )
          end

          files.each do |file_info|
            begin
              result = import_file(file_info, output_dir, options.verbose)
              case result
              when :imported
                imported += 1
              when :skipped
                skipped += 1
              end
            rescue ex
              errors += 1
              Logger.warn "Error importing #{file_info[:path]}: #{ex.message}"
            end
          end

          ImportResult.new(
            success: imported > 0 || errors == 0,
            message: "Jekyll import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        private def collect_files(path : String, include_drafts : Bool) : Array(NamedTuple(path: String, draft: Bool))
          files = [] of NamedTuple(path: String, draft: Bool)

          posts_dir = File.join(path, "_posts")
          if Dir.exists?(posts_dir)
            Dir.glob(File.join(posts_dir, "*.{md,markdown}")).each do |file|
              files << {path: file, draft: false}
            end
          end

          if include_drafts
            drafts_dir = File.join(path, "_drafts")
            if Dir.exists?(drafts_dir)
              Dir.glob(File.join(drafts_dir, "*.{md,markdown}")).each do |file|
                files << {path: file, draft: true}
              end
            end
          end

          files
        end

        private def import_file(
          file_info : NamedTuple(path: String, draft: Bool),
          output_dir : String,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_info[:path])
          frontmatter_yaml, body = parse_jekyll_file(raw)
          filename = File.basename(file_info[:path])

          # Extract slug and date from filename
          slug = extract_slug(filename)
          filename_date = extract_date_from_filename(filename)

          # Parse YAML frontmatter
          fields = Hash(String, String | Bool | Array(String) | Nil).new

          if frontmatter_yaml
            yaml = YAML.parse(frontmatter_yaml)

            # Title
            if title = yaml["title"]?
              fields["title"] = title.as_s? || title.raw.to_s
            end

            # Date: prefer frontmatter, fall back to filename
            if date_val = yaml["date"]?
              case date_val.raw
              when Time
                fields["date"] = format_date(date_val.raw.as(Time))
              when String
                parsed = parse_date(date_val.as_s)
                fields["date"] = format_date(parsed) if parsed
              end
            elsif filename_date
              fields["date"] = format_date(filename_date)
            end

            # Layout -> template
            if layout = yaml["layout"]?
              fields["template"] = layout.as_s? || layout.raw.to_s
            end

            # Tags: merge categories and tags
            tags = [] of String

            if cats = yaml["categories"]?
              case cats.raw
              when Array
                cats.as_a.each { |c| tags << (c.as_s? || c.raw.to_s) }
              when String
                cats.as_s.split(/[\s,]+/).each { |c| tags << c.strip unless c.strip.empty? }
              end
            end

            if cat = yaml["category"]?
              if cat_s = cat.as_s?
                cat_s.split(/[\s,]+/).each { |c| tags << c.strip unless c.strip.empty? }
              end
            end

            if tag_val = yaml["tags"]?
              case tag_val.raw
              when Array
                tag_val.as_a.each { |t| tags << (t.as_s? || t.raw.to_s) }
              when String
                tag_val.as_s.split(/[\s,]+/).each { |t| tags << t.strip unless t.strip.empty? }
              end
            end

            tags = tags.uniq
            fields["tags"] = tags unless tags.empty?

            # Draft status
            if published = yaml["published"]?
              if published.raw == false
                fields["draft"] = true
              end
            end

            # Description
            if excerpt = yaml["excerpt"]?
              fields["description"] = excerpt.as_s? || excerpt.raw.to_s
            elsif description = yaml["description"]?
              fields["description"] = description.as_s? || description.raw.to_s
            end

            # Image
            if image = yaml["image"]?
              case image.raw
              when String
                fields["image"] = image.as_s? || image.raw.to_s
              when Hash
                # Handle nested image object (e.g., image.path or similar)
              end
            end

            if header = yaml["header"]?
              if header_image = header["image"]?
                fields["image"] = (header_image.as_s? || header_image.raw.to_s) unless fields.has_key?("image")
              end
            end
          else
            # No frontmatter; use filename date if available
            if filename_date
              fields["date"] = format_date(filename_date)
            end
          end

          # Mark drafts
          if file_info[:draft]
            fields["draft"] = true
          end

          # Warn about Liquid tags in body
          if body.matches?(LIQUID_TAG_PATTERN)
            Logger.warn "Liquid tags detected in #{file_info[:path]} - manual conversion may be needed"
          end

          # Use slug from filename, or slugify the title
          if slug.empty?
            if title = fields["title"]?.as?(String)
              slug = slugify(title)
            else
              slug = "untitled"
            end
          end

          frontmatter = generate_frontmatter(fields)
          written = write_content_file(output_dir, "posts", slug, frontmatter, body, verbose)

          written ? :imported : :skipped
        end

        # Regex to match YAML frontmatter: opening --- on first line,
        # closing --- on its own line. Uses multiline mode so ^ matches line starts.
        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def parse_jekyll_file(content : String) : Tuple(String?, String)
          if match = YAML_FM_REGEX.match(content)
            yaml_str = match[1].strip
            body = match[2].strip
            return {yaml_str, body}
          end

          {nil, content.strip}
        end

        private def extract_slug(filename : String) : String
          if match = FILENAME_PATTERN.match(filename)
            match[2]
          else
            # Strip extension and use as slug
            name = File.basename(filename, File.extname(filename))
            slugify(name)
          end
        end

        private def extract_date_from_filename(filename : String) : Time?
          if match = FILENAME_PATTERN.match(filename)
            parse_date(match[1])
          else
            nil
          end
        end
      end
    end
  end
end
