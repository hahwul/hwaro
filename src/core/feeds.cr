require "../schemas/config"
require "../schemas/page"
require "../logger/logger"
require "../processor/markdown"

module Hwaro
  module Core
    class Feeds
      def self.generate(pages : Array(Schemas::Page), config : Schemas::Config, output_dir : String)
        return unless config.feeds.generate

        # Determine feed type and filename
        feed_type = config.feeds.type.downcase
        unless ["rss", "atom"].includes?(feed_type)
          Logger.warn "  [WARN] Invalid feed type '#{feed_type}'. Defaulting to 'rss'."
          feed_type = "rss"
        end

        filename = if config.feeds.filename.empty?
                     feed_type == "atom" ? "atom.xml" : "rss.xml"
                   else
                     config.feeds.filename
                   end

        # Filter and sort pages for feed (exclude drafts, sort by date/creation)
        feed_pages = pages.reject(&.draft)
        
        # Sort by date if available, otherwise keep original order
        # Pages with dates come first (most recent first), then pages without dates
        feed_pages.sort! { |a, b| 
          if a.date && b.date
            b.date.not_nil! <=> a.date.not_nil!  # Most recent first
          elsif a.date
            -1  # a has date, b doesn't - a comes first
          elsif b.date
            1   # b has date, a doesn't - b comes first
          else
            0   # Neither has date - maintain order
          end
        }

        # Generate feed content based on type
        feed_content = case feed_type
                      when "atom"
                        generate_atom(feed_pages, config, filename)
                      else
                        generate_rss(feed_pages, config, filename)
                      end

        # Write feed file
        feed_path = File.join(output_dir, filename)
        File.write(feed_path, feed_content)
        Logger.action :create, feed_path
        Logger.info "  Generated #{feed_type.upcase} feed with #{feed_pages.size} items."
      end

      private def self.generate_rss(pages : Array(Schemas::Page), config : Schemas::Config, filename : String) : String
        String.build do |str|
          str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          str << "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n"
          str << "  <channel>\n"
          str << "    <title>#{escape_xml(config.title)}</title>\n"
          str << "    <link>#{escape_xml(config.base_url)}</link>\n"
          str << "    <description>#{escape_xml(config.description)}</description>\n"
          
          # Self-referencing link
          feed_url = "#{config.base_url.rstrip('/')}/#{filename}"
          str << "    <atom:link href=\"#{escape_xml(feed_url)}\" rel=\"self\" type=\"application/rss+xml\" />\n"
          
          pages.each do |page|
            next if page.draft
            
            str << "    <item>\n"
            str << "      <title>#{escape_xml(page.title)}</title>\n"
            
            # Build full URL
            base = config.base_url.rstrip('/')
            path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
            full_url = base.empty? ? path : base + path
            str << "      <link>#{escape_xml(full_url)}</link>\n"
            str << "      <guid>#{escape_xml(full_url)}</guid>\n"
            
            # Add description/content
            content = get_content_for_feed(page, config.feeds.truncate)
            str << "      <description>#{escape_xml(content)}</description>\n"
            
            # Add date if available
            if date = page.date
              str << "      <pubDate>#{date.to_rfc2822}</pubDate>\n"
            end
            
            str << "    </item>\n"
          end
          
          str << "  </channel>\n"
          str << "</rss>\n"
        end
      end

      private def self.generate_atom(pages : Array(Schemas::Page), config : Schemas::Config, filename : String) : String
        now = Time.utc
        
        String.build do |str|
          str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          str << "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
          str << "  <title>#{escape_xml(config.title)}</title>\n"
          str << "  <link href=\"#{escape_xml(config.base_url)}\" />\n"
          
          # Self-referencing link
          feed_url = "#{config.base_url.rstrip('/')}/#{filename}"
          str << "  <link href=\"#{escape_xml(feed_url)}\" rel=\"self\" />\n"
          
          str << "  <updated>#{now.to_rfc3339}</updated>\n"
          str << "  <id>#{escape_xml(config.base_url)}</id>\n"
          
          if !config.description.empty?
            str << "  <subtitle>#{escape_xml(config.description)}</subtitle>\n"
          end
          
          pages.each do |page|
            next if page.draft
            
            str << "  <entry>\n"
            str << "    <title>#{escape_xml(page.title)}</title>\n"
            
            # Build full URL
            base = config.base_url.rstrip('/')
            path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
            full_url = base.empty? ? path : base + path
            str << "    <link href=\"#{escape_xml(full_url)}\" />\n"
            str << "    <id>#{escape_xml(full_url)}</id>\n"
            
            # Add date
            entry_date = page.date || now
            str << "    <updated>#{entry_date.to_rfc3339}</updated>\n"
            
            # Add content
            content = get_content_for_feed(page, config.feeds.truncate)
            str << "    <content type=\"html\">#{escape_xml(content)}</content>\n"
            
            str << "  </entry>\n"
          end
          
          str << "</feed>\n"
        end
      end

      private def self.get_content_for_feed(page : Schemas::Page, truncate : Int32) : String
        # Convert markdown to HTML for feed
        html_content, _ = Processor::Markdown.render(page.raw_content)
        
        # Truncate if needed
        if truncate > 0 && html_content.size > truncate
          # Strip HTML tags before truncating to avoid breaking tags
          text_content = html_content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
          if text_content.size > truncate
            html_content = text_content[0...truncate] + "..."
          end
        end
        
        html_content
      end

      private def self.escape_xml(text : String) : String
        text.gsub(/[&<>"']/) do |match|
          case match
          when "&"  then "&amp;"
          when "<"  then "&lt;"
          when ">"  then "&gt;"
          when "\"" then "&quot;"
          when "'"  then "&apos;"
          else           match
          end
        end
      end
    end
  end
end
