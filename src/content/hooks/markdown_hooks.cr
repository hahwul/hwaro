# Markdown processor hooks for build lifecycle
#
# Integrates the Markdown processor with the lifecycle system.
# Handles parsing front matter and transforming Markdown to HTML.

require "../../core/lifecycle"
require "../processors/markdown"

module Hwaro
  module Content
    module Hooks
      class MarkdownHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # After ReadContent: Parse front matter from markdown files
          manager.after(Core::Lifecycle::Phase::ReadContent, priority: 100, name: "markdown:parse") do |ctx|
            parse_all_pages(ctx)
            filter_drafts(ctx)
            calculate_urls(ctx)
            Core::Lifecycle::HookResult::Continue
          end

          # Before Render: Transform Markdown to HTML
          manager.before(Core::Lifecycle::Phase::Render, priority: 100, name: "markdown:transform") do |ctx|
            transform_all_pages(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def parse_all_pages(ctx : Core::Lifecycle::BuildContext)
          ctx.pages.each do |page|
            parse_page(page)
          end
          ctx.sections.each do |section|
            parse_page(section)
          end
        end

        private def parse_page(page : Models::Page)
          return unless page.path.ends_with?(".md")

          source_path = File.join("content", page.path)
          return unless File.exists?(source_path)

          raw_content = File.read(source_path)
          data = Processor::Markdown.parse(raw_content, source_path)

          page.title = data[:title]
          page.description = data[:description]
          page.image = data[:image]
          page.raw_content = data[:content]
          page.draft = data[:draft]
          page.template = data[:template]
          page.in_sitemap = data[:in_sitemap]
          page.toc = data[:toc]
          page.date = data[:date]
          page.updated = data[:updated]
          page.render = data[:render]
          page.slug = data[:slug]
          page.custom_path = data[:custom_path]
          page.aliases = data[:aliases]
          page.tags = data[:tags]
          page.taxonomies = data[:taxonomies]
          page.front_matter_keys = data[:front_matter_keys]
          page.taxonomy_name = nil
          page.taxonomy_term = nil
          page.redirect_to = data[:redirect_to]

          if page.is_a?(Models::Section)
            page.transparent = data[:transparent]
            page.generate_feeds = data[:generate_feeds]
            page.paginate = data[:paginate]
            page.pagination_enabled = data[:pagination_enabled]
            page.sort_by = data[:sort_by]
            page.reverse = data[:reverse]
          end
        end

        private def filter_drafts(ctx : Core::Lifecycle::BuildContext)
          unless ctx.options.drafts
            ctx.pages.reject! { |p| p.draft }
            ctx.sections.reject! { |s| s.draft }
          end
        end

        private def calculate_urls(ctx : Core::Lifecycle::BuildContext)
          config = ctx.config
          return unless config

          ctx.all_pages.each do |page|
            calculate_page_url(page, config)
          end
        end

        private def calculate_page_url(page : Models::Page, config : Models::Config)
          relative_path = page.path

          # Apply permalinks mapping
          directory_path = Path[relative_path].dirname.to_s
          effective_dir = directory_path

          config.permalinks.each do |source, target|
            if directory_path == source
              effective_dir = target
              break
            elsif directory_path.starts_with?("#{source}/")
              effective_dir = directory_path.sub(/^#{Regex.escape(source)}\//, "#{target}/")
              break
            end
          end

          # For multilingual sites, include language prefix for non-default languages
          lang_prefix = if page.language && page.language != config.default_language
                          "/#{page.language}"
                        else
                          ""
                        end

          if page.custom_path
            custom = page.custom_path.not_nil!.sub(/^\//, "")
            page.url = "#{lang_prefix}/#{custom}"
            page.url += "/" unless page.url.ends_with?("/")
          elsif page.is_index
            if effective_dir == "." || effective_dir.empty?
              page.url = lang_prefix.empty? ? "/" : "#{lang_prefix}/"
            else
              page.url = "#{lang_prefix}/#{effective_dir}/"
            end
          else
            stem = Path[relative_path].stem

            # Remove language suffix from stem (e.g., "hello-world.ko" -> "hello-world")
            clean_stem = if page.language
                           stem.sub(/\.#{page.language}$/, "")
                         else
                           stem
                         end

            leaf = page.slug || clean_stem

            if effective_dir == "." || effective_dir.empty?
              page.url = "#{lang_prefix}/#{leaf}/"
            else
              page.url = "#{lang_prefix}/#{effective_dir}/#{leaf}/"
            end
          end
        end

        private def transform_all_pages(ctx : Core::Lifecycle::BuildContext)
          # Get markdown config options
          safe = ctx.config.try(&.markdown.safe) || false

          ctx.all_pages.each do |page|
            transform_page(page, safe)
          end
        end

        private def transform_page(page : Models::Page, safe : Bool = false)
          return unless page.render
          return if page.raw_content.empty?

          html_content, toc_headers = Processor::Markdown.render(page.raw_content, highlight: true, safe: safe)
          page.content = html_content
          # Store TOC in metadata if needed
        end
      end
    end
  end
end
