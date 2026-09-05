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
          force = options.force

          reset_written_paths

          content_dir = File.join(hugo_path, "content")

          unless Dir.exists?(content_dir)
            return ImportResult.new(
              success: false,
              message: "Hugo content directory not found: #{content_dir}"
            )
          end

          import_each(scan_markdown_files(content_dir), "Hugo", wrapped_note: "contained Hugo shortcodes. Imports kept the raw syntax — each will render as literal text until you hand-convert them.") do |file_path|
            process_file(file_path, content_dir, output_dir, include_drafts, verbose, force)
          end
        end

        protected def import_error_message(item : String, ex : Exception) : String
          "Error processing #{item}: #{ex.message}"
        end

        protected def summary_message(engine : String, imported : Int32, skipped : Int32, errors : Int32) : String
          "Imported #{imported} items, skipped #{skipped}, errors #{errors}"
        end

        private def scan_markdown_files(content_dir : String) : Array(String)
          walk_files(content_dir)
        end

        private def process_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
          force : Bool,
        ) : Symbol
          raw = read_text(file_path)
          fm_data, body = extract_frontmatter(raw)

          # Check draft status (only if frontmatter exists)
          is_draft = fm_data.try { |d| d["draft"]?.try { |v| truthy?(v) } } || false
          if is_draft && !include_drafts
            return :skipped
          end

          # Track files with Hugo shortcodes so the `run` method can
          # emit a single summary telling the user how many files need
          # manual conversion.
          has_shortcodes = body.includes?("{{<") || body.includes?("{{%")
          if has_shortcodes
            Logger.warn "Hugo shortcodes detected in #{file_path} — manual conversion needed."
          end

          # Map Hugo fields to Hwaro frontmatter
          fields = {} of String => FieldValue
          slug_val : String? = nil

          if data = fm_data
            # title
            if title = string_value(data, "title")
              fields["title"] = title
            end

            # date (falling back to Hugo's publishDate so a page dated only
            # via publishDate doesn't lose its date entirely)
            if date_str = string_value(data, "date") || string_value(data, "publishDate")
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
            fields["tags"] = tags unless tags.empty?

            # categories — preserve as its own taxonomy key; hwaro's
            # scaffold `[[taxonomies]]` defines tags and categories as
            # separate classifications.
            categories = array_string_value(data, "categories")
            fields["categories"] = categories unless categories.empty?

            # authors — Hugo's `authors` list maps 1:1 onto hwaro's own
            # `authors` front matter (the blog scaffold writes it, and the
            # WordPress/Astro importers already populate it). Dropping it
            # lost author attribution on every Hugo import and made
            # `hwaro → hugo export → hugo import` non-round-tripping.
            authors = array_string_value(data, "authors")
            fields["authors"] = authors unless authors.empty?

            # series
            if series = string_value(data, "series")
              fields["series"] = series
            elsif series_arr = array_string_value(data, "series")
              fields["series"] = series_arr.first? unless series_arr.empty?
            end

            # weight — must stay numeric: hwaro's frontmatter reader takes
            # `as_i?`, so a quoted `weight = "3"` silently reads as weight 0
            # and every imported page loses its ordering.
            if weight_val = data["weight"]?
              case weight_raw = weight_val.raw
              when Int64 then fields["weight"] = weight_raw
              when Float64
                # Guard the conversion: 1e300 / Infinity / NaN would raise
                # OverflowError out of `to_i64` and error the whole file.
                # An absurd weight is ignored instead.
                if weight_raw.finite? && weight_raw.in?(-9.0e18..9.0e18)
                  fields["weight"] = weight_raw.to_i64
                end
              when String then fields["weight"] = weight_raw.to_i64?
              end
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

          # Determine section and filename
          section, filename = section_from_path(file_path, content_dir, "")

          # Determine slug for the file
          if filename == "_index.md" || filename == "_index.markdown"
            file_slug = "_index"
          elsif slug_val && !slug_val.empty?
            file_slug = slug_val
          else
            file_slug = filename.sub(/\.(md|markdown)$/, "")
          end

          body = strip_redundant_title_h1(body, fields["title"]?.as?(String))
          written, dest_path = write_content_file_to(output_dir, section, file_slug, frontmatter, body.strip, verbose, force)

          # Leaf bundle (`posts/my-post/index.md`): the co-located images
          # belong beside the written `.md`, and were never copied at all —
          # leaving every `![](cover.png)` in the imported post 404ing.
          #
          # The destination comes from the path `write_content_file_to`
          # actually chose, not from `output_dir/section`: a front-matter
          # `slug` or a claim collision moves the `.md` elsewhere, and the
          # assets have to follow it. Assets are also copied when the `.md`
          # was SKIPPED — on a re-import the post already exists, and
          # requiring `--force` (which rewrites content) just to recover
          # missing images was a trap.
          #
          # `section` must be non-empty: a bare `content/index.md` is the site
          # root, not a bundle, and sweeping the whole content root's loose
          # files into the output is not what the author asked for.
          if dest_path && !section.empty? && (filename == "index.md" || filename == "index.markdown")
            copy_bundle_assets(File.dirname(file_path), File.dirname(dest_path), output_dir, verbose, force)
          end

          return :skipped unless written
          has_shortcodes ? :imported_wrapped : :imported
        end

        # Regex for TOML frontmatter: +++ on first line, +++ on its own line.
        # (YAML frontmatter reuses the inherited Base::YAML_FM_REGEX.)
        TOML_FM_REGEX = /\A\+\+\+[ \t]*\n(.*?\n?)^\+\+\+[ \t]*$\n?(.*)\z/m

        private def extract_frontmatter(raw : String) : {Hash(String, TOML::Any)?, String} | {Hash(String, YAML::Any)?, String}
          if raw.starts_with?("+++")
            if match = TOML_FM_REGEX.match(raw)
              toml_str = match[1].strip
              body = match[2].lstrip('\n')
              begin
                data = TOML.parse(toml_str)
                return {data, body}
              rescue TOML::ParseException
                return {nil, raw}
              end
            end
          elsif raw.starts_with?("---")
            if match = YAML_FM_REGEX.match(raw)
              yaml_str = match[1].strip
              body = match[2].lstrip('\n')
              begin
                yaml_data = YAML.parse(yaml_str)
                if h = yaml_data.as_h?
                  data = {} of String => TOML::Any
                  h.each do |k, v|
                    key_str = yaml_string(k)
                    data[key_str] = yaml_any_to_toml_any(v)
                  end
                  return {data, body}
                elsif yaml_data.raw.nil?
                  # Empty/comment-only frontmatter: no fields, but drop the
                  # fences — returning `raw` leaked literal `---` lines into
                  # the imported page body.
                  return {nil, body}
                end
                # Non-mapping block (a leading horizontal rule): treat the
                # whole document as body.
              rescue ex : YAML::ParseException
                Logger.debug "YAML front matter parse failed: #{ex.message}"
                return {nil, raw}
              end
            end
          end

          {nil, raw}
        end

        # `depth` guards a cyclic YAML::Any (self-referencing anchor); see
        # `Utils::Nesting`.
        private def yaml_any_to_toml_any(value : YAML::Any, depth : Int32 = 0) : TOML::Any
          Utils::Nesting.check!(depth)
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
            arr = raw.map { |item| yaml_any_to_toml_any(item.as(YAML::Any), depth + 1) }
            TOML::Any.new(arr)
          when Hash
            hash = {} of String => TOML::Any
            raw.each do |k, v|
              k_any = k.as(YAML::Any)
              key_str = yaml_string(k_any)
              hash[key_str] = yaml_any_to_toml_any(v.as(YAML::Any), depth + 1)
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
