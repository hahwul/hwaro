require "file_utils"
require "../../ext/stb_bindings"
require "../../models/config"
require "../../models/page"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Seo
      # Renders OG images directly as PNG using stb_truetype + stb_image_write.
      # No external tools required — all rendering is done in-process.
      class OgPngRenderer
        WIDTH    = 1200
        HEIGHT   =  630
        CHANNELS =    4 # RGBA

        # Bundled DejaVu Sans Bold font (compiled into the binary as fallback)
        BUNDLED_FONT_BOLD = {{ read_file("#{__DIR__}/../../ext/fonts/DejaVuSans-Bold.ttf") }}

        # System font search paths (platform-dependent)
        FONT_SEARCH_PATHS = [
          # macOS
          "/System/Library/Fonts/Helvetica.ttc",
          "/System/Library/Fonts/ArialHB.ttc",
          "/System/Library/Fonts/Geneva.ttf",
          "/System/Library/Fonts/Supplemental/Arial.ttf",
          "/Library/Fonts/Arial.ttf",
          # Linux (common distributions)
          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
          "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
          "/usr/share/fonts/TTF/DejaVuSans.ttf",
          "/usr/share/fonts/dejavu/DejaVuSans.ttf",
          "/usr/share/fonts/noto/NotoSans-Regular.ttf",
          "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
          "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        ]

        # Bold font variants to search for
        BOLD_FONT_SEARCH_PATHS = [
          # macOS
          "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
          "/Library/Fonts/Arial Bold.ttf",
          # Linux
          "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
          "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
          "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
          "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
          "/usr/share/fonts/noto/NotoSans-Bold.ttf",
          "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
          "/usr/share/fonts/google-noto/NotoSans-Bold.ttf",
        ]

        # Try to find a system font, returns file path or nil
        def self.find_system_font(bold : Bool = false) : String?
          paths = bold ? BOLD_FONT_SEARCH_PATHS : FONT_SEARCH_PATHS
          paths.each do |path|
            return path if File.exists?(path)
          end
          # Fallback: if bold not found, use regular
          if bold
            FONT_SEARCH_PATHS.each do |path|
              return path if File.exists?(path)
            end
          end
          nil
        end

        # Check if PNG rendering is available (always true thanks to bundled fonts)
        def self.available? : Bool
          true
        end

        # Pre-decoded and resized RGBA image for reuse across render calls.
        class CachedImage
          getter data : Pointer(UInt8)
          getter width : Int32
          getter height : Int32

          def initialize(@data, @width, @height)
          end

          def finalize
            LibC.free(@data.as(Void*)) unless @data.null?
          end
        end

        # Decode an image file and resize it to target dimensions. Returns nil on failure.
        def self.load_image(path : String, target_w : Int32, target_h : Int32) : CachedImage?
          return nil unless File.exists?(path)

          src_w = uninitialized LibC::Int
          src_h = uninitialized LibC::Int
          channels = uninitialized LibC::Int
          src_pixels = LibStb.stbi_load(path, pointerof(src_w), pointerof(src_h), pointerof(channels), 4)
          return nil if src_pixels.null?

          begin
            return nil if src_w <= 0 || src_h <= 0

            buf_size = target_w.to_i64 * target_h.to_i64 * 4
            return nil if buf_size > 64_000_000_i64 * 4

            resized = LibC.malloc(buf_size).as(UInt8*)
            return nil if resized.null?

            result = LibStb.stbir_resize_uint8_linear(
              src_pixels, src_w, src_h, 0,
              resized, target_w, target_h, 0, 4
            )
            if result.null?
              LibC.free(resized.as(Void*))
              return nil
            end

            CachedImage.new(resized, target_w, target_h)
          ensure
            LibStb.stbi_image_free(src_pixels.as(Void*))
          end
        end

        # Pre-loaded font context for reuse across multiple render calls.
        # Holds font data bytes (must stay alive while font_info is in use)
        # and the opaque stbtt_fontinfo pointer.
        class FontContext
          getter bold_data : Bytes
          getter bold_info : LibStb::HwaroFontInfo
          getter regular_data : Bytes?
          getter regular_info : LibStb::HwaroFontInfo?

          def initialize(@bold_data, @bold_info, @regular_data = nil, @regular_info = nil)
          end

          def finalize
            LibStb.hwaro_font_free(@bold_info) unless @bold_info.null?
            if ri = @regular_info
              LibStb.hwaro_font_free(ri) unless ri.null?
            end
          end
        end

        # Initialize a single font from raw bytes. Returns {info, data} or nil.
        private def self.init_font(data : Bytes) : {LibStb::HwaroFontInfo, Bytes}?
          info = LibStb.hwaro_font_alloc
          return nil if info.null?
          if LibStb.hwaro_font_init(info, data, 0) != 0
            {info, data}
          else
            LibStb.hwaro_font_free(info)
            nil
          end
        end

        # Read a font file and initialize it. Returns {info, data} or nil.
        private def self.load_font_file(path : String) : {LibStb::HwaroFontInfo, Bytes}?
          return nil unless File.exists?(path)
          data = File.open(path, "rb") { |f| f.getb_to_end }
          init_font(data)
        end

        # Load fonts once, return a reusable context. Returns nil if no font found.
        # Priority: custom font_path > system fonts > bundled DejaVu Sans Bold.
        def self.load_fonts(custom_font_path : String? = nil) : FontContext?
          # 1) Custom font path (user-specified via config)
          if cfp = custom_font_path
            abs = cfp.starts_with?("/") ? cfp : File.join(Dir.current, cfp)
            if result = load_font_file(abs)
              bold_info, bold_data = result
              return FontContext.new(bold_data, bold_info)
            end
            Logger.warn "  Custom font '#{cfp}' not found or failed to load. Trying system fonts."
          end

          # 2) System fonts
          bold_path = find_system_font(bold: true)
          regular_path = find_system_font(bold: false)
          font_path = bold_path || regular_path

          if font_path
            if result = load_font_file(font_path)
              bold_info, bold_data = result
              # Try loading a separate regular font
              regular_info = nil
              regular_data = nil
              r_path = regular_path
              if r_path && r_path != font_path
                if r_result = load_font_file(r_path)
                  regular_info, regular_data = r_result
                end
              end
              return FontContext.new(bold_data, bold_info, regular_data, regular_info)
            end
          end

          # 3) Bundled fallback (DejaVu Sans Bold)
          if result = init_font(BUNDLED_FONT_BOLD.to_slice.dup)
            bold_info, bold_data = result
            return FontContext.new(bold_data, bold_info)
          end

          nil
        end

        # Render OG image directly to PNG file. Returns true on success.
        # Accepts optional pre-loaded CachedImage for logo/background to avoid
        # repeated decode+resize when generating many pages.
        def self.render_png(
          page : Models::Page,
          config : Models::Config,
          png_path : String,
          logo_image_path : String? = nil,
          bg_image_path : String? = nil,
          font_ctx : FontContext? = nil,
          cached_logo : CachedImage? = nil,
          cached_bg : CachedImage? = nil,
        ) : Bool
          ai = config.og.auto_image
          is_minimal = ai.style == "minimal"

          # Parse colors
          bg_color = parse_hex_color(ai.background)
          text_color = parse_hex_color(ai.text_color)
          accent_color = parse_hex_color(ai.accent_color)

          # Allocate pixel buffer (RGBA) with LibC.malloc for explicit lifecycle control.
          buf_size = WIDTH * HEIGHT * CHANNELS
          pixels = LibC.malloc(buf_size).as(UInt8*)
          return false if pixels.null?

          begin
            # 1. Fill background
            fill_rect(pixels, 0, 0, WIDTH, HEIGHT, bg_color)

            # 2. Background image (if configured)
            if bg_image_path
              if cbg = cached_bg
                blit_cached_image(pixels, cbg, 0, 0)
              else
                composite_image(pixels, bg_image_path, 0, 0, WIDTH, HEIGHT)
              end
              # Overlay
              fill_rect_alpha(pixels, 0, 0, WIDTH, HEIGHT, bg_color, ai.overlay_opacity)
            end

            # 3. Style pattern
            render_pattern(pixels, ai.style, accent_color, ai.pattern_opacity, ai.pattern_scale)

            # 4. Accent bar at top
            unless is_minimal
              fill_rect(pixels, 0, 0, WIDTH, 6, accent_color)
            end

            # 5. Render text
            if ctx = font_ctx
              render_text_content(pixels, page, config, ctx, text_color, accent_color)
            end

            # 6. Logo image
            if logo_image_path
              logo_x, logo_y = case ai.logo_position
                               when "bottom-right" then {WIDTH - 80 - 48, HEIGHT - 100}
                               when "top-left"     then {80, 20}
                               when "top-right"    then {WIDTH - 80 - 48, 20}
                               else                     {80, HEIGHT - 100} # bottom-left
                               end
              if clogo = cached_logo
                blit_cached_image(pixels, clogo, logo_x, logo_y)
              else
                composite_image(pixels, logo_image_path, logo_x, logo_y, 48, 48)
              end
            end

            # 7. Bottom accent bar
            unless is_minimal
              fill_rect(pixels, 0, HEIGHT - 6, WIDTH, 6, accent_color)
            end

            # Write PNG
            FileUtils.mkdir_p(File.dirname(png_path))
            result = LibStb.stbi_write_png(
              png_path, WIDTH, HEIGHT, CHANNELS,
              pixels.as(Void*), WIDTH * CHANNELS
            )
            result != 0
          ensure
            LibC.free(pixels.as(Void*))
          end
        end

        # Render text content using a pre-loaded FontContext.
        # The FontContext owns the font data and stbtt_fontinfo pointers,
        # so there is no use-after-free risk here.
        private def self.render_text_content(
          pixels : UInt8*,
          page : Models::Page,
          config : Models::Config,
          ctx : FontContext,
          text_color : UInt32,
          accent_color : UInt32,
        )
          ai = config.og.auto_image
          font_size = Math.max(ai.font_size, 1).to_f32
          desc_size = Math.max((font_size * 0.45).to_i, 1).to_f32

          bold_info = ctx.bold_info
          bold_scale = LibStb.hwaro_font_scale_for_pixel_height(bold_info, font_size)

          # Use regular font if available, otherwise fall back to bold
          r_info = ctx.regular_info || bold_info
          r_scale = LibStb.hwaro_font_scale_for_pixel_height(r_info, desc_size)

          # Word-wrap
          title_lines = word_wrap_measured(bold_info, bold_scale, page.title, WIDTH - 160)
          desc_text = page.description || ""
          desc_lines = desc_text.empty? ? [] of String : word_wrap_measured(r_info, r_scale, desc_text, WIDTH - 160)

          # Vertical positioning
          title_block_height = title_lines.size * (font_size + 8)
          desc_block_height = desc_lines.empty? ? 0 : desc_lines.size * (desc_size + 6)
          total_text_height = title_block_height + desc_block_height + 20
          title_start_y = Math.max(font_size + 20, ((HEIGHT - total_text_height) / 2).to_f32 + font_size)

          # Render title lines
          title_lines.each_with_index do |line, i|
            y = title_start_y + i * (font_size + 8)
            LibStb.hwaro_font_render_text(bold_info, pixels, WIDTH, HEIGHT, 80_f32, y - font_size, bold_scale, line, text_color, 1.0_f32)
          end

          # Render description
          unless desc_lines.empty?
            desc_start_y = title_start_y + title_block_height + 16
            desc_lines.each_with_index do |line, i|
              y = desc_start_y + i * (desc_size + 6)
              LibStb.hwaro_font_render_text(r_info, pixels, WIDTH, HEIGHT, 80_f32, y - desc_size, r_scale, line, text_color, 0.75_f32)
            end
          end

          # Site name
          if ai.show_title
            site_scale = LibStb.hwaro_font_scale_for_pixel_height(bold_info, 22_f32)
            site_x = (ai.logo && ai.logo_position == "bottom-left") ? 140_f32 : 80_f32
            LibStb.hwaro_font_render_text(bold_info, pixels, WIDTH, HEIGHT, site_x, (HEIGHT - 65 - 22).to_f32, site_scale, config.title, accent_color, 1.0_f32)
          end
        end

        # Word-wrap using incremental measured text width.
        # Handles CJK characters by allowing breaks between any CJK characters.
        private def self.word_wrap_measured(font_info : LibStb::HwaroFontInfo, scale : Float32, text : String, max_width : Int32) : Array(String)
          return [] of String if text.empty?
          segments = Content::Seo::OgImage.split_into_segments(text)
          lines = [] of String
          current_line = ""
          current_width = 0_f32

          segments.each do |seg|
            seg_width = LibStb.hwaro_font_measure_text(font_info, seg, scale)
            if current_line.empty?
              current_line = seg
              current_width = seg_width
            elsif current_width + seg_width <= max_width
              current_line += seg
              current_width += seg_width
            else
              lines << current_line.strip
              current_line = seg.lstrip
              current_width = LibStb.hwaro_font_measure_text(font_info, current_line, scale)
            end
          end
          lines << current_line.strip unless current_line.strip.empty?
          lines.first(4)
        end

        # Parse "#RRGGBB" to 0xRRGGBB
        def self.parse_hex_color(hex : String) : UInt32
          hex = hex.lchop("#")
          hex.to_u32(16) rescue 0x000000_u32
        end

        # Fill a solid rectangle
        private def self.fill_rect(pixels : UInt8*, x : Int32, y : Int32, w : Int32, h : Int32, color : UInt32)
          r = ((color >> 16) & 0xFF).to_u8
          g = ((color >> 8) & 0xFF).to_u8
          b = (color & 0xFF).to_u8

          (y...Math.min(y + h, HEIGHT)).each do |py|
            (x...Math.min(x + w, WIDTH)).each do |px|
              idx = (py * WIDTH + px) * CHANNELS
              pixels[idx] = r
              pixels[idx + 1] = g
              pixels[idx + 2] = b
              pixels[idx + 3] = 255_u8
            end
          end
        end

        # Fill a rectangle with alpha blending
        private def self.fill_rect_alpha(pixels : UInt8*, x : Int32, y : Int32, w : Int32, h : Int32, color : UInt32, opacity : Float64)
          r = ((color >> 16) & 0xFF).to_u8
          g = ((color >> 8) & 0xFF).to_u8
          b = (color & 0xFF).to_u8
          alpha = opacity.clamp(0.0, 1.0)

          (y...Math.min(y + h, HEIGHT)).each do |py|
            (x...Math.min(x + w, WIDTH)).each do |px|
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]
              dg = pixels[idx + 1]
              db = pixels[idx + 2]
              pixels[idx] = (dr + (r.to_f - dr) * alpha).to_u8
              pixels[idx + 1] = (dg + (g.to_f - dg) * alpha).to_u8
              pixels[idx + 2] = (db + (b.to_f - db) * alpha).to_u8
            end
          end
        end

        # Alpha-blend a pre-decoded CachedImage onto the pixel buffer
        private def self.blit_cached_image(pixels : UInt8*, cached : CachedImage, dx : Int32, dy : Int32)
          dw = cached.width
          dh = cached.height
          src = cached.data

          dh.times do |ry|
            py = dy + ry
            next if py < 0 || py >= HEIGHT
            dw.times do |rx|
              px = dx + rx
              next if px < 0 || px >= WIDTH
              src_idx = (ry * dw + rx) * 4
              dst_idx = (py * WIDTH + px) * CHANNELS
              sa = src[src_idx + 3].to_f / 255.0
              next if sa <= 0
              pixels[dst_idx] = (pixels[dst_idx] + (src[src_idx].to_f - pixels[dst_idx]) * sa).to_u8
              pixels[dst_idx + 1] = (pixels[dst_idx + 1] + (src[src_idx + 1].to_f - pixels[dst_idx + 1]) * sa).to_u8
              pixels[dst_idx + 2] = (pixels[dst_idx + 2] + (src[src_idx + 2].to_f - pixels[dst_idx + 2]) * sa).to_u8
              pixels[dst_idx + 3] = 255_u8
            end
          end
        end

        # Composite an image file onto the pixel buffer, scaled to fit
        private def self.composite_image(pixels : UInt8*, image_path : String, dx : Int32, dy : Int32, dw : Int32, dh : Int32)
          return unless File.exists?(image_path)

          src_w = uninitialized LibC::Int
          src_h = uninitialized LibC::Int
          channels = uninitialized LibC::Int
          src_pixels = LibStb.stbi_load(image_path, pointerof(src_w), pointerof(src_h), pointerof(channels), 4) # force RGBA
          return if src_pixels.null?

          begin
            return if src_w <= 0 || src_h <= 0

            # Resize to destination dimensions
            buf_size = dw.to_i64 * dh.to_i64 * 4
            return if buf_size > 64_000_000_i64 * 4

            resized = LibC.malloc(buf_size).as(UInt8*)
            return if resized.null?

            begin
              result = LibStb.stbir_resize_uint8_linear(
                src_pixels, src_w, src_h, 0,
                resized, dw, dh, 0, 4
              )
              return if result.null?

              # Alpha-blend onto destination
              dh.times do |ry|
                py = dy + ry
                next if py < 0 || py >= HEIGHT
                dw.times do |rx|
                  px = dx + rx
                  next if px < 0 || px >= WIDTH
                  src_idx = (ry * dw + rx) * 4
                  dst_idx = (py * WIDTH + px) * CHANNELS
                  sa = resized[src_idx + 3].to_f / 255.0
                  next if sa <= 0
                  pixels[dst_idx] = (pixels[dst_idx] + (resized[src_idx].to_f - pixels[dst_idx]) * sa).to_u8
                  pixels[dst_idx + 1] = (pixels[dst_idx + 1] + (resized[src_idx + 1].to_f - pixels[dst_idx + 1]) * sa).to_u8
                  pixels[dst_idx + 2] = (pixels[dst_idx + 2] + (resized[src_idx + 2].to_f - pixels[dst_idx + 2]) * sa).to_u8
                  pixels[dst_idx + 3] = 255_u8
                end
              end
            ensure
              LibC.free(resized.as(Void*))
            end
          ensure
            LibStb.stbi_image_free(src_pixels.as(Void*))
          end
        end

        # Render style patterns onto pixel buffer
        private def self.render_pattern(pixels : UInt8*, style : String, accent : UInt32, opacity : Float64, scale : Float64)
          case style
          when "dots"
            spacing = Math.max((20 * scale).to_i, 2)
            radius = Math.max((3 * scale).to_i, 1)
            y = spacing // 2
            while y < HEIGHT
              x = spacing // 2
              while x < WIDTH
                draw_filled_circle(pixels, x, y, radius, accent, opacity)
                x += spacing
              end
              y += spacing
            end
          when "grid"
            spacing = Math.max((40 * scale).to_i, 4)
            # Horizontal lines
            y = 0
            while y < HEIGHT
              fill_rect_alpha(pixels, 0, y, WIDTH, 1, accent, opacity)
              y += spacing
            end
            # Vertical lines
            x = 0
            while x < WIDTH
              fill_rect_alpha(pixels, x, 0, 1, HEIGHT, accent, opacity)
              x += spacing
            end
          when "diagonal"
            spacing = Math.max((20 * scale).to_i, 4)
            step = 0
            while step < WIDTH + HEIGHT
              # Draw a 1px diagonal line
              px = 0
              while px < WIDTH && (step - px) >= 0
                py = step - px
                if py < HEIGHT
                  idx = (py * WIDTH + px) * CHANNELS
                  r = ((accent >> 16) & 0xFF).to_u8
                  g = ((accent >> 8) & 0xFF).to_u8
                  b = (accent & 0xFF).to_u8
                  alpha = opacity.clamp(0.0, 1.0)
                  dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
                  pixels[idx] = (dr + (r.to_f - dr) * alpha).to_u8
                  pixels[idx + 1] = (dg + (g.to_f - dg) * alpha).to_u8
                  pixels[idx + 2] = (db + (b.to_f - db) * alpha).to_u8
                end
                px += 1
              end
              step += spacing
            end
          when "gradient"
            r = ((accent >> 16) & 0xFF).to_f
            g = ((accent >> 8) & 0xFF).to_f
            b = (accent & 0xFF).to_f
            diagonal = Math.sqrt((WIDTH * WIDTH + HEIGHT * HEIGHT).to_f)
            HEIGHT.times do |py|
              WIDTH.times do |px|
                t = (px + py).to_f / diagonal
                alpha = opacity * (1.0 - t)
                next if alpha <= 0
                idx = (py * WIDTH + px) * CHANNELS
                dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
                pixels[idx] = (dr + (r - dr) * alpha).to_u8
                pixels[idx + 1] = (dg + (g - dg) * alpha).to_u8
                pixels[idx + 2] = (db + (b - db) * alpha).to_u8
              end
            end
          when "waves"
            amp = (20 * scale).to_i
            3.times do |i|
              y_center = HEIGHT // 3 + i * (80 * scale).to_i
              WIDTH.times do |px|
                # Simple sine wave approximation
                angle = px.to_f * Math::PI * 2 / 600.0
                py = y_center + (Math.sin(angle) * amp).to_i
                next if py < 0 || py >= HEIGHT
                # Draw 2px thick
                (-1..1).each do |dy|
                  ppy = py + dy
                  next if ppy < 0 || ppy >= HEIGHT
                  idx = (ppy * WIDTH + px) * CHANNELS
                  r = ((accent >> 16) & 0xFF).to_u8
                  g = ((accent >> 8) & 0xFF).to_u8
                  b = (accent & 0xFF).to_u8
                  alpha = opacity.clamp(0.0, 1.0)
                  dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
                  pixels[idx] = (dr + (r.to_f - dr) * alpha).to_u8
                  pixels[idx + 1] = (dg + (g.to_f - dg) * alpha).to_u8
                  pixels[idx + 2] = (db + (b.to_f - db) * alpha).to_u8
                end
              end
            end
          end
        end

        # Draw a filled circle with alpha blending
        private def self.draw_filled_circle(pixels : UInt8*, cx : Int32, cy : Int32, radius : Int32, color : UInt32, opacity : Float64)
          r = ((color >> 16) & 0xFF).to_u8
          g = ((color >> 8) & 0xFF).to_u8
          b = (color & 0xFF).to_u8
          alpha = opacity.clamp(0.0, 1.0)
          r2 = radius * radius

          (-radius..radius).each do |dy|
            py = cy + dy
            next if py < 0 || py >= HEIGHT
            (-radius..radius).each do |dx|
              next if dx * dx + dy * dy > r2
              px = cx + dx
              next if px < 0 || px >= WIDTH
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
              pixels[idx] = (dr + (r.to_f - dr) * alpha).to_u8
              pixels[idx + 1] = (dg + (g.to_f - dg) * alpha).to_u8
              pixels[idx + 2] = (db + (b.to_f - db) * alpha).to_u8
            end
          end
        end
      end
    end
  end
end
