require "./base"

module Hwaro
  module Services
    module Exporters
      class HugoExporter < Base
        def run(options : Config::Options::ExportOptions) : ExportResult
          content_dir = options.content_dir
          output_dir = options.output_dir
          include_drafts = options.drafts
          verbose = options.verbose

          files = scan_content_files(content_dir)

          if files.empty?
            return ExportResult.new(
              success: false,
              message: "No content files found in: #{content_dir}"
            )
          end

          exported = 0
          skipped = 0
          errors = 0

          files.each do |file_path|
            begin
              result = export_file(file_path, content_dir, output_dir, include_drafts, verbose)
              case result
              when :exported then exported += 1
              when :skipped  then skipped += 1
              end
            rescue ex
              errors += 1
              Logger.warn "Error exporting #{file_path}: #{ex.message}"
            end
          end

          ExportResult.new(
            success: exported > 0 || errors == 0,
            message: "Exported #{exported} items, skipped #{skipped}, errors #{errors}",
            exported_count: exported,
            skipped_count: skipped,
            error_count: errors
          )
        end

        private def export_file(
          file_path : String,
          content_dir : String,
          output_dir : String,
          include_drafts : Bool,
          verbose : Bool,
        ) : Symbol
          raw = File.read(file_path)
          fields, body = parse_content(raw)

          # Skip drafts unless requested
          is_draft = fields["draft"]?.try { |v| v == true }
          if is_draft && !include_drafts
            return :skipped
          end

          # Build Hugo frontmatter (TOML)
          hugo_fields = {} of String => String | Bool | Array(String) | Nil

          # Direct mappings
          %w[title date description draft weight].each do |key|
            hugo_fields[key] = fields[key]? if fields.has_key?(key)
          end

          # updated -> lastmod
          if updated = fields["updated"]?
            hugo_fields["lastmod"] = updated
          end

          # tags
          if tags = fields["tags"]?.as?(Array(String))
            hugo_fields["tags"] = tags
          end

          # series
          if series = fields["series"]?
            hugo_fields["series"] = series
          end

          # aliases
          if aliases = fields["aliases"]?.as?(Array(String))
            hugo_fields["aliases"] = aliases
          end

          # image -> images array in Hugo
          if image = fields["image"]?.as?(String)
            hugo_fields["images"] = [image] of String
          end

          # expires -> expiryDate
          if expires = fields["expires"]?
            hugo_fields["expiryDate"] = expires
          end

          frontmatter = generate_toml_frontmatter(hugo_fields)
          body = rewrite_internal_links(body)

          # Preserve directory structure
          relative = file_path.sub(content_dir, "").lstrip('/')
          out_path = File.join(output_dir, "content", relative)

          write_file(out_path, "#{frontmatter}\n\n#{body.strip}\n", verbose)
          :exported
        end

        private def generate_toml_frontmatter(fields : Hash(String, String | Bool | Array(String) | Nil)) : String
          lines = ["+++"]

          fields.each do |key, value|
            case value
            when Nil    then next
            when Bool   then lines << "#{key} = #{value}"
            when String
              next if value.empty?
              lines << "#{key} = #{value.inspect}"
            when Array(String)
              next if value.empty?
              formatted = value.map(&.inspect).join(", ")
              lines << "#{key} = [#{formatted}]"
            end
          end

          lines << "+++"
          lines.join("\n")
        end
      end
    end
  end
end
