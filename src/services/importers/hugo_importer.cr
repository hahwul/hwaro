require "yaml"
require "toml"
require "./base"

module Hwaro
  module Services
    module Importers
      class HugoImporter < Base
        def run(options : Config::Options::ImportOptions) : ImportResult
          hugo_path = options.path
          output_dir = options.output_dir
          include_drafts = options.drafts
          verbose = options.verbose

          content_dir = File.join(hugo_path, "content")

          unless Dir.exists?(content_dir)
            return ImportResult.new(
              success: false,
              message: "Hugo content directory not found: #{content_dir}"
            )
          end

          imported = 0
          skipped = 0
          errors = 0

          scan_markdown_files(content_dir).each do |file_path|
            begin
              result = process_file(file_path, content_dir, output_dir, include_drafts, verbose)
              case result
              when :imported
                imported += 1
              when :skipped
                skipped += 1
              end
            rescue ex
              errors += 1
              Logger.warn "Error processing #{file_path}: #{ex.message}"
            end
          end

          ImportResult.new(
            success: imported > 0 || errors == 0,
            message: "Imported #{imported} items, skipped #{skipped}, errors #{errors}",
            imported_count: imported,
            skipped_count: skipped,
            error_count: errors
          )
        end

        private def scan_markdown_files(content_dir : String) : Array(String)
          files = [] of String
          scan_dir(content_dir, files)
          files
        end

        private def scan_dir(dir : String, files : Array(String))
          Dir.each_child(dir) do |entry|
            path = File.join(dir, entry)
            if File.directory?(path)
              scan_dir(path, files)
            elsif entry.ends_with?(".md") || entry.ends_with?(".markdown")
              files << path
            end
          end
        end

        private def process_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_path)
          fm_data, body = extract_frontmatter(raw)

          # Check draft status (only if frontmatter exists)
          is_draft = fm_data.try { |d| d["draft"]?.try { |v| truthy?(v) } } || false
          if is_draft && !include_drafts
            return :skipped
          end

          # Warn about Hugo shortcodes in body
          if body.includes?("{{<") || body.includes?("{{%")
            Logger.warn "Hugo shortcodes detected in #{file_path} — manual conversion may be needed"
          end

          # Map Hugo fields to Hwaro frontmatter
          fields = {} of String => String | Bool | Array(String) | Nil
          slug_val : String? = nil

          if data = fm_data
            # title
            if title = string_value(data, "title")
              fields["title"] = title
            end

            # date
            if date_str = string_value(data, "date")
              parsed = parse_date(date_str)
              fields["date"] = format_date(parsed) if parsed
            end

            # updated (from lastmod)
            if lastmod_str = string_value(data, "lastmod")
              parsed = parse_date(lastmod_str)
              fields["updated"] = format_date(parsed) if parsed
            end

            # draft
            fields["draft"] = true if is_draft

            # description (from description or summary)
            desc = string_value(data, "description") || string_value(data, "summary")
            fields["description"] = desc if desc

            # tags
            tags = array_string_value(data, "tags")

            # categories — merge into tags
            categories = array_string_value(data, "categories")
            unless categories.empty?
              tags = tags + categories
            end
            fields["tags"] = tags unless tags.empty?

            # series
            if series = string_value(data, "series")
              fields["series"] = series
            elsif series_arr = array_string_value(data, "series")
              fields["series"] = series_arr.first? unless series_arr.empty?
            end

            # weight
            if weight = string_value(data, "weight")
              fields["weight"] = weight
            end

            # slug
            slug_val = string_value(data, "slug")

            # aliases
            aliases = array_string_value(data, "aliases")
            fields["aliases"] = aliases unless aliases.empty?

            # image (from images[0] or featured_image)
            image = extract_image(data)
            fields["image"] = image if image

            # expires (from expiryDate)
            if expires_str = string_value(data, "expiryDate")
              parsed = parse_date(expires_str)
              fields["expires"] = format_date(parsed) if parsed
            end
          end

          frontmatter = generate_frontmatter(fields)

          # Determine relative path for output structure
          relative_path = file_path.sub(content_dir, "").lstrip('/')

          # Determine section and filename
          parts = relative_path.split("/")
          if parts.size > 1
            section = parts[0..-2].join("/")
            filename = parts.last
          else
            section = ""
            filename = parts.first
          end

          # Determine slug for the file
          if filename == "_index.md" || filename == "_index.markdown"
            file_slug = "_index"
          elsif slug_val && !slug_val.empty?
            file_slug = slug_val
          else
            file_slug = filename.sub(/\.(md|markdown)$/, "")
          end

          written = write_content_file(output_dir, section, file_slug, frontmatter, body.strip, verbose)
          written ? :imported : :skipped
        end

        # Regex for TOML frontmatter: +++ on first line, +++ on its own line
        TOML_FM_REGEX = /\A\+\+\+[ \t]*\n(.*?\n?)^\+\+\+[ \t]*$\n?(.*)\z/m

        # Regex for YAML frontmatter: --- on first line, --- on its own line
        YAML_FM_REGEX = /\A---[ \t]*\n(.*?\n?)^---[ \t]*$\n?(.*)\z/m

        private def extract_frontmatter(raw : String) : {Hash(String, TOML::Any)?, String} | {Hash(String, YAML::Any)?, String}
          if raw.starts_with?("+++")
            if match = TOML_FM_REGEX.match(raw)
              toml_str = match[1].strip
              body = match[2].lstrip('\n')
              begin
                data = TOML.parse(toml_str)
                return {data, body}
              rescue
                return {nil, raw}
              end
            end
          elsif raw.starts_with?("---")
            if match = YAML_FM_REGEX.match(raw)
              yaml_str = match[1].strip
              body = match[2].lstrip('\n')
              begin
                yaml_data = YAML.parse(yaml_str)
                if yaml_data.as_h?
                  data = {} of String => TOML::Any
                  yaml_data.as_h.each do |k, v|
                    data[k.as_s] = yaml_any_to_toml_any(v)
                  end
                  return {data, body}
                end
              rescue
                return {nil, raw}
              end
            end
          end

          {nil, raw}
        end

        private def yaml_any_to_toml_any(value : YAML::Any) : TOML::Any
          raw = value.raw
          case raw
          when String
            TOML::Any.new(raw)
          when Int64
            TOML::Any.new(raw)
          when Int32
            TOML::Any.new(raw.to_i64)
          when Float64
            TOML::Any.new(raw)
          when Bool
            TOML::Any.new(raw)
          when Array
            arr = raw.map { |item| yaml_any_to_toml_any(item.as(YAML::Any)) }
            TOML::Any.new(arr)
          when Hash
            hash = {} of String => TOML::Any
            raw.each do |k, v|
              hash[k.as(YAML::Any).as_s] = yaml_any_to_toml_any(v.as(YAML::Any))
            end
            TOML::Any.new(hash)
          when Nil
            TOML::Any.new("")
          when Time
            TOML::Any.new(raw)
          else
            TOML::Any.new(raw.to_s)
          end
        end

        private def string_value(data : Hash(String, TOML::Any), key : String) : String?
          if val = data[key]?
            raw = val.raw
            case raw
            when String
              return raw.empty? ? nil : raw
            when Time
              return raw.to_s("%Y-%m-%dT%H:%M:%S%:z")
            when Int64, Float64
              return raw.to_s
            end
          end
          nil
        end

        private def array_string_value(data : Hash(String, TOML::Any), key : String) : Array(String)
          result = [] of String
          if val = data[key]?
            raw = val.raw
            case raw
            when Array
              raw.each do |item|
                item_raw = item.as(TOML::Any).raw
                result << item_raw.to_s if item_raw
              end
            when String
              result << raw unless raw.empty?
            end
          end
          result
        end

        private def truthy?(value : TOML::Any) : Bool
          raw = value.raw
          case raw
          when Bool
            raw
          when String
            raw.downcase == "true"
          else
            false
          end
        end

        private def extract_image(data : Hash(String, TOML::Any)) : String?
          # Try images[0] first
          if images = data["images"]?
            raw = images.raw
            if raw.is_a?(Array) && !raw.empty?
              first = raw[0].as(TOML::Any).raw
              return first.to_s if first
            end
          end

          # Fall back to featured_image
          string_value(data, "featured_image")
        end
      end
    end
  end
end
