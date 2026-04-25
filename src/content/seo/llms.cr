require "../../models/config"
require "../../models/page"
require "../../utils/logger"

module Hwaro
  module Content
    module Seo
      class Llms
        # Backward-compatible entry point for callers that don't have a
        # page list handy. The current build pipeline always uses the
        # 4-arg form below; this stub keeps any external caller working
        # by emitting the title/description/instructions header without
        # the page index.
        def self.generate(config : Models::Config, output_dir : String, verbose : Bool = false)
          generate(config, [] of Models::Page, output_dir, verbose)
        end

        def self.generate(config : Models::Config, pages : Array(Models::Page), output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
          return unless config.llms.enabled

          if skip_if_unchanged
            filename = File.basename(config.llms.filename.empty? ? "llms.txt" : config.llms.filename)
            if File.exists?(File.join(output_dir, filename))
              Logger.debug "  LLMs.txt unchanged (cache hit), skipping."
              return
            end
          end

          filename = File.basename(config.llms.filename.empty? ? "llms.txt" : config.llms.filename)
          file_path = File.join(output_dir, filename)
          File.write(file_path, build_index(config, pages))
          Logger.action :create, file_path if verbose
          Logger.info "  Generated #{filename}"

          generate_full(pages, config, output_dir, verbose)
        end

        # Build the llms.txt body per the proposed [llms.txt][1] format:
        #
        #     # Site Title
        #
        #     > Optional site description (blockquote)
        #
        #     Optional preamble (free-form, e.g. crawler instructions).
        #
        #     ## Section Name
        #
        #     - [Page Title](https://site/url): optional description
        #
        # Pages are grouped by `page.section`; standalone (root) pages
        # land under `## Pages`. Drafts, hidden pages, and `render=false`
        # pages are excluded — same filter the search index uses.
        #
        # [1]: https://llmstxt.org/
        private def self.build_index(config : Models::Config, pages : Array(Models::Page)) : String
          base_url = config.base_url.rstrip('/')

          eligible = pages.select { |p| p.render && !p.draft && p.in_search_index && !p.generated }

          # Group by section, keyed by display heading. Section index
          # pages double as the section's heading source — find the
          # corresponding `_index.md` (`is_index && section.match`) and
          # use its title; fall back to the section directory's basename.
          headings = {} of String => String
          eligible.each do |p|
            next unless p.is_index
            next if p.section.empty?
            headings[p.section] = p.title unless p.title.empty? || p.title == "Untitled"
          end

          # Section-level `_index.md` pages are folded into the section
          # heading, so they don't need their own listing. Root-level
          # `index.md` (the home page) has nowhere else to live, so it
          # stays in the listing under "Pages".
          by_section = eligible
            .reject { |p| p.is_index && !p.section.empty? }
            .group_by(&.section)

          String.build do |str|
            str << "# " << (config.title.empty? ? "Site" : config.title) << "\n\n"

            desc = config.description.strip
            unless desc.empty?
              str << "> " << desc << "\n\n"
            end

            instructions = config.llms.instructions.strip
            unless instructions.empty?
              str << instructions << "\n\n"
            end

            # Stable, deterministic order: empty section ("Pages") first,
            # then the rest alphabetically. Mirrors how `site.sections`
            # surfaces in templates.
            section_keys = by_section.keys.sort_by! { |k| k.empty? ? "" : "1#{k}" }
            section_keys.each do |section_name|
              heading = if section_name.empty?
                          "Pages"
                        else
                          headings[section_name]? || section_name.split("/").last.capitalize
                        end
              str << "## " << heading << "\n\n"

              by_section[section_name].sort_by(&.url).each do |p|
                link = if base_url.empty?
                         p.url
                       else
                         "#{base_url}#{p.url}"
                       end
                str << "- [" << p.title << "](" << link << ")"
                if d = p.description
                  str << ": " << d unless d.empty?
                end
                str << "\n"
              end
              str << "\n"
            end
          end
        end

        def self.generate_full(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false)
          return unless config.llms.enabled
          return unless config.llms.full_enabled

          filename = config.llms.full_filename
          filename = "llms-full.txt" if filename.empty?
          filename = File.basename(filename)

          file_path = File.join(output_dir, filename)
          content = build_full_document(pages, config)
          content += "\n" unless content.ends_with?("\n")

          File.write(file_path, content)
          Logger.action :create, file_path if verbose
          Logger.info "  Generated #{filename}"
        end

        private def self.build_full_document(pages : Array(Models::Page), config : Models::Config) : String
          eligible_pages = pages.select { |page| page.render && !page.draft && !page.raw_content.empty? }.sort_by!(&.url)

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
