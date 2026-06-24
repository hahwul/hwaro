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

        # Obsidian tag pattern: #tag (but not inside code blocks, headings,
        # or as a URL fragment like `path/#section`). Requires the `#` to
        # sit at start-of-line or after whitespace — this matches Obsidian's
        # own tag-detection heuristic and avoids treating URL anchors as tags.
        OBSIDIAN_TAG_PATTERN = /(?:^|(?<=\s))#([a-zA-Z][\w\-\/]*)/

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

          # First pass: build a name → URL map of every imported note so
          # second-pass `[[Wiki-Link]]` resolution can produce absolute URLs
          # instead of slugs that resolve relative to the current page.
          # Keys are case-insensitive matches on filename, title, and aliases.
          # The pass also caches each file's raw bytes so the second pass below
          # reuses them instead of re-reading every note from disk (2N → N reads).
          content_cache = {} of String => String
          link_map = build_link_map(files, path, content_cache)

          files.each do |file_path|
            result = import_file(file_path, path, output_dir, options.drafts, options.verbose, options.force, link_map, content_cache)
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
            message: "Obsidian import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        private def collect_markdown_files(path : String) : Array(String)
          walk_files(path, skip_dir: ->(entry : String) { entry.starts_with?(".") })
        end

        # Build a name → URL map covering every note in the vault. Keys are
        # lowercased lookup names: the filename (with and without extension),
        # the front-matter `title`, and every `aliases:` entry. Values are
        # absolute site paths (e.g. `/posts/note-2/`) computed the same way
        # `import_file` builds the on-disk destination.
        #
        # The lookup is case-insensitive because Obsidian itself treats
        # wiki-links that way (`[[Note]]` and `[[note]]` resolve to the same
        # file), and Hwaro authors typically lowercase slugs on publish.
        private def build_link_map(files : Array(String), base_path : String, content_cache : Hash(String, String) = {} of String => String) : Hash(String, String)
          map = Hash(String, String).new
          files.each do |file_path|
            raw = File.read(file_path)
            content_cache[file_path] = raw
            fm_yaml, _ = split_yaml_frontmatter(raw)

            # Section mirrors `import_file`'s computation so the URL we
            # emit lands at the same path the file will be written to.
            section, _ = section_from_path(file_path, base_path, "posts")

            basename = File.basename(file_path, File.extname(file_path))
            title = basename
            aliases = [] of String

            if fm_yaml && (yaml = YAML.parse(fm_yaml))
              if t = yaml["title"]?
                title = t.as_s? || t.raw.to_s
              end
              if a = yaml["aliases"]?
                case a.raw
                when Array
                  flatten_yaml_strings(a).each { |s| aliases << s }
                when String
                  aliases << a.as_s
                end
              end
            end

            slug = slugify(title)
            url = "/#{section}/#{slug}/"

            # Register every name a wiki-link could plausibly use.
            [basename, "#{basename}.md", title, *aliases].each do |key|
              next if key.empty?
              map[key.downcase.strip] = url
            end
          rescue ex
            # Don't fail the whole import if one note's YAML is malformed;
            # we just won't be able to resolve links pointing at it. The
            # per-file import below will surface the actual error.
            Logger.debug "build_link_map: skipped #{file_path}: #{ex.message}"
          end
          map
        end

        # Map a `[[Wiki-Link]]` target to either an absolute site URL (when
        # the target was found in the vault) or the slugified fallback (so
        # external references still produce *some* link rather than nothing).
        private def resolve_wikilink(page : String, link_map : Hash(String, String)) : String
          # Obsidian links can include a `#heading` anchor (`[[Note#Section]]`)
          # and `^block-ref` ids (`[[Note#^abc]]`). Strip those before lookup
          # and re-append the anchor in slugified form afterwards.
          name, anchor = page, ""
          if hash_idx = page.index('#')
            name = page[0...hash_idx]
            anchor = page[hash_idx..]
          end

          key = name.strip.downcase
          if url = link_map[key]?
            return anchor.empty? ? url : "#{url}##{slugify(anchor.lchop('#').lchop('^'))}"
          end
          # Unknown target: fall back to a relative slug. This keeps behavior
          # backwards-compatible for vaults that link to pages outside the
          # import scope, and the user can fix up by hand.
          slug = slugify(name)
          anchor.empty? ? slug : "#{slug}##{slugify(anchor.lchop('#').lchop('^'))}"
        end

        private def import_file(
          file_path : String,
          base_path : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
          force : Bool,
          link_map : Hash(String, String) = {} of String => String,
          content_cache : Hash(String, String) = {} of String => String,
        ) : Symbol
          raw = content_cache[file_path]? || File.read(file_path)
          frontmatter_yaml, body = split_yaml_frontmatter(raw)

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
                flatten_yaml_strings(tags_val).each { |t| tags << t }
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
                flatten_yaml_strings(aliases_val).each { |a| aliases << a }
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
          body = convert_obsidian_syntax(body, link_map)

          # Determine section from vault folder structure
          section, _ = section_from_path(file_path, base_path, "posts")

          slug = slugify(fields["title"].as?(String) || File.basename(file_path, File.extname(file_path)))

          frontmatter = generate_frontmatter(fields)
          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose, force)
          written ? :imported : :skipped
        end

        # Recursively flatten a YAML array value into a flat list of strings.
        # Obsidian users write nested arrays for tags (e.g. `tags: [[a, b]]`)
        # and the naive per-element `t.raw.to_s` on an Array element yielded
        # a JSON-literal tag like `["a", "b"]`. Skips nested hashes since
        # they don't map to a scalar tag — the caller can warn separately
        # if needed.
        private def flatten_yaml_strings(value : YAML::Any) : Array(String)
          result = [] of String
          case value.raw
          when Array
            value.as_a.each do |item|
              flatten_yaml_strings(item).each { |s| result << s }
            end
          when Hash
            # Nested object: skip silently; tags/aliases don't carry objects.
          else
            s = value.as_s? || value.raw.to_s
            result << s unless s.empty?
          end
          result
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

        private def convert_obsidian_syntax(body : String, link_map : Hash(String, String) = {} of String => String) : String
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

          # Convert wiki-links [[Page|Display]] to standard markdown links.
          # Resolve against the prebuilt link_map so the output is an absolute
          # site URL (e.g. `/posts/note-2/`) rather than a same-page-relative
          # slug — the old behavior wrote `[Note2](note2)` which the browser
          # resolved as `<current-page>/note2`, producing 404s.
          result = result.gsub(WIKILINK_PATTERN) do
            page = $1
            display = $~[2]? || page
            target = resolve_wikilink(page, link_map)
            "[#{display}](#{target})"
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
              # Strip inline `#tag` references (already extracted to
              # frontmatter), but require start-of-line or whitespace before
              # the `#` — otherwise we'd eat the `#section` anchor inside a
              # markdown link URL like `[Note](/posts/note/#section)` that
              # the wiki-link conversion above just emitted.
              line.gsub(/(?:^|(?<=\s))#([a-zA-Z][\w\-\/]*)/, "").rstrip
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
