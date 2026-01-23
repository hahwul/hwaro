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
        def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false)
          # 1. Generate Main Site Feed
          if config.feeds.enabled
            site_pages = pages.reject { |p| p.draft || !p.render || p.is_index }

            # Filter by section if configured for main feed
            if !config.feeds.sections.empty?
              site_pages.select! { |p| config.feeds.sections.includes?(p.section) }
            end

            process_feed(site_pages, config, output_dir, config.feeds.filename, config.title, "", verbose)
          end

          # 2. Generate Section Feeds
          pages.each do |page|
            # Check if it's a section and has feed generation enabled
            if page.is_a?(Models::Section) && page.generate_feeds && page.render && !page.draft
              # Section feed only includes pages from that specific section (shallow)
              # It does not include subsections or pages from other sections
              section_pages = pages.select { |p|
                !p.draft && p.render && !p.is_index && p.section == page.section
              }

              # Construct output path for section feed
              # e.g., output_dir/posts/rss.xml
              section_output_dir = File.join(output_dir, page.url.sub(/^\//, ""))
              FileUtils.mkdir_p(section_output_dir)

              feed_title = "#{config.title} - #{page.title}"

              process_feed(section_pages, config, section_output_dir, "", feed_title, page.url, verbose)
            end
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

          # Sort pages: updated > date > none (newest first)
          pages.sort! { |a, b| Utils::SortUtils.compare_by_date(a, b) }

          # Apply limit
          if config.feeds.limit > 0
            pages = pages.first(config.feeds.limit)
          end

          # Generate feed content
          feed_content = case feed_type
                         when "atom"
                           generate_atom(pages, config, filename, config.feeds.truncate > 0, feed_title, base_path)
                         else
                           generate_rss(pages, config, filename, config.feeds.truncate > 0, feed_title, base_path)
                         end

          # Write feed file
          feed_path = File.join(output_dir, filename)
          File.write(feed_path, feed_content)
          Logger.action :create, feed_path if verbose
        end

        def self.generate_rss(
          pages : Array(Models::Page),
          config : Models::Config,
          filename : String,
          is_text : Bool,
          feed_title : String,
          base_path : String,
        ) : String
          String.build do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            str << "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n"
            str << "  <channel>\n"
            str << "    <title>#{Utils::TextUtils.escape_xml(feed_title)}</title>\n"
            str << "    <link>#{Utils::TextUtils.escape_xml(config.base_url)}</link>\n"
            str << "    <description>#{Utils::TextUtils.escape_xml(config.description)}</description>\n"

            # Self-referencing link
            base_url = config.base_url.rstrip('/')
            feed_url_path = base_path.empty? ? filename : File.join(base_path, filename)
            feed_url = "#{base_url}/#{feed_url_path.sub(/^\//, "")}"

            str << "    <atom:link href=\"#{Utils::TextUtils.escape_xml(feed_url)}\" rel=\"self\" type=\"application/rss+xml\" />\n"

            pages.each do |page|
              str << "    <item>\n"
              str << "      <title>#{Utils::TextUtils.escape_xml(page.title)}</title>\n"

              # Build full URL
              path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
              full_url = base_url.empty? ? path : base_url + path
              str << "      <link>#{Utils::TextUtils.escape_xml(full_url)}</link>\n"
              str << "      <guid>#{Utils::TextUtils.escape_xml(full_url)}</guid>\n"

              # Add description/content
              content = get_content_for_feed(page, config.feeds.truncate)
              str << "      <description>#{Utils::TextUtils.escape_xml(content)}</description>\n"

              # Add date if available (prefer updated, then date)
              if date = (page.updated || page.date)
                str << "      <pubDate>#{date.to_rfc2822}</pubDate>\n"
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
        ) : String
          now = Time.utc

          String.build do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            str << "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            str << "  <title>#{Utils::TextUtils.escape_xml(feed_title)}</title>\n"
            str << "  <link href=\"#{Utils::TextUtils.escape_xml(config.base_url)}\" />\n"

            # Self-referencing link
            base_url = config.base_url.rstrip('/')
            feed_url_path = base_path.empty? ? filename : File.join(base_path, filename)
            feed_url = "#{base_url}/#{feed_url_path.sub(/^\//, "")}"

            str << "  <link href=\"#{Utils::TextUtils.escape_xml(feed_url)}\" rel=\"self\" />\n"

            str << "  <updated>#{now.to_rfc3339}</updated>\n"
            str << "  <id>#{Utils::TextUtils.escape_xml(config.base_url)}</id>\n"

            if !config.description.empty?
              str << "  <subtitle>#{Utils::TextUtils.escape_xml(config.description)}</subtitle>\n"
            end

            pages.each do |page|
              str << "  <entry>\n"
              str << "    <title>#{Utils::TextUtils.escape_xml(page.title)}</title>\n"

              # Build full URL
              path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
              full_url = base_url.empty? ? path : base_url + path
              str << "    <link href=\"#{Utils::TextUtils.escape_xml(full_url)}\" />\n"
              str << "    <id>#{Utils::TextUtils.escape_xml(full_url)}</id>\n"

              # Add date
              entry_date = page.updated || page.date || now
              str << "    <updated>#{entry_date.to_rfc3339}</updated>\n"

              # Add content with appropriate type
              content = get_content_for_feed(page, config.feeds.truncate)
              content_type = is_text ? "text" : "html"
              str << "    <content type=\"#{content_type}\">#{Utils::TextUtils.escape_xml(content)}</content>\n"

              str << "  </entry>\n"
            end

            str << "</feed>\n"
          end
        end

        private def self.get_content_for_feed(page : Models::Page, truncate : Int32) : String
          # Convert markdown to HTML for feed
          html_content, _ = Processor::Markdown.render(page.raw_content)

          # Truncate if needed
          if truncate > 0
            # Strip HTML tags to get plain text for safe truncation
            text_content = html_content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
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
