require "base64"
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

        MIME_TYPES = {
          ".png"  => "image/png",
          ".jpg"  => "image/jpeg",
          ".jpeg" => "image/jpeg",
          ".svg"  => "image/svg+xml",
          ".gif"  => "image/gif",
          ".webp" => "image/webp",
        }

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

          # Validate and resolve output format
          format = ai.format
          unless {"svg", "png"}.includes?(format)
            Logger.warn "  Unknown OG image format '#{format}', falling back to SVG."
            format = "svg"
          end

          # Check PNG tool availability once if format is png
          png_tool = nil
          if format == "png"
            png_tool = find_png_tool
            if png_tool.nil?
              Logger.warn "  PNG format requested but no conversion tool found (resvg, rsvg-convert, or convert). Falling back to SVG."
            end
          end

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

            svg_filename = "#{slug}.svg"
            svg_path = File.join(img_dir, svg_filename)

            svg = render_svg(page, config)
            File.write(svg_path, svg)

            if format == "png" && png_tool
              png_filename = "#{slug}.png"
              png_path = File.join(img_dir, png_filename)
              if convert_svg_to_png(svg_path, png_path, png_tool)
                File.delete(svg_path) if File.exists?(svg_path)
                page.image = "/#{ai.output_dir}/#{png_filename}"
              else
                Logger.warn "  PNG conversion failed for #{svg_filename}, keeping SVG"
                page.image = "/#{ai.output_dir}/#{svg_filename}"
              end
            else
              page.image = "/#{ai.output_dir}/#{svg_filename}"
            end

            generated += 1
            Logger.debug "  OG image: #{page.image}" if verbose
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
          is_minimal = ai.style == "minimal"

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
            abs_path = logo_path.starts_with?("/") ? logo_path : File.join(Dir.current, logo_path)
            if File.exists?(abs_path)
              data_uri = file_to_data_uri(abs_path)
              logo_svg = %(<image href="#{data_uri}" x="80" y="#{HEIGHT - 100}" width="48" height="48" />)
            else
              # Fallback: reference logo as URL
              logo_url = logo_path.lchop("static/")
              logo_url = logo_url.starts_with?("/") ? logo_url : "/#{logo_url}"
              logo_svg = %(<image href="#{escape_attr(logo_url)}" x="80" y="#{HEIGHT - 100}" width="48" height="48" />)
            end
          end

          String.build do |svg|
            svg << %(<?xml version="1.0" encoding="UTF-8"?>\n)
            svg << %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" )
            svg << %(width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">\n)

            # Background
            svg << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{bg}" />\n)

            # Background image (if configured)
            if bg_image_path = ai.background_image
              abs_bg_path = bg_image_path.starts_with?("/") ? bg_image_path : File.join(Dir.current, bg_image_path)
              if File.exists?(abs_bg_path)
                bg_data_uri = file_to_data_uri(abs_bg_path)
                svg << %(<image href="#{bg_data_uri}" x="0" y="0" width="#{WIDTH}" height="#{HEIGHT}" preserveAspectRatio="xMidYMid slice" />\n)
                svg << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{bg}" opacity="#{ai.overlay_opacity}" />\n)
              end
            end

            # Style pattern
            pattern_svg = render_style_pattern(ai.style, accent, bg, ai.pattern_opacity, ai.pattern_scale)
            svg << pattern_svg unless pattern_svg.empty?

            # Accent bar at top (skip for minimal style)
            unless is_minimal
              svg << %(<rect width="#{WIDTH}" height="6" fill="#{accent}" />\n)
            end

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

            # Site name at bottom (controlled by show_title)
            if ai.show_title
              svg << %(<text x="#{logo_svg.empty? ? 80 : 140}" y="#{HEIGHT - 65}" )
              svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
              svg << %(font-size="22" font-weight="600" fill="#{accent}">)
              svg << site_name
              svg << %(</text>\n)
            end

            # Logo
            svg << logo_svg << "\n" unless logo_svg.empty?

            # Bottom border (skip for minimal style)
            unless is_minimal
              svg << %(<rect y="#{HEIGHT - 6}" width="#{WIDTH}" height="6" fill="#{accent}" />\n)
            end

            svg << %(</svg>\n)
          end
        end

        # Render a style/pattern SVG snippet based on the configured style
        def self.render_style_pattern(style : String, accent : String, bg : String, opacity : Float64, scale : Float64) : String
          case style
          when "dots"
            spacing = (20 * scale).to_i
            radius = Math.max((3 * scale).to_i, 1)
            String.build do |s|
              s << %(<defs><pattern id="dots" width="#{spacing}" height="#{spacing}" patternUnits="userSpaceOnUse">)
              s << %(<circle cx="#{spacing // 2}" cy="#{spacing // 2}" r="#{radius}" fill="#{accent}" />)
              s << %(</pattern></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#dots)" opacity="#{opacity}" />\n)
            end
          when "grid"
            spacing = (40 * scale).to_i
            String.build do |s|
              s << %(<defs><pattern id="grid" width="#{spacing}" height="#{spacing}" patternUnits="userSpaceOnUse">)
              s << %(<path d="M #{spacing} 0 L 0 0 0 #{spacing}" fill="none" stroke="#{accent}" stroke-width="1" />)
              s << %(</pattern></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#grid)" opacity="#{opacity}" />\n)
            end
          when "diagonal"
            spacing = (20 * scale).to_i
            String.build do |s|
              s << %(<defs><pattern id="diagonal" width="#{spacing}" height="#{spacing}" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">)
              s << %(<line x1="0" y1="0" x2="0" y2="#{spacing}" stroke="#{accent}" stroke-width="1" />)
              s << %(</pattern></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#diagonal)" opacity="#{opacity}" />\n)
            end
          when "gradient"
            String.build do |s|
              s << %(<defs><linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">)
              s << %(<stop offset="0%" stop-color="#{accent}" stop-opacity="#{opacity}" />)
              s << %(<stop offset="100%" stop-color="#{accent}" stop-opacity="0" />)
              s << %(</linearGradient></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#grad)" />\n)
            end
          when "waves"
            amp = (20 * scale).to_i
            String.build do |s|
              3.times do |i|
                y_offset = HEIGHT // 3 + i * (80 * scale).to_i
                s << %(<path d="M 0 #{y_offset} Q 300 #{y_offset - amp} 600 #{y_offset} T 1200 #{y_offset}" )
                s << %(fill="none" stroke="#{accent}" stroke-width="2" opacity="#{opacity}" />\n)
              end
            end
          when "minimal", "default"
            ""
          else
            ""
          end
        end

        # Convert a file to a data URI with base64 encoding
        private def self.file_to_data_uri(file_path : String) : String
          ext = File.extname(file_path).downcase
          mime = MIME_TYPES[ext]? || "application/octet-stream"
          data = File.open(file_path, "rb") { |f| f.getb_to_end }
          encoded = Base64.strict_encode(data)
          "data:#{mime};base64,#{encoded}"
        end

        # Find an available PNG conversion tool
        private def self.find_png_tool : String?
          {"resvg", "rsvg-convert", "convert"}.each do |tool|
            result = Process.run("which", [tool], output: Process::Redirect::Pipe, error: Process::Redirect::Close)
            return tool if result.success?
          end
          nil
        end

        # Convert SVG to PNG using an external tool
        private def self.convert_svg_to_png(svg_path : String, png_path : String, tool : String) : Bool
          args = case tool
                 when "resvg"
                   [svg_path, png_path]
                 when "rsvg-convert"
                   ["-o", png_path, svg_path]
                 when "convert"
                   [svg_path, png_path]
                 else
                   return false
                 end
          result = Process.run(tool, args, output: Process::Redirect::Close, error: Process::Redirect::Close)
          result.success?
        rescue
          false
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
