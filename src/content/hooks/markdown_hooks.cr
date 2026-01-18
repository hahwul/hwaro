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
          page.raw_content = data[:content]
          page.draft = data[:draft]
          page.template = data[:layout]
          page.in_sitemap = data[:in_sitemap]
          page.toc = data[:toc]
          page.date = data[:date]
          page.updated = data[:updated]
          page.render = data[:render]
          page.slug = data[:slug]
          page.custom_path = data[:custom_path]
          page.aliases = data[:aliases]
          page.tags = data[:tags]

          if page.is_a?(Models::Section)
            page.transparent = data[:transparent]
            page.generate_feeds = data[:generate_feeds]
          end
        end

        private def filter_drafts(ctx : Core::Lifecycle::BuildContext)
          unless ctx.options.drafts
            ctx.pages.reject! { |p| p.draft }
            ctx.sections.reject! { |s| s.draft }
          end
        end

        private def calculate_urls(ctx : Core::Lifecycle::BuildContext)
          ctx.all_pages.each do |page|
            calculate_page_url(page)
          end
        end

        private def calculate_page_url(page : Models::Page)
          relative_path = page.path
          path_parts = Path[relative_path].parts

          if page.custom_path
            custom = page.custom_path.not_nil!.sub(/^\//, "")
            page.url = "/#{custom}"
            page.url += "/" unless page.url.ends_with?("/")
          elsif page.is_index
            if path_parts.size == 1
              page.url = "/"
            else
              parent = Path[relative_path].dirname
              page.url = "/#{parent}/"
            end
          else
            dir = Path[relative_path].dirname
            stem = Path[relative_path].stem
            leaf = page.slug || stem

            if dir == "."
              page.url = "/#{leaf}/"
            else
              page.url = "/#{dir}/#{leaf}/"
            end
          end
        end

        private def transform_all_pages(ctx : Core::Lifecycle::BuildContext)
          ctx.all_pages.each do |page|
            transform_page(page)
          end
        end

        private def transform_page(page : Models::Page)
          return unless page.render
          return if page.raw_content.empty?

          html_content, toc_headers = Processor::Markdown.render(page.raw_content)
          page.content = html_content
          # Store TOC in metadata if needed
        end
      end
    end
  end
end
