require "file_utils"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../utils/logger"
require "../../utils/text_utils"
require "../../utils/sort_utils"
require "../processors/markdown"

module Hwaro
  module Content
    module Seo
      class Feeds
        def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
          if skip_if_unchanged && config.feeds.enabled
            feed_file = config.feeds.filename.empty? ? (config.feeds.type == "atom" ? "atom.xml" : "rss.xml") : config.feeds.filename
            if File.exists?(File.join(output_dir, feed_file))
              Logger.debug "  Feeds unchanged (cache hit), skipping."
              return
            end
          end

          # 1. Generate Main Site Feed
          if config.feeds.enabled
            site_pages = pages.reject { |p| p.draft || !p.render || p.is_a?(Models::Section) }

            # Deduplicate by URL (keep last occurrence, matching build behavior)
            seen_urls = Set(String).new
            site_pages = site_pages.reverse.select { |p| seen_urls.add?(p.url) }.reverse!

            # Filter by section if configured for main feed
            if !config.feeds.sections.empty?
              site_pages = site_pages.select { |p|
                config.feeds.sections.any? { |s| p.section == s || p.section.starts_with?("#{s}/") }
              }
            end

            # When multilingual and default_language_only is true,
            # the main feed only contains default language pages.
            # When false, the main feed includes all languages (original behavior).
            if config.multilingual? && config.feeds.default_language_only
              default_lang = config.default_language
              site_pages = site_pages.select { |p|
                lang = p.language || default_lang
                lang == default_lang
              }
            end

            process_feed(site_pages, config, output_dir, config.feeds.filename, config.title, "", verbose)
          end

          # 2. Generate Section Feeds — pre-group pages by section for O(1) lookup
          pages_by_section = {} of String => Array(Models::Page)
          pages.each do |p|
            next if p.draft || !p.render || p.is_a?(Models::Section)
            (pages_by_section[p.section] ||= [] of Models::Page) << p
          end

          pages.each do |page|
            # Check if it's a section and has feed generation enabled
            if page.is_a?(Models::Section) && page.generate_feeds && page.render && !page.draft
              section_pages = pages_by_section[page.section]? || [] of Models::Page

              # Construct output path for section feed
              # e.g., output_dir/posts/rss.xml
              section_output_dir = File.join(output_dir, page.url.lchop("/"))
              FileUtils.mkdir_p(section_output_dir)

              feed_title = "#{config.title} - #{page.title}"

              process_feed(section_pages, config, section_output_dir, "", feed_title, page.url, verbose)
            end
          end

          # 3. Generate Language-specific Feeds (for non-default languages)
          if config.multilingual?
            generate_language_feeds(pages, config, output_dir, verbose)
          end
        end

        # Generate per-language feeds for non-default languages.
        # Each language with generate_feed=true gets its own feed at /{lang}/rss.xml (or atom.xml).
        private def self.generate_language_feeds(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false)
          default_lang = config.default_language

          config.languages.each do |lang_code, lang_config|
            # Skip the default language — it's already covered by the main feed
            next if lang_code == default_lang

            # Respect per-language generate_feed setting
            next unless lang_config.generate_feed

            # Filter pages for this language (single pass)
            lang_pages = pages.select { |p|
              !p.draft && p.render && !p.is_a?(Models::Section) && p.language == lang_code
            }

            # Apply section filter if configured on the main feed
            if !config.feeds.sections.empty?
              lang_pages.select! { |p|
                config.feeds.sections.any? { |s| p.section == s || p.section.starts_with?("#{s}/") }
              }
            end

            # Build the output directory: output_dir/{lang}/
            lang_output_dir = File.join(output_dir, lang_code)
            FileUtils.mkdir_p(lang_output_dir)

            # Build a language-specific feed title
            lang_name = lang_config.language_name
            feed_title = "#{config.title} (#{lang_name})"

            # base_path corresponds to the URL prefix for this language feed
            # e.g., "/ko/" so the self-referencing link becomes base_url/ko/rss.xml
            base_path = "/#{lang_code}/"

            process_feed(lang_pages, config, lang_output_dir, "", feed_title, base_path, verbose, lang_code)
          end
        end

        def self.process_feed(
          pages : Array(Models::Page),
          config : Models::Config,
          output_dir : String,
          custom_filename : String,
          feed_title : String,
          base_path : String = "",
          verbose : Bool = false,
          language : String? = nil,
        )
          # Determine feed type and filename
          feed_type = config.feeds.type.downcase
          unless ["rss", "atom"].includes?(feed_type)
            feed_type = "rss"
          end

          filename = if !custom_filename.empty?
                       custom_filename
                     else
                       feed_type == "atom" ? "atom.xml" : "rss.xml"
                     end

          # Sort a copy to avoid mutating the caller's array
          pages = pages.sort { |a, b| Utils::SortUtils.compare_by_date(a, b) }

          # Apply limit
          if config.feeds.limit > 0
            pages = pages.first(config.feeds.limit)
          end

          # Determine whether feed content will be plain text or HTML.
          # get_content_for_feed returns plain text when:
          # - full_content is false (uses description or 300-char summary)
          # - truncate > 0 (strips HTML and truncates)
          is_text = !config.feeds.full_content || config.feeds.truncate > 0

          # Generate feed content
          feed_content = case feed_type
                         when "atom"
                           generate_atom(pages, config, filename, is_text, feed_title, base_path, language)
                         else
                           generate_rss(pages, config, filename, is_text, feed_title, base_path, language)
                         end

          # Write feed file (basename prevents path traversal via config filename)
          feed_path = File.join(output_dir, File.basename(filename))
          File.write(feed_path, feed_content)
          Logger.action :create, feed_path if verbose
        end

        # Build the self-referencing feed URL from config, base path, and filename.
        private def self.build_feed_url(config : Models::Config, base_path : String, filename : String) : {String, String}
          base_url = config.base_url.rstrip('/')
          feed_url_path = base_path.empty? ? filename : File.join(base_path, filename)
          feed_url = "#{base_url}/#{feed_url_path.lchop("/")}"
          {base_url, feed_url}
        end

        # Build the full absolute URL for a page.
        private def self.page_full_url(page : Models::Page, base_url : String) : String
          path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
          base_url.empty? ? path : base_url + path
        end

        def self.generate_rss(
          pages : Array(Models::Page),
          config : Models::Config,
          filename : String,
          is_text : Bool,
          feed_title : String,
          base_path : String,
          language : String? = nil,
        ) : String
          base_url, feed_url = build_feed_url(config, base_path, filename)

          String.build(500 + pages.size * 300) do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            str << "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n"
            str << "  <channel>\n"
            str << "    <title>#{Utils::TextUtils.escape_xml(feed_title)}</title>\n"
            str << "    <link>#{Utils::TextUtils.escape_xml(config.base_url)}</link>\n"
            str << "    <description>#{Utils::TextUtils.escape_xml(config.description)}</description>\n"

            if language
              str << "    <language>#{Utils::TextUtils.escape_xml(language)}</language>\n"
            end

            str << "    <atom:link href=\"#{Utils::TextUtils.escape_xml(feed_url)}\" rel=\"self\" type=\"application/rss+xml\" />\n"

            pages.each do |page|
              str << "    <item>\n"
              str << "      <title>#{Utils::TextUtils.escape_xml(page.title)}</title>\n"

              full_url = page_full_url(page, base_url)
              escaped_url = Utils::TextUtils.escape_xml(full_url)
              str << "      <link>#{escaped_url}</link>\n"
              str << "      <guid>#{escaped_url}</guid>\n"

              content = get_content_for_feed(page, config)
              str << "      <description>#{Utils::TextUtils.escape_xml(content)}</description>\n"

              if pub_date = page.date
                str << "      <pubDate>#{pub_date.to_rfc2822}</pubDate>\n"
              end

              str << "    </item>\n"
            end

            str << "  </channel>\n"
            str << "</rss>\n"
          end
        end

        def self.generate_atom(
          pages : Array(Models::Page),
          config : Models::Config,
          filename : String,
          is_text : Bool,
          feed_title : String,
          base_path : String,
          language : String? = nil,
        ) : String
          now = Time.utc
          base_url, feed_url = build_feed_url(config, base_path, filename)

          String.build(500 + pages.size * 350) do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

            if language
              str << "<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"#{Utils::TextUtils.escape_xml(language)}\">\n"
            else
              str << "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            end

            str << "  <title>#{Utils::TextUtils.escape_xml(feed_title)}</title>\n"
            str << "  <link href=\"#{Utils::TextUtils.escape_xml(config.base_url)}\" />\n"
            str << "  <link href=\"#{Utils::TextUtils.escape_xml(feed_url)}\" rel=\"self\" />\n"
            str << "  <updated>#{now.to_rfc3339}</updated>\n"
            str << "  <id>#{Utils::TextUtils.escape_xml(config.base_url)}</id>\n"

            if !config.description.empty?
              str << "  <subtitle>#{Utils::TextUtils.escape_xml(config.description)}</subtitle>\n"
            end

            pages.each do |page|
              str << "  <entry>\n"
              str << "    <title>#{Utils::TextUtils.escape_xml(page.title)}</title>\n"

              full_url = page_full_url(page, base_url)
              escaped_url = Utils::TextUtils.escape_xml(full_url)
              str << "    <link href=\"#{escaped_url}\" />\n"
              str << "    <id>#{escaped_url}</id>\n"

              entry_date = (page.updated || page.date || now).to_utc
              str << "    <updated>#{entry_date.to_rfc3339}</updated>\n"

              content = get_content_for_feed(page, config)
              content_type = is_text ? "text" : "html"
              str << "    <content type=\"#{content_type}\">#{Utils::TextUtils.escape_xml(content)}</content>\n"

              str << "  </entry>\n"
            end

            str << "</feed>\n"
          end
        end

        private def self.get_content_for_feed(page : Models::Page, config : Models::Config) : String
          truncate = config.feeds.truncate
          full_content = config.feeds.full_content

          # When full_content is false, prefer the front matter description
          unless full_content
            if desc = page.description
              return desc unless desc.empty?
            end
            # Fall back to truncated content (default 300 chars)
            truncate = 300 if truncate <= 0
          end

          # Reuse already-rendered HTML from the Render phase when available,
          # avoiding an expensive duplicate Markdown → HTML conversion.
          html_content = if !page.content.empty?
                           page.content
                         else
                           rendered, _ = Processor::Markdown.render(page.raw_content)
                           rendered
                         end

          # Truncate if needed
          if truncate > 0
            # Strip HTML tags to get plain text for safe truncation
            text_content = Utils::TextUtils.strip_html(html_content)
            if text_content.size > truncate
              text_content[0...truncate] + "..."
            else
              text_content # Return plain text even if not truncated for consistency
            end
          else
            html_content # No truncation - return full HTML
          end
        end
      end
    end
  end
end
