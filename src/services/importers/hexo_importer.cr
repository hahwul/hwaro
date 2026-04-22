require "yaml"
require "./base"

module Hwaro
  module Services
    module Importers
      class HexoImporter < Base
        # Hexo post filename pattern: YYYY-MM-DD-slug.md
        FILENAME_PATTERN = /^(\d{4}-\d{2}-\d{2})-(.+)\.(md|markdown)$/

        # Hexo tag plugin pattern: {% tag_name args %}
        HEXO_TAG_PATTERN = /\{%\s*\w+.*?%\}/

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0
          wrapped = 0

          unless Dir.exists?(path)
            return ImportResult.new(
              success: false,
              message: "Hexo source directory not found: #{path}",
            )
          end

          files = collect_files(path, options.drafts)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No Hexo posts found in #{path}",
            )
          end

          files.each do |file_info|
            begin
              result = import_file(file_info, output_dir, options.verbose, options.force)
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
              Logger.warn "Error importing #{file_info[:path]}: #{ex.message}"
            end
          end

          if wrapped > 0
            Logger.warn "#{wrapped} file(s) contained Hexo tag plugins. Imports kept the raw syntax — each will render as literal text until you hand-convert them."
          end

          ImportResult.new(
            success: imported > 0 || errors == 0,
            message: "Hexo import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        private def collect_files(path : String, include_drafts : Bool) : Array(NamedTuple(path: String, draft: Bool))
          files = [] of NamedTuple(path: String, draft: Bool)

          # Hexo stores posts in source/_posts/
          posts_dir = File.join(path, "source", "_posts")
          if Dir.exists?(posts_dir)
            scan_markdown(posts_dir).each do |file|
              files << {path: file, draft: false}
            end
          end

          if include_drafts
            drafts_dir = File.join(path, "source", "_drafts")
            if Dir.exists?(drafts_dir)
              scan_markdown(drafts_dir).each do |file|
                files << {path: file, draft: true}
              end
            end
          end

          files
        end

        private def scan_markdown(dir : String) : Array(String)
          files = [] of String
          Dir.each_child(dir) do |entry|
            full_path = File.join(dir, entry)
            if File.directory?(full_path)
              scan_markdown(full_path).each { |f| files << f }
            elsif entry.ends_with?(".md") || entry.ends_with?(".markdown")
              files << full_path
            end
          end
          files
        end

        private def import_file(
          file_info : NamedTuple(path: String, draft: Bool),
          output_dir : String,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          raw = File.read(file_info[:path])
          frontmatter_yaml, body = parse_hexo_file(raw)
          filename = File.basename(file_info[:path])

          fields = Hash(String, (String | Bool | Array(String))?).new

          slug = extract_slug(filename)
          filename_date = extract_date_from_filename(filename)

          if frontmatter_yaml
            yaml = YAML.parse(frontmatter_yaml)

            # Title
            if title = yaml["title"]?
              fields["title"] = title.as_s? || title.raw.to_s
            end

            # Date
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

            # Updated
            if updated = yaml["updated"]?
              case updated.raw
              when Time
                fields["updated"] = format_date(updated.raw.as(Time))
              when String
                parsed = parse_date(updated.as_s)
                fields["updated"] = format_date(parsed) if parsed
              end
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

            tags = tags.uniq
            fields["tags"] = tags unless tags.empty?

            # Categories — preserve as their own taxonomy key. Hexo supports
            # nested arrays (`[[tech, rust], [life]]`) for hierarchical
            # categories; we flatten the hierarchy since hwaro's taxonomy
            # is currently flat. The values stay distinct from tags.
            categories = [] of String

            if cats = yaml["categories"]?
              case cats.raw
              when Array
                cats.as_a.each do |c|
                  case c.raw
                  when Array
                    c.as_a.each { |sub| categories << (sub.as_s? || sub.raw.to_s) }
                  else
                    categories << (c.as_s? || c.raw.to_s)
                  end
                end
              when String
                cats.as_s.split(/[\s,]+/).each { |c| categories << c.strip unless c.strip.empty? }
              end
            end

            categories = categories.uniq
            fields["categories"] = categories unless categories.empty?

            # Description
            if desc = yaml["description"]?
              fields["description"] = desc.as_s? || desc.raw.to_s
            elsif excerpt = yaml["excerpt"]?
              fields["description"] = excerpt.as_s? || excerpt.raw.to_s
            end

            # Image / thumbnail
            if image = yaml["cover"]?
              fields["image"] = image.as_s? || image.raw.to_s
            elsif image = yaml["thumbnail"]?
              fields["image"] = image.as_s? || image.raw.to_s
            end

            # Permalink slug — normalize to safe filename
            if permalink = yaml["permalink"]?
              if ps = permalink.as_s?
                unless ps.empty?
                  # Strip leading/trailing slashes and extensions, take last segment
                  normalized = ps.strip("/").sub(/\.\w+$/, "")
                  parts = normalized.split("/")
                  slug = slugify(parts.last) unless parts.empty?
                end
              end
            end
          else
            if filename_date
              fields["date"] = format_date(filename_date)
            end
          end

          # Mark drafts
          if file_info[:draft]
            fields["draft"] = true
          end

          # Handle Hexo's <!-- more --> excerpt separator.
          body = body.gsub(/<!--\s*more\s*-->/, "")

          # Track files with Hexo tag plugins; the `run` method emits a
          # single summary so the user knows how many files need manual
          # conversion even when per-file warnings scroll off.
          has_hexo_tags = body.matches?(HEXO_TAG_PATTERN)
          if has_hexo_tags
            Logger.warn "Hexo tag plugins detected in #{file_info[:path]} — manual conversion needed."
          end

          if slug.empty?
            if title = fields["title"]?.as?(String)
              slug = slugify(title)
            else
              slug = "untitled"
            end
          end

          frontmatter = generate_frontmatter(fields)
          written = write_content_file(output_dir, "posts", slug, frontmatter, body.strip, verbose, force)
          return :skipped unless written
          has_hexo_tags ? :imported_wrapped : :imported
        end

        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def parse_hexo_file(content : String) : Tuple(String?, String)
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
            name = File.basename(filename, File.extname(filename))
            slugify(name)
          end
        end

        private def extract_date_from_filename(filename : String) : Time?
          if match = FILENAME_PATTERN.match(filename)
            parse_date(match[1])
          end
        end
      end
    end
  end
end
