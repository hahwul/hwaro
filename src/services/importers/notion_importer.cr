require "yaml"
require "set"
require "uri"
require "./base"
require "../../content/processors/fence_tracker"

module Hwaro
  module Services
    module Importers
      class NotionImporter < Base
        # Notion exported markdown uses YAML frontmatter or embedded metadata
        # Notion export structure: folder per page, with .md files and assets

        # Slugs written this run, to disambiguate collisions.
        @used_slugs = Set(String).new

        # Final slug of every file in this run, by source path, and by the
        # 32-hex id Notion appends to each export filename. Links between
        # pages carry that id, and the slug a page ends up with depends on
        # which same-titled page claimed the plain slug first.
        @file_slugs = Hash(String, String).new
        @slug_by_id = Hash(String, String).new

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir

          @used_slugs.clear
          @file_slugs.clear
          @slug_by_id.clear
          reset_written_paths

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
              skipped_count: outside_source_skips,
            )
          end

          assign_slugs(files)

          import_each(files, "Notion") do |file_path|
            import_file(file_path, path, output_dir, options.verbose, options.force)
          end
        end

        private def collect_markdown_files(path : String) : Array(String)
          walk_files(path, source_root: path)
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
              if (title = yaml_hash["title"]?) && (title_text = yaml_title(title))
                fields["title"] = title_text
              end

              if date_val = yaml_hash["date"]?
                assign_date_field(fields, "date", date_val)
              end

              if tags_val = yaml_hash["tags"]?
                tags = [] of String
                collect_string_list(tags_val, into: tags)
                fields["tags"] = tags unless tags.empty?
              end

              if desc = yaml_hash["description"]?
                fields["description"] = yaml_string(desc)
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

          slug = @file_slugs[file_path]? || slug_from_notion_filename(file_path)

          section = "posts"

          frontmatter = generate_frontmatter(fields)
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose, force)
          written ? :imported : :skipped
        end

        # Give every file its final slug up front, in walk order, so a link to a
        # page can be written before that page is. Same-titled pages get `-1`,
        # `-2`, … suffixes; the first in walk order keeps the plain slug.
        private def assign_slugs(files : Array(String)) : Nil
          files.each do |file_path|
            slug = slug_from_notion_filename(file_path)
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
            @file_slugs[file_path] = slug
            if id = notion_id(File.basename(file_path, File.extname(file_path)))
              @slug_by_id[id] ||= slug
            end
          end
        end

        # The 32-hex page id a Notion export filename ends with, lowercased.
        private def notion_id(name : String) : String?
          name[/[0-9a-fA-F]{32}\z/]?.try(&.downcase)
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
          file_slug(title)
        end

        # A Notion callout: a blockquote opened by one emoji/pictograph. Any
        # other single punctuation character after `> ` (`-`, `>`, `#`, `—`)
        # is ordinary quote content.
        CALLOUT_PREFIX = /\A> [\p{So}]\x{FE0F}?[ \t]+/

        private def clean_notion_content(body : String) : String
          tracker = Content::Processors::FenceTracker.new
          String.build do |io|
            body.each_line(chomp: false) do |line|
              if tracker.fence_line?(line)
                io << line
              else
                # Convert Notion callout blocks (> emoji text) to plain
                # blockquotes. Example: '> 💡 Some tip' -> '> Some tip'
                line = line.sub(CALLOUT_PREFIX, "> ")
                io << clean_notion_text(line)
              end
            end
          end
        end

        private def code_spans(line : String) : Array(Range(Int32, Int32))
          spans = [] of Range(Int32, Int32)
          line.scan(/`+[^`]*`+/) { |m| spans << (m.begin(0)..(m.end(0) - 1)) } if line.includes?('`')
          spans
        end

        # Rewrites one line. A match that STARTS inside an inline code span is
        # literal text; one that merely contains a span (`[`code` page](x.md)`)
        # is still a link.
        private def clean_notion_text(line : String) : String
          code = code_spans(line)

          # Convert Notion bookmark embeds to links
          result = line.gsub(/\[bookmark\]\((.+?)\)/) do |match|
            code.any?(&.includes?($~.begin(0))) ? match : "[#{$1}](#{$1})"
          end

          # Rewrite internal subpage links (relative targets ending in .md containing a 32-hex suffix)
          code = code_spans(result)
          result.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do |match|
            next match if code.any?(&.includes?($~.begin(0)))
            text = $1
            target = $2
            if target.ends_with?(".md") && !target.starts_with?("http://") && !target.starts_with?("https://")
              # `scrub`: URI.decode can materialize invalid UTF-8 (`%ff`),
              # and the regex below raises on it — dropping the whole note.
              target_decoded = URI.decode(target).scrub
              if /[0-9a-fA-F]{32}/.match(target_decoded)
                filename = File.basename(target_decoded, ".md")
                clean_name = filename.sub(/\s+[0-9a-f]{16,}$/i, "").strip
                # The slug the target page was actually written under (it may
                # carry a `-N` collision suffix); the title alone cannot tell
                # same-titled pages apart.
                slug = notion_id(filename).try { |id| @slug_by_id[id]? } || file_slug(clean_name)
                "[#{text}](/posts/#{slug}/)"
              else
                match
              end
            else
              match
            end
          end
        end
      end
    end
  end
end
