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

          # New fields — keep in sync with Builder#parse_single_page
          page.authors = data[:authors]
          page.extra = data[:extra]
          page.in_search_index = data[:in_search_index]
          page.insert_anchor_links = data[:insert_anchor_links]
          page.weight = data[:weight]

          # Expiry support
          page.expires = data[:expires]

          # Series support
          page.series = data[:series]
          page.series_weight = data[:series_weight]

          if page.is_a?(Models::Section)
            page.transparent = data[:transparent]
            page.generate_feeds = data[:generate_feeds]
            page.paginate = data[:paginate]
            page.pagination_enabled = data[:pagination_enabled]
            page.sort_by = data[:sort_by]
            page.reverse = data[:reverse]
            page.page_template = data[:page_template]
            page.paginate_path = data[:paginate_path]
          end

          # Calculate derived fields
          page.calculate_word_count
          page.calculate_reading_time
          page.extract_summary
        end

        private def filter_drafts(ctx : Core::Lifecycle::BuildContext)
          include_drafts = ctx.options.drafts
          filter_expired = !ctx.options.include_expired
          filter_future = !ctx.options.include_future
          now = Time.utc

          filter = ->(p : Models::Page) do
            (!include_drafts && p.draft) ||
            (filter_expired && (p.expires.try { |e| e <= now } || false)) ||
            (filter_future && (p.date.try { |d| d > now } || false))
          end

          before = ctx.pages.size + ctx.sections.size
          ctx.pages.reject!(&filter)
          ctx.sections.reject!(&filter)
          after = ctx.pages.size + ctx.sections.size
          ctx.invalidate_all_pages_cache if before != after
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

          if custom_path = page.custom_path
            custom = custom_path.lchop("/")
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
            clean_stem = if lang = page.language
                           stem.sub(/\.#{Regex.escape(lang)}$/, "")
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
          emoji = ctx.config.try(&.markdown.emoji) || false
          md_config = ctx.config.try(&.markdown)

          ctx.all_pages.each do |page|
            transform_page(page, safe, emoji, md_config)
          end
        end

        private def transform_page(page : Models::Page, safe : Bool = false, emoji : Bool = false, markdown_config : Models::MarkdownConfig? = nil)
          return unless page.render
          return if page.raw_content.empty?

          html_content, toc_headers = Processor::Markdown.render(page.raw_content, highlight: true, safe: safe, emoji: emoji, markdown_config: markdown_config)
          page.content = html_content
          # Store TOC in metadata if needed
        end
      end
    end
  end
end
