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

        # Slugs written this run, to disambiguate date-prefix-strip collisions.
        @used_slugs = Set(String).new

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
              message: "Jekyll site directory not found: #{path}",
            )
          end

          @used_slugs.clear
          files = collect_files(path, options.drafts)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No Jekyll posts found in #{path}",
            )
          end

          files.each do |file_info|
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

          if wrapped > 0
            Logger.warn "#{wrapped} file(s) contained unconverted Liquid constructs. Imports kept the raw syntax — each will render as literal text until you hand-convert them."
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

          # Recursive: Jekyll supports organizing posts in subfolders
          # (`_posts/tech/2024-01-02-post.md` is a common category layout);
          # a flat glob silently ignored every nested post.
          posts_dir = File.join(path, "_posts")
          if Dir.exists?(posts_dir)
            walk_files(posts_dir).sort.each do |file|
              files << {path: file, draft: false}
            end
          end

          if include_drafts
            drafts_dir = File.join(path, "_drafts")
            if Dir.exists?(drafts_dir)
              walk_files(drafts_dir).sort.each do |file|
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
          force : Bool,
        ) : Symbol
          raw = read_text(file_info[:path])
          frontmatter_yaml, body = split_yaml_frontmatter(raw)
          filename = File.basename(file_info[:path])

          # Extract slug and date from filename
          slug = extract_slug(filename)
          filename_date = extract_date_from_filename(filename)

          # Parse YAML frontmatter. Comment-only or scalar frontmatter parses
          # to a non-hash document whose `[]?` raises ("Expected Array or
          # Hash, not Nil"), which used to drop the whole post as an error —
          # treat anything but a mapping as no frontmatter.
          fields = Hash(String, FieldValue).new
          yaml = frontmatter_yaml ? YAML.parse(frontmatter_yaml) : nil
          yaml = nil unless yaml.try(&.as_h?)

          if yaml
            # Title
            if title = yaml["title"]?
              fields["title"] = title.as_s? || title.raw.to_s
            end

            # Date from frontmatter (filename fallback below also covers an
            # unparseable frontmatter date, which used to suppress it)
            if date_val = yaml["date"]?
              case date_val.raw
              when Time
                fields["date"] = format_date(date_val.raw.as(Time))
              when String
                parsed = parse_date(date_val.as_s)
                fields["date"] = format_date(parsed) if parsed
              end
            end

            # Layout -> template
            if layout = yaml["layout"]?
              fields["template"] = layout.as_s? || layout.raw.to_s
            end

            # Categories and tags are kept as separate taxonomies so the
            # imported content matches hwaro's scaffold taxonomy shape
            # (`[[taxonomies]]` defines both keys distinctly).
            categories = [] of String

            if cats = yaml["categories"]?
              case cats.raw
              when Array
                cats.as_a.each { |c| categories << (c.as_s? || c.raw.to_s) }
              when String
                cats.as_s.split(/[\s,]+/).each { |c| categories << c.strip unless c.strip.empty? }
              end
            end

            if cat = yaml["category"]?
              if cat_s = cat.as_s?
                cat_s.split(/[\s,]+/).each { |c| categories << c.strip unless c.strip.empty? }
              end
            end

            categories = categories.uniq
            fields["categories"] = categories unless categories.empty?

            tags = [] of String
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

            # `header:` may be a hash (Minimal-Mistakes style `header: {image: …}`)
            # or a plain scalar string path. `YAML::Any#[]?` RAISES on a scalar
            # ("Expected Array or Hash, not String"), which the per-file rescue
            # would swallow — silently dropping the whole post. Guard on `as_h?`
            # first; indexing the YAML::Any is then safe (it's a hash).
            if (header = yaml["header"]?) && header.as_h?
              if header_image = header["image"]?
                fields["image"] = (header_image.as_s? || header_image.raw.to_s) unless fields.has_key?("image")
              end
            end
          end

          # Fall back to the filename date when frontmatter had none (or an
          # unparseable one).
          if !fields.has_key?("date") && filename_date
            fields["date"] = format_date(filename_date)
          end

          # Mark drafts
          if file_info[:draft]
            fields["draft"] = true
          end

          # Track files that contain unconverted Liquid constructs. The
          # per-file warning stays for verbose consumers; the `run`
          # method emits a single summary warning with the total so
          # users know how many files need manual conversion even when
          # the per-file lines scroll off.
          has_liquid = body.matches?(LIQUID_TAG_PATTERN)
          if has_liquid
            Logger.warn "Liquid tags detected in #{file_info[:path]} — manual conversion needed."
          end

          # Use slug from filename, or slugify the title
          if slug.empty?
            if title = fields["title"]?.as?(String)
              slug = slugify(title)
            else
              slug = "untitled"
            end
          end

          # Stripping the unique `YYYY-MM-DD-` prefix can collide two posts
          # (`2023-01-01-recap.md` + `2024-01-01-recap.md` → `recap.md`);
          # re-attach the date to the later one instead of losing it.
          unless @used_slugs.add?(slug)
            candidate = filename_date ? "#{slug}-#{filename_date.to_s("%Y-%m-%d")}" : slug
            n = 1
            until @used_slugs.add?(candidate)
              candidate = "#{slug}-#{n}"
              n += 1
            end
            Logger.warn "Slug collision after date-prefix strip: writing #{candidate} for #{file_info[:path]}"
            slug = candidate
          end

          frontmatter = generate_frontmatter(fields)
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))
          written = write_content_file(output_dir, "posts", slug, frontmatter, body, verbose, force)

          return :skipped unless written
          has_liquid ? :imported_wrapped : :imported
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
          end
        end
      end
    end
  end
end
