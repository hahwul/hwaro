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
            result = export_file(file_path, content_dir, output_dir, include_drafts, verbose)
            case result
            when :exported then exported += 1
            when :skipped  then skipped += 1
            end
          rescue ex
            errors += 1
            Logger.warn "Error exporting #{file_path}: #{ex.message}"
          end

          # Any per-file error fails the run: `exported > 0` used to mask
          # errors, so a partial export reported success and exited 0.
          ExportResult.new(
            success: errors == 0,
            message: errors > 0 ? "#{errors} file(s) could not be exported (#{exported} exported, #{skipped} skipped)" : "Exported #{exported} items, skipped #{skipped}, errors #{errors}",
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
          raw = read_content(file_path)
          fields, body = parse_content(raw)

          # Skip drafts unless requested
          is_draft = fields["draft"]?.try(&.raw) == true
          if is_draft && !include_drafts
            return :skipped
          end

          # Build Hugo frontmatter (TOML).
          #
          # Strategy: walk every parsed frontmatter key and either rename
          # it to its Hugo equivalent (`updated`→`lastmod`, `image`→`images`,
          # `expires`→`expiryDate`) or pass it through unchanged — including
          # nested tables (`[extra]`) and typed scalars. Hugo
          # accepts arbitrary keys as page params, so dropping them was a
          # silent data-loss bug for `categories`, `authors`, and any
          # custom field the user added (gh#527). A `[taxonomies]` table is
          # flattened first: Hugo reads `tags`/`categories` at the TOP level
          # and treats the nested table as an inert param, so passing it
          # through cost the post every taxonomy it belonged to.
          # Source-iteration order is preserved so Hugo frontmatter reads
          # similarly to the original.
          # A rename only applies when its TARGET key is not authored in the
          # source — an authored target wins regardless of key order, the
          # same existing-key-wins rule `flatten_taxonomies` uses. When the
          # rename is blocked, the source key is passed through under its own
          # name instead of being dropped: Hugo accepts arbitrary page
          # params, and silent data loss is this exporter's cardinal sin
          # (gh#527). Renaming unconditionally clobbered a coexisting
          # authored key whenever the source key happened to iterate second.
          hugo_fields = {} of String => YAML::Any
          flattened = flatten_taxonomies(fields)
          flattened.each do |key, value|
            next if value.raw.nil?
            case key
            when "updated"
              if authored?(flattened, "lastmod")
                hugo_fields[key] = value
              else
                hugo_fields["lastmod"] = value
              end
            when "expires"
              if authored?(flattened, "expiryDate")
                hugo_fields[key] = value
              else
                hugo_fields["expiryDate"] = value
              end
            when "image"
              if authored?(flattened, "images")
                hugo_fields[key] = value
              elsif image = value.as_s?
                hugo_fields["images"] = YAML::Any.new([YAML::Any.new(image)])
              else
                hugo_fields["images"] = value
              end
            else
              hugo_fields[key] = value
            end
          end

          frontmatter = generate_toml_frontmatter(hugo_fields)
          body = rewrite_internal_links(body)

          # Preserve directory structure
          relative = file_path.sub(content_dir, "").lstrip('/')
          out_path = File.join(output_dir, "content", relative)

          # A refused destination (outside `output_dir`) is reported as
          # skipped, and its bundle assets are not copied either — there is no
          # exported post for them to sit next to.
          return :skipped unless write_file(out_path, "#{frontmatter}\n\n#{body.strip}\n", output_dir, verbose)

          # Leaf bundle (`posts/my-post/index.md`): Hugo reads the bundle's
          # co-located resources out of this same directory, so carry them
          # across instead of exporting a post whose images all 404.
          if File.basename(relative).in?("index.md", "index.markdown") && relative.includes?('/')
            begin
              copy_bundle_assets(File.dirname(file_path), File.dirname(out_path), output_dir, verbose)
            rescue ex : File::Error
              # The bundle directory vanished or became unlistable after the
              # post was written — the post itself exported, so warn instead
              # of letting the counts/manifest disagree with disk.
              Logger.warn "Could not export bundle assets for #{file_path}: #{ex.message}"
            end
          end

          :exported
        end

        # An authored, non-null value for `key` exists in the source fields.
        private def authored?(fields : Hash(String, YAML::Any), key : String) : Bool
          value = fields[key]?
          !value.nil? && !value.raw.nil?
        end

        private def generate_toml_frontmatter(fields : Hash(String, YAML::Any)) : String
          body = Hwaro::Utils::FrontmatterWriter::TomlBuilder.new.build(fields)
          "+++\n#{body}+++"
        end
      end
    end
  end
end
