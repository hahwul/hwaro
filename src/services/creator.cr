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

        # --section overrides the base directory
        if section = options.section
          if path && path.ends_with?(".md")
            filename = File.basename(path)
            full_path = File.join("content", section, filename)
          elsif path
            full_path = File.join("content", section, path)
            full_path += ".md" unless full_path.ends_with?(".md")
          else
            # No path given; title must be supplied via --title.
            full_path = nil
          end

          if full_path
            base_dir = File.dirname(full_path)
            if title.empty?
              filename_without_ext = File.basename(full_path, ".md")
              title = filename_without_ext.split("-").map(&.capitalize).join(" ")
            end
          else
            base_dir = File.join("content", section)
          end
        else
          # Determine if path is a file path or directory
          is_file_path = path && path.ends_with?(".md")

          if is_file_path && path
            # Extract directory and filename from path
            base_dir = File.dirname(path)
            base_dir = "content/drafts" if base_dir == "."

            # Extract title from filename if not provided
            if title.empty?
              filename_without_ext = File.basename(path, ".md")
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
            full_path = nil
          end
        end

        # Require `--title` (or an explicit `<path>.md`) whenever the title
        # cannot be inferred. The `new` command is flag-only: no interactive
        # prompts, so behavior is predictable in TTY, CI, and agent runs.
        if !full_path && title.empty?
          raise "missing --title (or <path>.md) argument\nUsage: hwaro new <path> [options]\nRun 'hwaro new --help' for details."
        end

        if !full_path
          if title.empty?
            raise "Title cannot be empty."
          end
          filename = title.downcase.gsub(/[^\p{L}\p{N}]+/, "-").strip("-") + ".md"
          full_path = File.join(base_dir, filename)
        end

        FileUtils.mkdir_p(base_dir) unless Dir.exists?(base_dir)

        # Draft: CLI flag > path-based detection
        is_draft = if options.draft.nil?
                     base_dir.includes?("drafts")
                   else
                     options.draft == true
                   end

        date = options.date || Time.local.to_s("%Y-%m-%d %H:%M:%S")
        tags = options.tags

        # Find archetype
        archetype_content = find_archetype(options.archetype, full_path)

        content = if archetype_content
                    process_archetype(archetype_content, title, date, is_draft, tags)
                  else
                    generate_default_content(title, date, is_draft, tags)
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
        relative_path = path.lchop("content/")
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

      private def process_archetype(archetype_content : String, title : String, date : String, is_draft : Bool, tags : Array(String)) : String
        tags_str = tags.empty? ? "[]" : "[#{tags.map { |t| "\"#{t.gsub("\"", "\\\"")}\"" }.join(", ")}]"
        content = archetype_content
          .gsub("{{ title }}", title)
          .gsub("{{title}}", title)
          .gsub("{{ date }}", date)
          .gsub("{{date}}", date)
          .gsub("{{ draft }}", is_draft.to_s)
          .gsub("{{draft}}", is_draft.to_s)
          .gsub("{{ tags }}", tags_str)
          .gsub("{{tags}}", tags_str)

        content
      end

      private def generate_default_content(title : String, date : String, is_draft : Bool, tags : Array(String)) : String
        safe_title = title.gsub("\"", "\\\"").gsub("\n", " ")
        String.build do |str|
          str << "---\n"
          str << "title: \"#{safe_title}\"\n"
          str << "date: #{date}\n"
          str << "draft: true\n" if is_draft
          unless tags.empty?
            str << "tags:\n"
            tags.each { |tag| str << "  - \"#{tag.gsub("\"", "\\\"")}\"\n" }
          end
          str << "---\n\n"
          str << "# #{title}\n"
        end
      end
    end
  end
end
