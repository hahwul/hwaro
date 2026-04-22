require "yaml"
require "./base"

module Hwaro
  module Services
    module Importers
      class ObsidianImporter < Base
        # Obsidian wiki-link pattern: [[Page Name]] or [[Page Name|Display Text]]
        WIKILINK_PATTERN = /\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]/

        # Obsidian embed pattern: ![[filename]]
        EMBED_PATTERN = /!\[\[([^\]]+?)\]\]/

        # Obsidian tag pattern: #tag (but not inside code blocks or headings)
        OBSIDIAN_TAG_PATTERN = /(?<!\w)#([a-zA-Z][\w\-\/]*)/

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0

          unless Dir.exists?(path)
            return ImportResult.new(
              success: false,
              message: "Obsidian vault directory not found: #{path}",
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
              result = import_file(file_path, path, output_dir, options.drafts, options.verbose, options.force)
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
            message: "Obsidian import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
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
            # Skip hidden directories (like .obsidian, .trash)
            if File.directory?(full_path)
              scan_dir(full_path, files) unless entry.starts_with?(".")
            elsif entry.ends_with?(".md") || entry.ends_with?(".markdown")
              files << full_path
            end
          end
        end

        private def import_file(
          file_path : String,
          base_path : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          raw = File.read(file_path)
          frontmatter_yaml, body = parse_markdown_file(raw)

          fields = Hash(String, (String | Bool | Array(String))?).new
          tags = [] of String

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

            if created = yaml["created"]?
              unless fields.has_key?("date")
                case created.raw
                when Time
                  fields["date"] = format_date(created.raw.as(Time))
                when String
                  parsed = parse_date(created.as_s)
                  fields["date"] = format_date(parsed) if parsed
                end
              end
            end

            # Tags from frontmatter
            if tags_val = yaml["tags"]?
              case tags_val.raw
              when Array
                tags_val.as_a.each { |t| tags << (t.as_s? || t.raw.to_s) }
              when String
                tags_val.as_s.split(/[\s,]+/).each { |t| tags << t.strip unless t.strip.empty? }
              end
            end

            if desc = yaml["description"]?
              fields["description"] = desc.as_s? || desc.raw.to_s
            end

            # Draft status
            if draft = yaml["draft"]?
              if draft.raw == true
                unless include_drafts
                  return :skipped
                end
                fields["draft"] = true
              end
            end

            # Aliases
            if aliases_val = yaml["aliases"]?
              aliases = [] of String
              case aliases_val.raw
              when Array
                aliases_val.as_a.each { |a| aliases << (a.as_s? || a.raw.to_s) }
              when String
                aliases << aliases_val.as_s
              end
              fields["aliases"] = aliases unless aliases.empty?
            end
          end

          # Extract inline tags from body (#tag)
          inline_tags = extract_inline_tags(body)
          tags = (tags + inline_tags).uniq

          fields["tags"] = tags unless tags.empty?

          # Title from frontmatter or filename
          unless fields.has_key?("title")
            fields["title"] = File.basename(file_path, File.extname(file_path))
          end

          # Date from file modification time if not in frontmatter
          unless fields.has_key?("date")
            if info = File.info?(file_path)
              fields["date"] = format_date(info.modification_time)
            end
          end

          # Convert Obsidian-specific syntax
          body = convert_obsidian_syntax(body)

          # Determine section from vault folder structure
          relative = file_path.sub(base_path, "").lstrip('/')
          parts = relative.split("/")
          if parts.size > 1
            section = parts[0..-2].join("/")
          else
            section = "posts"
          end

          slug = slugify(fields["title"].as?(String) || File.basename(file_path, File.extname(file_path)))

          frontmatter = generate_frontmatter(fields)
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose, force)
          written ? :imported : :skipped
        end

        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def parse_markdown_file(content : String) : Tuple(String?, String)
          if match = YAML_FM_REGEX.match(content)
            yaml_str = match[1].strip
            body = match[2].strip
            return {yaml_str, body}
          end
          {nil, content.strip}
        end

        private def extract_inline_tags(body : String) : Array(String)
          tags = [] of String
          # Skip code blocks when extracting tags
          in_code_block = false
          fence_close_re : Regex? = nil
          body.each_line do |line|
            if in_code_block
              if fence_close_re.try(&.match(line))
                in_code_block = false
                fence_close_re = nil
              end
              next
            end
            if match = line.match(/^(\s*(`{3,}|~{3,}))/)
              in_code_block = true
              fence_close_re = Regex.new("^\\s*#{Regex.escape(match[2])}\\s*$")
              next
            end
            # Skip headings (all markdown heading levels)
            next if line.matches?(/^\s*\#{1,6}\s/)

            line.scan(OBSIDIAN_TAG_PATTERN) do |tag_match|
              tag = tag_match[1]
              # Convert nested tags (tag/subtag) to just the leaf
              tags << tag.gsub("/", "-")
            end
          end
          tags.uniq
        end

        private def convert_obsidian_syntax(body : String) : String
          result = body

          # Convert embeds ![[file]] to markdown image/link
          result = result.gsub(EMBED_PATTERN) do
            filename = $1
            if filename.matches?(/\.(png|jpg|jpeg|gif|svg|webp|avif)$/i)
              "![#{filename}](#{filename})"
            else
              "[#{filename}](#{filename})"
            end
          end

          # Convert wiki-links [[Page|Display]] to standard markdown links
          result = result.gsub(WIKILINK_PATTERN) do
            page = $1
            display = $~[2]? || page
            slug = slugify(page)
            "[#{display}](#{slug})"
          end

          # Remove inline tags (already extracted to frontmatter)
          in_code_block = false
          fence_close_re : Regex? = nil
          lines = result.split("\n").map do |line|
            if in_code_block
              if fence_close_re.try(&.match(line))
                in_code_block = false
                fence_close_re = nil
              end
              line
            elsif fence_match = line.match(/^(\s*(`{3,}|~{3,}))/)
              in_code_block = true
              fence_close_re = Regex.new("^\\s*#{Regex.escape(fence_match[2])}\\s*$")
              line
            elsif line.matches?(/^\s*\#{1,6}\s/)
              # Preserve markdown headings
              line
            else
              line.gsub(/(?<!\w)#([a-zA-Z][\w\-\/]*)/, "").rstrip
            end
          end
          result = lines.join("\n")

          # Clean up multiple blank lines
          result.gsub(/\n{3,}/, "\n\n")
        end
      end
    end
  end
end
