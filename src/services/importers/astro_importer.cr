require "yaml"
require "./base"
require "../../content/processors/fence_tracker"

module Hwaro
  module Services
    module Importers
      class AstroImporter < Base
        # Astro uses content collections in src/content/ directory
        # Frontmatter is YAML between --- delimiters

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir

          reset_written_paths

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

          files = collect_markdown_files(content_dir, path)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No content files found in #{content_dir}",
              skipped_count: outside_source_skips,
            )
          end

          import_each(files, "Astro", wrapped_note: "contained MDX components. Imports kept the raw markup — each will render as literal text until you hand-convert them.") do |file_path|
            import_file(file_path, content_dir, output_dir, options.drafts, options.verbose, options.force)
          end
        end

        private def collect_markdown_files(dir : String, source_root : String) : Array(String)
          walk_files(dir, [".md", ".mdx"], source_root: source_root)
        end

        private def import_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          raw = read_text(file_path)
          frontmatter_yaml, body = split_yaml_frontmatter(raw)

          fields = Hash(String, FieldValue).new

          # Non-mapping frontmatter (comment-only, scalar) would raise on []?.
          yaml = frontmatter_yaml ? YAML.parse(frontmatter_yaml) : nil
          yaml = nil unless yaml.try(&.as_h?)

          if yaml
            # Title
            if title = yaml["title"]?
              fields["title"] = yaml_string(title)
            end

            # Date (pubDate is Astro's convention). `first_present`, not
            # `||`: a present-but-null key would discard the fallbacks.
            if date_val = first_present(yaml, "pubDate", "date", "publishDate")
              assign_date_field(fields, "date", date_val)
            end

            # Updated date
            if updated = first_present(yaml, "updatedDate", "updated", "lastmod")
              assign_date_field(fields, "updated", updated)
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
              fields["description"] = yaml_string(desc)
            end

            # Tags
            tags = [] of String
            if tags_val = yaml["tags"]?
              collect_string_list(tags_val, into: tags)
            end

            # Categories
            if cats = yaml["categories"]?
              case cats.raw
              when Array
                cats.as_a.each { |c| tags << yaml_string(c) }
              end
            end

            tags = tags.uniq
            fields["tags"] = tags unless tags.empty?

            # Image (heroImage is Astro's blog template convention)
            if image = first_present(yaml, "heroImage", "image", "cover")
              case image.raw
              when String
                fields["image"] = image.as_s
              when Hash
                # Handle structured image objects (e.g., { src: "...", alt: "..." })
                if src = image["src"]?
                  fields["image"] = yaml_string(src)
                end
              end
            end

            # Author — Hwaro's parser only reads the plural `authors` array,
            # so map Astro's singular `author` onto it (Astro templates
            # occasionally use a list, so accept both shapes).
            if author = yaml["author"]?
              authors = [] of String
              case author.raw
              when Array
                author.as_a.each { |a| authors << yaml_string(a) }
              else
                authors << yaml_string(author)
              end
              fields["authors"] = authors unless authors.empty?
            end
          end

          # Fallback title from filename
          unless fields.has_key?("title")
            name = File.basename(file_path, File.extname(file_path))
            fields["title"] = name.gsub(/[-_]/, " ").split.map(&.capitalize).join(" ")
          end

          # MDX handling: strip import statements (no Crinja equivalent).
          # Track remaining JSX-ish component markup so the `run` method
          # can emit a single summary warning.
          has_mdx_components = false
          if file_path.ends_with?(".mdx")
            body = strip_mdx_imports(body)
            if body.matches?(/<[A-Z]/)
              Logger.warn "MDX components detected in #{file_path} — manual conversion needed."
              has_mdx_components = true
            end
          end

          # Determine section from content collection name (e.g. "blog", "posts")
          section = top_section_from_path(file_path, content_dir, "posts")

          # Page bundles (`blog/my-post/index.md`): the slug is the bundle
          # directory — a literal "index" slug collides across every bundle
          # in the section, silently dropping all but the first.
          base = File.basename(file_path, File.extname(file_path))
          if base == "index"
            parent = File.basename(File.dirname(file_path))
            base = parent unless File.same?(File.dirname(file_path), content_dir)
          end
          slug = Utils::TextUtils.slugify(base)

          frontmatter = generate_frontmatter(fields)
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose, force)
          return :skipped unless written
          has_mdx_components ? :imported_wrapped : :imported
        end

        # Drop MDX's top-level ESM `import` statements. Only lines outside
        # fenced code are statements: a JavaScript sample in a ``` block
        # starting with `import …` is article content, and deleting it
        # mangled every MDX post that shows how to import a module.
        #
        # A multi-line `import {` statement is dropped through the line that
        # starts with its closing `}`, but only while the lines in between
        # look like a specifier list (identifiers, `as`, commas, `//`
        # comments). Anything else — a blank line, prose — means it was not
        # a statement after all, and the held lines are kept, so an
        # unclosed `import {` can't swallow the rest of the article.
        private def strip_mdx_imports(body : String) : String
          tracker = Content::Processors::FenceTracker.new
          pending : String? = nil
          String.build do |io|
            body.each_line(chomp: false) do |line|
              fenced = tracker.fence_line?(line)
              if held = pending
                code = line.sub(%r{//.*}, "").strip
                if !fenced && code.starts_with?('}')
                  pending = nil
                  next
                elsif !fenced && code.matches?(/\A[\w$\s,]+\z/)
                  pending = held + line
                  next
                end
                io << held
                pending = nil
              end

              if fenced
                io << line
              elsif line.matches?(/\Aimport[ \t]/)
                code = line.sub(%r{//.*}, "")
                pending = line if code.includes?('{') && !code.includes?('}')
              else
                io << line
              end
            end
            # Never closed: not a statement, keep it.
            pending.try { |held| io << held }
          end
        end
      end
    end
  end
end
