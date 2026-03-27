require "yaml"
require "json"
require "./base"

module Hwaro
  module Services
    module Importers
      class EleventyImporter < Base
        # 11ty supports multiple template formats; we handle Markdown + Nunjucks/Liquid

        # Nunjucks/Liquid tag patterns
        TEMPLATE_TAG_PATTERN = /\{[%{].*?[%}]\}/

        def run(options : Config::Options::ImportOptions) : ImportResult
          path = options.path
          output_dir = options.output_dir
          imported = 0
          skipped = 0
          errors = 0

          unless Dir.exists?(path)
            return ImportResult.new(
              success: false,
              message: "Eleventy project directory not found: #{path}",
            )
          end

          # 11ty content can be anywhere; common locations are src/, posts/, content/
          # Also check the root for .md files
          files = collect_content_files(path)

          if files.empty?
            return ImportResult.new(
              success: true,
              message: "No content files found in #{path}",
            )
          end

          # Load directory data files (11ty convention)
          dir_data = load_directory_data(path)

          files.each do |file_path|
            begin
              result = import_file(file_path, path, output_dir, dir_data, options.drafts, options.verbose)
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
            message: "Eleventy import complete: #{imported} imported, #{skipped} skipped, #{errors} errors",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors,
          )
        end

        private def collect_content_files(path : String) : Array(String)
          files = [] of String
          scan_dir(path, files)
          files
        end

        private def scan_dir(dir : String, files : Array(String))
          Dir.each_child(dir) do |entry|
            full_path = File.join(dir, entry)
            if File.directory?(full_path)
              # Skip common non-content directories
              next if entry.starts_with?(".")
              next if entry == "node_modules"
              next if entry == "_site"
              next if entry == "_includes"
              next if entry == "_layouts"
              next if entry == "_data"
              scan_dir(full_path, files)
            elsif entry.ends_with?(".md") || entry.ends_with?(".markdown")
              files << full_path
            end
          end
        end

        # Load 11ty directory data files (dirname.json or dirname.11tydata.json)
        private def load_directory_data(base_path : String) : Hash(String, Hash(String, YAML::Any))
          data = {} of String => Hash(String, YAML::Any)

          scan_data_files(base_path, base_path, data)
          data
        end

        private def scan_data_files(dir : String, base_path : String, data : Hash(String, Hash(String, YAML::Any)))
          dirname = File.basename(dir)

          # Check for dirname.json
          json_data_file = File.join(dir, "#{dirname}.json")
          eleventydata_file = File.join(dir, "#{dirname}.11tydata.json")

          data_file = if File.exists?(eleventydata_file)
                        eleventydata_file
                      elsif File.exists?(json_data_file)
                        json_data_file
                      else
                        nil
                      end

          if data_file
            begin
              json = JSON.parse(File.read(data_file))
              if json.as_h?
                relative_dir = dir.sub(base_path, "").lstrip('/')
                parsed = {} of String => YAML::Any
                json.as_h.each do |k, v|
                  parsed[k] = json_any_to_yaml_any(v)
                end
                data[relative_dir] = parsed
              end
            rescue
              # Skip invalid data files
            end
          end

          Dir.each_child(dir) do |entry|
            full_path = File.join(dir, entry)
            if File.directory?(full_path) && !entry.starts_with?(".") && entry != "node_modules" && entry != "_site"
              scan_data_files(full_path, base_path, data)
            end
          end
        end

        private def json_any_to_yaml_any(value : JSON::Any) : YAML::Any
          raw = value.raw
          case raw
          when String
            YAML::Any.new(raw)
          when Int64
            YAML::Any.new(raw)
          when Float64
            YAML::Any.new(raw)
          when Bool
            YAML::Any.new(raw)
          when Array
            arr = raw.map { |item| json_any_to_yaml_any(item.as(JSON::Any)) }
            YAML::Any.new(arr.as(Array(YAML::Any)))
          when Hash
            hash = {} of YAML::Any => YAML::Any
            raw.each do |k, v|
              hash[YAML::Any.new(k)] = json_any_to_yaml_any(v.as(JSON::Any))
            end
            YAML::Any.new(hash)
          when Nil
            YAML::Any.new("")
          else
            YAML::Any.new(raw.to_s)
          end
        end

        private def import_file(
          file_path : String,
          base_path : String,
          output_dir : String,
          dir_data : Hash(String, Hash(String, YAML::Any)),
          include_drafts : Bool,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_path)
          frontmatter_yaml, body = parse_eleventy_file(raw)

          fields = Hash(String, String | Bool | Array(String) | Nil).new

          # Merge directory data as defaults
          relative_dir = File.dirname(file_path).sub(base_path, "").lstrip('/')
          merged_yaml = merge_directory_data(dir_data, relative_dir, frontmatter_yaml)

          if merged_yaml
            yaml = YAML.parse(merged_yaml)

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
                date_str = date_val.as_s
                # 11ty special date values
                unless date_str == "Last Modified" || date_str == "Created" || date_str == "git Last Modified" || date_str == "git Created"
                  parsed = parse_date(date_str)
                  fields["date"] = format_date(parsed) if parsed
                end
              end
            end

            # Draft or excluded from collections
            draft_val = yaml["draft"]?
            exclude_val = yaml["eleventyExcludeFromCollections"]?
            is_draft = !draft_val.nil? && draft_val.raw == true
            is_excluded = !exclude_val.nil? && exclude_val.raw == true
            if is_draft || is_excluded
              unless include_drafts
                return :skipped
              end
              fields["draft"] = true
            end

            # Tags (11ty uses tags for collection membership)
            if tags_val = yaml["tags"]?
              tags = [] of String
              case tags_val.raw
              when Array
                tags_val.as_a.each do |t|
                  tag_str = t.as_s? || t.raw.to_s
                  # Skip 11ty collection tags like "post", "posts", "all"
                  next if tag_str == "post" || tag_str == "posts" || tag_str == "all"
                  tags << tag_str
                end
              when String
                tag_str = tags_val.as_s
                unless tag_str == "post" || tag_str == "posts" || tag_str == "all"
                  tags << tag_str
                end
              end
              fields["tags"] = tags unless tags.empty?
            end

            # Description
            if desc = yaml["description"]? || yaml["excerpt"]? || yaml["summary"]?
              fields["description"] = desc.as_s? || desc.raw.to_s
            end

            # Image
            if image = yaml["image"]? || yaml["featuredImage"]? || yaml["cover"]?
              fields["image"] = image.as_s? || image.raw.to_s
            end

            # Template / layout
            if layout = yaml["layout"]?
              fields["template"] = layout.as_s? || layout.raw.to_s
            end
          end

          # Fallback title from filename
          unless fields.has_key?("title")
            name = File.basename(file_path, File.extname(file_path))
            return :skipped if name == "index" # Skip index files without title
            fields["title"] = name.gsub(/[-_]/, " ").split.map(&.capitalize).join(" ")
          end

          # Fallback date from file
          unless fields.has_key?("date")
            # Try to extract date from filename (YYYY-MM-DD-slug.md)
            filename = File.basename(file_path)
            if match = /^(\d{4}-\d{2}-\d{2})/.match(filename)
              parsed = parse_date(match[1])
              fields["date"] = format_date(parsed) if parsed
            elsif info = File.info?(file_path)
              fields["date"] = format_date(info.modification_time)
            end
          end

          # Warn about template tags
          if body.matches?(TEMPLATE_TAG_PATTERN)
            Logger.warn "Template tags detected in #{file_path} — manual conversion may be needed"
          end

          # Determine section
          relative = file_path.sub(base_path, "").lstrip('/')
          parts = relative.split("/")
          section = if parts.size > 1
                      parts[0]
                    else
                      "posts"
                    end

          slug = slugify(File.basename(file_path, File.extname(file_path)))

          frontmatter = generate_frontmatter(fields)
          written = write_content_file(output_dir, section, slug, frontmatter, body.strip, verbose)
          written ? :imported : :skipped
        end

        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def parse_eleventy_file(content : String) : Tuple(String?, String)
          if match = YAML_FM_REGEX.match(content)
            yaml_str = match[1].strip
            body = match[2].strip
            return {yaml_str, body}
          end
          {nil, content.strip}
        end

        # Merge directory data with per-file frontmatter (file data takes precedence)
        private def merge_directory_data(
          dir_data : Hash(String, Hash(String, YAML::Any)),
          relative_dir : String,
          frontmatter_yaml : String?,
        ) : String?
          dir_defaults = dir_data[relative_dir]?

          if frontmatter_yaml
            if dir_defaults
              begin
                file_yaml = YAML.parse(frontmatter_yaml)
                if file_hash = file_yaml.as_h?
                  # Build merged hash: directory defaults + file overrides
                  merged = {} of YAML::Any => YAML::Any
                  dir_defaults.each do |k, v|
                    merged[YAML::Any.new(k)] = v
                  end
                  file_hash.each do |k, v|
                    merged[k] = v
                  end
                  return YAML.dump(merged).strip
                end
              rescue
                return frontmatter_yaml
              end
            end
            frontmatter_yaml
          elsif dir_defaults
            # Build YAML from directory data only
            hash = {} of YAML::Any => YAML::Any
            dir_defaults.each do |k, v|
              hash[YAML::Any.new(k)] = v
            end
            YAML.dump(hash).strip
          else
            nil
          end
        end
      end
    end
  end
end
