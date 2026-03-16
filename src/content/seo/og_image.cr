require "file_utils"
require "../../models/config"
require "../../models/page"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Seo
      # Auto-generate OG (Open Graph) preview images as SVG files.
      # Produces 1200x630 SVG images with the page title, description,
      # site name, and optional logo — all without external dependencies.
      class OgImage
        WIDTH  = 1200
        HEIGHT =  630

        # Generate OG images for all pages that lack a custom image.
        # Sets page.image to the generated SVG path so that og:image
        # meta tags pick it up automatically.
        def self.generate(
          pages : Array(Models::Page),
          config : Models::Config,
          output_dir : String,
          verbose : Bool = false,
        )
          ai = config.og.auto_image
          return unless ai.enabled

          img_dir = File.join(output_dir, ai.output_dir)
          FileUtils.mkdir_p(img_dir) unless Dir.exists?(img_dir)

          generated = 0

          pages.each do |page|
            next if page.draft
            next if page.generated
            next unless page.render
            next if page.image # Skip pages that already have a custom image

            # Use URL-based slug to avoid collisions between pages with the same title
            # in different sections (e.g., /posts/hello/ and /guides/hello/)
            url_slug = page.url.gsub("/", "-").strip("-")
            slug = url_slug.empty? ? Utils::TextUtils.slugify(page.title) : url_slug
            slug = "page" if slug.empty?
            filename = "#{slug}.svg"
            relative_path = "/#{ai.output_dir}/#{filename}"

            svg = render_svg(page, config)

            file_path = File.join(img_dir, filename)
            File.write(file_path, svg)

            # Set the page image so og:image picks it up
            page.image = relative_path
            generated += 1
            Logger.debug "  OG image: #{file_path}" if verbose
          end

          Logger.info "  Generated #{generated} OG image(s)" if generated > 0
        end

        # Render an SVG image for a page
        def self.render_svg(page : Models::Page, config : Models::Config) : String
          ai = config.og.auto_image
          bg = escape_attr(ai.background)
          text_color = escape_attr(ai.text_color)
          accent = escape_attr(ai.accent_color)
          font_size = Math.max(ai.font_size, 1)
          desc_size = Math.max((font_size * 0.45).to_i, 1)
          site_name = escape_xml(config.title)
          title = escape_xml(page.title)
          description = escape_xml(page.description || "")

          # Word-wrap title for SVG (approx 25 chars per line at 48px in 1200px width)
          chars_per_line = (900 / (font_size * 0.55)).to_i
          title_lines = word_wrap(page.title, chars_per_line)
          desc_lines = word_wrap(page.description || "", (900 / (desc_size * 0.55)).to_i)

          # Calculate vertical positioning
          title_block_height = title_lines.size * (font_size + 8)
          desc_block_height = desc_lines.empty? ? 0 : desc_lines.size * (desc_size + 6)
          total_text_height = title_block_height + desc_block_height + 20
          title_start_y = Math.max(font_size + 20, ((HEIGHT - total_text_height) / 2).to_i + font_size)

          # Build logo element
          logo_svg = ""
          if logo_path = ai.logo
            # Reference logo as image in SVG — strip static/ prefix and ensure leading /
            logo_url = logo_path.sub(/\Astatic\//, "")
            logo_url = logo_url.starts_with?("/") ? logo_url : "/#{logo_url}"
            logo_svg = %(<image href="#{escape_attr(logo_url)}" x="80" y="#{HEIGHT - 100}" width="48" height="48" />)
          end

          String.build do |svg|
            svg << %(<?xml version="1.0" encoding="UTF-8"?>\n)
            svg << %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" )
            svg << %(width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">\n)

            # Background
            svg << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{bg}" />\n)

            # Accent bar at top
            svg << %(<rect width="#{WIDTH}" height="6" fill="#{accent}" />\n)

            # Title text
            title_lines.each_with_index do |line, i|
              y = title_start_y + i * (font_size + 8)
              svg << %(<text x="80" y="#{y}" )
              svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
              svg << %(font-size="#{font_size}" font-weight="700" fill="#{text_color}">)
              svg << escape_xml(line)
              svg << %(</text>\n)
            end

            # Description text
            unless desc_lines.empty?
              desc_start_y = title_start_y + title_block_height + 16
              desc_lines.each_with_index do |line, i|
                y = desc_start_y + i * (desc_size + 6)
                svg << %(<text x="80" y="#{y}" )
                svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
                svg << %(font-size="#{desc_size}" font-weight="400" fill="#{text_color}" opacity="0.75">)
                svg << escape_xml(line)
                svg << %(</text>\n)
              end
            end

            # Site name at bottom
            svg << %(<text x="#{logo_svg.empty? ? 80 : 140}" y="#{HEIGHT - 65}" )
            svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
            svg << %(font-size="22" font-weight="600" fill="#{accent}">)
            svg << site_name
            svg << %(</text>\n)

            # Logo
            svg << logo_svg << "\n" unless logo_svg.empty?

            # Bottom border
            svg << %(<rect y="#{HEIGHT - 6}" width="#{WIDTH}" height="6" fill="#{accent}" />\n)

            svg << %(</svg>\n)
          end
        end

        # Word-wrap text to fit within a character limit per line
        private def self.word_wrap(text : String, max_chars : Int32) : Array(String)
          return [] of String if text.empty?
          max_chars = 10 if max_chars < 10 # safety minimum

          words = text.split(/\s+/)
          lines = [] of String
          current_line = ""

          words.each do |word|
            if current_line.empty?
              current_line = word
            elsif (current_line.size + 1 + word.size) <= max_chars
              current_line += " #{word}"
            else
              lines << current_line
              current_line = word
            end
          end

          lines << current_line unless current_line.empty?

          # Limit to reasonable number of lines
          lines.first(4)
        end

        private def self.escape_xml(text : String) : String
          Utils::TextUtils.escape_xml(text)
        end

        private def self.escape_attr(text : String) : String
          Utils::TextUtils.escape_xml(text)
        end
      end
    end
  end
end
