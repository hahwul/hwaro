require "../../models/config"
require "../../models/page"
require "../../utils/logger"

module Hwaro
  module Content
    module Seo
      class Llms
        def self.generate(config : Models::Config, output_dir : String, verbose : Bool = false)
          return unless config.llms.enabled

          content = config.llms.instructions
          # Add a newline at the end if not present and content is not empty
          content += "\n" if !content.empty? && !content.ends_with?("\n")

          filename = config.llms.filename
          file_path = File.join(output_dir, filename)
          File.write(file_path, content)
          Logger.action :create, file_path if verbose
          Logger.info "  Generated #{filename}"
        end

        def self.generate(config : Models::Config, pages : Array(Models::Page), output_dir : String, verbose : Bool = false)
          generate(config, output_dir, verbose)
          generate_full(pages, config, output_dir, verbose)
        end

        def self.generate_full(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false)
          return unless config.llms.enabled
          return unless config.llms.full_enabled

          filename = config.llms.full_filename
          filename = "llms-full.txt" if filename.empty?

          file_path = File.join(output_dir, filename)
          content = build_full_document(pages, config)
          content += "\n" unless content.ends_with?("\n")

          File.write(file_path, content)
          Logger.action :create, file_path if verbose
          Logger.info "  Generated #{filename}"
        end

        private def self.build_full_document(pages : Array(Models::Page), config : Models::Config) : String
          eligible_pages = pages.select { |page| page.render && !page.raw_content.empty? }.sort_by(&.url)

          base_url = config.base_url
          base_url = base_url.rstrip('/') unless base_url.empty?

          String.build do |str|
            str << "# " << config.title << "\n"
            str << config.description << "\n" unless config.description.empty?
            str << "\n" unless config.description.empty?

            str << "Base URL: " << config.base_url << "\n" unless config.base_url.empty?

            instructions = config.llms.instructions
            unless instructions.empty?
              str << "\n"
              str << instructions
              str << "\n" unless instructions.ends_with?("\n")
            end

            eligible_pages.each do |page|
              str << "\n---\n\n"
              str << "Title: " << page.title << "\n"

              url = page.url
              absolute_url = base_url.empty? ? url : "#{base_url}#{url}"
              str << "URL: " << absolute_url << "\n"
              str << "Source: content/" << page.path << "\n"

              if config.multilingual?
                lang = page.language || config.default_language
                str << "Language: " << lang << "\n"
              end

              str << "\n"
              str << page.raw_content
              str << "\n" unless page.raw_content.ends_with?("\n")
            end
          end
        end
      end
    end
  end
end
