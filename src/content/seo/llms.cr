require "../../models/config"
require "../../models/page"
require "../../models/section"
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
          Logger.info "  Generated #{filename}" if verbose

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

          eligible = pages.select(&.search_index_eligible?)

          # Group by section, keyed by display heading. A section's heading
          # comes from its `_index.md`, which is the only page modeled as a
          # `Models::Section`. Key off the *type*, NOT `is_index`: a
          # page-bundle leaf (`foo/bar/index.md`) is also `is_index == true`,
          # so testing `is_index` here let an arbitrary leaf's title clobber
          # the section heading.
          headings = {} of String => String
          eligible.each do |p|
            next unless p.is_a?(Models::Section)
            next if p.section.empty?
            headings[p.section] = p.title unless p.title.empty? || p.title == "Untitled"
          end

          # Fold section-level `_index.md` pages (a `Models::Section` with a
          # non-empty section) into their heading, so they don't get their own
          # listing. Everything else stays listed — in particular page-bundle
          # leaves (`foo/index.md`), which are `Models::Page` with
          # `is_index == true`: they are real content pages. Filtering on
          # `is_index` here dropped every page-bundle leaf and left only the
          # home page(s). The root `_index.md` (a `Models::Section` with an
          # empty section) is the home page and has nowhere else to live, so
          # the `!section.empty?` guard keeps it under "Pages".
          by_section = eligible
            .reject { |p| p.is_a?(Models::Section) && !p.section.empty? }
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
                # The root index commonly has `title = ""` so its heading
                # falls through to the site title; without this fallback
                # the homepage rendered as `- [](url)` (no link label).
                raw_label = p.title.empty? ? config.title : p.title
                # Escape link-label metacharacters so a title with a stray
                # `[`/`]` doesn't break the `- [label](url)` Markdown link.
                # (escape backslash first, then the brackets)
                label = raw_label.gsub('\\', "\\\\").gsub('[', "\\[").gsub(']', "\\]")
                str << "- [" << label << "](" << link << ")"
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
          Logger.info "  Generated #{filename}" if verbose
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
