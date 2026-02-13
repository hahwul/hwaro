require "file_utils"
require "time"
require "../config/options/new_options"
require "../utils/logger"

module Hwaro
  module Services
    class Creator
      ARCHETYPES_DIR = "archetypes"

      def run(options : Config::Options::NewOptions)
        path = options.path
        title = options.title || ""

        # Determine if path is a file path or directory
        is_file_path = path && path.ends_with?(".md")

        if is_file_path && path
          # Extract directory and filename from path
          base_dir = File.dirname(path)
          base_dir = "content/drafts" if base_dir == "."

          # Extract title from filename if not provided
          if title.empty?
            filename_without_ext = File.basename(path, ".md")
            # Convert slug to title (capitalize words, replace dashes with spaces)
            title = filename_without_ext.split("-").map(&.capitalize).join(" ")
          end

          filename = File.basename(path)
          if base_dir == "content/drafts"
            full_path = File.join(base_dir, filename)
          else
            full_path = path.starts_with?("content/") ? path : File.join("content", path)
          end
          base_dir = File.dirname(full_path)
        else
          base_dir = path || "content/drafts"
          base_dir = "content/#{base_dir}" unless base_dir.starts_with?("content/")

          if title.empty?
            print "Enter title: "
            title = gets.try(&.chomp) || ""
          end

          if title.empty?
            raise "Title cannot be empty."
          end

          filename = title.downcase.gsub(/[^\p{L}\p{N}]+/, "-").strip("-") + ".md"
          full_path = File.join(base_dir, filename)
        end

        FileUtils.mkdir_p(base_dir) unless Dir.exists?(base_dir)

        is_draft = base_dir.includes?("drafts")
        date = Time.local.to_s("%Y-%m-%d %H:%M:%S")

        # Find archetype
        archetype_content = find_archetype(options.archetype, full_path)

        content = if archetype_content
                    process_archetype(archetype_content, title, date, is_draft)
                  else
                    generate_default_content(title, date, is_draft)
                  end

        if File.exists?(full_path)
          raise "File already exists: #{full_path}"
        end

        File.write(full_path, content)
        Logger.info "Created new content: #{full_path}"
      end

      private def find_archetype(explicit_archetype : String?, path : String) : String?
        # 1. If explicit archetype is given, use it
        if explicit_archetype
          archetype_path = File.join(ARCHETYPES_DIR, "#{explicit_archetype}.md")
          if File.exists?(archetype_path)
            Logger.debug "Using archetype: #{archetype_path}"
            return File.read(archetype_path)
          else
            raise "Archetype not found: #{archetype_path}"
          end
        end

        # 2. Try to find archetype based on path
        # Extract relative path from content/ directory
        relative_path = path.sub(/^content\//, "")
        dir_path = File.dirname(relative_path)

        if dir_path != "."
          # Try progressively shorter paths
          # e.g., tools/develop/mytool.md -> try tools/develop.md, then tools.md
          parts = dir_path.split("/")

          # Try from most specific to least specific
          parts.size.downto(1) do |i|
            archetype_name = parts[0...i].join("/")
            archetype_path = File.join(ARCHETYPES_DIR, "#{archetype_name}.md")

            if File.exists?(archetype_path)
              Logger.debug "Using archetype: #{archetype_path}"
              return File.read(archetype_path)
            end
          end
        end

        # 3. Try default archetype
        default_archetype = File.join(ARCHETYPES_DIR, "default.md")
        if File.exists?(default_archetype)
          Logger.debug "Using default archetype: #{default_archetype}"
          return File.read(default_archetype)
        end

        # 4. No archetype found
        nil
      end

      private def process_archetype(archetype_content : String, title : String, date : String, is_draft : Bool) : String
        # Replace placeholders in archetype
        content = archetype_content
          .gsub("{{ title }}", title)
          .gsub("{{title}}", title)
          .gsub("{{ date }}", date)
          .gsub("{{date}}", date)
          .gsub("{{ draft }}", is_draft.to_s)
          .gsub("{{draft}}", is_draft.to_s)

        content
      end

      private def generate_default_content(title : String, date : String, is_draft : Bool) : String
        String.build do |str|
          str << "---\n"
          str << "title: #{title}\n"
          str << "date: #{date}\n"
          str << "draft: true\n" if is_draft
          str << "---\n\n"
          str << "# #{title}\n"
        end
      end
    end
  end
end
