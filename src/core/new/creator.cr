require "file_utils"
require "time"
require "../../options/new_options"
require "../../utils/logger"

module Hwaro
  module Core
    module New
      class Creator
        def run(options : Options::NewOptions)
          base_path = options.path || "content/drafts"

          title = options.title || ""

          if title.empty?
            print "Enter title: "
            title = gets.try(&.chomp) || ""
          end

          if title.empty?
            Logger.error "Title cannot be empty."
            exit(1)
          end

          filename = title.downcase.gsub(/[^\p{L}\p{N}]+/, "-").strip("-") + ".md"
          full_path = File.join(base_path, filename)

          dir_path = File.dirname(full_path)
          FileUtils.mkdir_p(dir_path) unless Dir.exists?(dir_path)

          is_draft = base_path.starts_with?("content/drafts")
          date = Time.local.to_s("%Y-%m-%d %H:%M:%S")

          content = String.build do |str|
            str << "---\n"
            str << "title: #{title}\n"
            str << "date: #{date}\n"
            str << "draft: true\n" if is_draft
            str << "---\n\n"
            str << "# #{title}\n"
          end

          if File.exists?(full_path)
            Logger.error "File already exists: #{full_path}"
            exit(1)
          end

          File.write(full_path, content)
          Logger.info "Created new content: #{full_path}"
        end
      end
    end
  end
end
