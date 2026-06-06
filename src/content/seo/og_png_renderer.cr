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
          return unless File.exists?(path)

          src_w = uninitialized LibC::Int
          src_h = uninitialized LibC::Int
          channels = uninitialized LibC::Int
          src_pixels = LibStb.stbi_load(path, pointerof(src_w), pointerof(src_h), pointerof(channels), 4)
          return if src_pixels.null?

          begin
            return if src_w <= 0 || src_h <= 0

            buf_size = target_w.to_i64 * target_h.to_i64 * 4
            return if buf_size > 64_000_000_i64 * 4

            resized = LibC.malloc(buf_size).as(UInt8*)
            return if resized.null?

            result = LibStb.stbir_resize_uint8_linear(
              src_pixels, src_w, src_h, 0,
              resized, target_w, target_h, 0, 4
            )
            if result.null?
              LibC.free(resized.as(Void*))
              return
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

        # Simple memoization for expensive font loading (helps fast-start priority + deferred passes
        # and watch rebuilds during `hwaro serve`).
        @@cached_font_ctx : FontContext? = nil
        @@cached_font_key : String = ""

        # Last-built base layer + the key that produced it. This avoids re-doing
        # the heavy pixel work (fill + pattern + overlay) on the second fast-start
        # pass and on typical watch-triggered rebuilds.
        @@last_base_layer : Bytes? = nil
        @@last_base_key : String = ""

        # Initialize a single font from raw bytes. Returns {info, data} or nil.
        private def self.init_font(data : Bytes) : {LibStb::HwaroFontInfo, Bytes}?
          info = LibStb.hwaro_font_alloc
          return if info.null?
          if LibStb.hwaro_font_init(info, data, 0) != 0
            {info, data}
          else
            LibStb.hwaro_font_free(info)
            nil
          end
        end

        # Read a font file and initialize it. Returns {info, data} or nil.
        private def self.load_font_file(path : String) : {LibStb::HwaroFontInfo, Bytes}?
          return unless File.exists?(path)
          data = File.open(path, "rb", &.getb_to_end)
          init_font(data)
        end

        # Load fonts once, return a reusable context. Returns nil if no font found.
        # Priority: custom font_path > system fonts > bundled DejaVu Sans Bold.
        # Results are memoized so repeated calls (fast-start priority + deferred passes,
        # or watch rebuilds) do not re-scan the filesystem or re-parse TTF data.
        def self.load_fonts(custom_font_path : String? = nil) : FontContext?
          key = custom_font_path || "system"

          if @@cached_font_key == key && (cached = @@cached_font_ctx)
            return cached
          end

          ctx : FontContext? = nil

          # 1) Custom font path (user-specified via config)
          if cfp = custom_font_path
            abs = cfp.starts_with?("/") ? cfp : File.join(Dir.current, cfp)
            if result = load_font_file(abs)
              bold_info, bold_data = result
              ctx = FontContext.new(bold_data, bold_info)
            else
              Logger.warn "  Custom font '#{cfp}' not found or failed to load. Trying system fonts."
            end
          end

          # 2) System fonts
          if ctx.nil?
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
                ctx = FontContext.new(bold_data, bold_info, regular_data, regular_info)
              end
            end
          end

          # 3) Bundled fallback (DejaVu Sans Bold)
          if ctx.nil?
            if result = init_font(BUNDLED_FONT_BOLD.to_slice.dup)
              bold_info, bold_data = result
              ctx = FontContext.new(bold_data, bold_info)
            end
          end

          if ctx
            @@cached_font_ctx = ctx
            @@cached_font_key = key
          end
          ctx
        end

        # Pre-render the config-only layers (background fill, background
        # image + overlay, style pattern, top accent bar) into a reusable
        # RGBA buffer that can be memcpy'd into each per-page pixel
        # buffer. On large sites these layers account for the bulk of
        # the per-page cost — the "gradient" pattern alone touches every
        # one of the 756,000 pixels in Crystal-level math — so doing
        # them once per build instead of once per page is the largest
        # single win in PNG OG generation.
        #
        # Z-order is preserved: the original render order is bg → bg
        # image → pattern → top bar → text → logo → bottom bar, and the
        # remaining per-page work (text, logo, bottom bar) is layered
        # on top of this base in the same order.
        def self.build_base_layer(
          config : Models::Config,
          bg_image_path : String? = nil,
          cached_bg : CachedImage? = nil,
        ) : Bytes
          ai = config.og.auto_image

          # Build a cheap cache key from the things that affect the base pixels.
          # accent_bars gates the baked-in top accent bar, so it must be part of
          # the key — otherwise a serve-session toggle reuses a stale base layer.
          key = "#{ai.background}|#{ai.accent_color}|#{ai.secondary_color}|#{ai.style}|#{ai.pattern_opacity}|" \
                "#{ai.pattern_scale}|#{ai.overlay_opacity}|#{bg_image_path}|#{ai.logo_position}|#{ai.accent_bars}"

          if @@last_base_key == key && (cached = @@last_base_layer)
            return cached
          end

          bg_color = parse_hex_color(ai.background)
          accent_color = parse_hex_color(ai.accent_color)
          secondary_color = parse_hex_color(OgImage.resolve_secondary(ai))

          # Minimal / modern / geometric styles drop the classic accent bars.
          show_accent_bars = ai.accent_bars && !OgImage.no_accent_bars?(ai.style)

          base = Bytes.new(WIDTH * HEIGHT * CHANNELS)
          pixels = base.to_unsafe

          fill_rect(pixels, 0, 0, WIDTH, HEIGHT, bg_color)

          if bg_image_path
            if cbg = cached_bg
              blit_cached_image(pixels, cbg, 0, 0)
            else
              composite_image(pixels, bg_image_path, 0, 0, WIDTH, HEIGHT)
            end
            fill_rect_alpha(pixels, 0, 0, WIDTH, HEIGHT, bg_color, ai.overlay_opacity)
          end

          render_pattern(pixels, ai.style, accent_color, ai.pattern_opacity, ai.pattern_scale)

          # Per-style signature decoration (color blocks, gradient, glow, frame)
          render_style_decoration(pixels, ai.style, bg_color, accent_color, secondary_color, !bg_image_path.nil?)

          if show_accent_bars
            fill_rect(pixels, 0, 0, WIDTH, 6, accent_color)
          end

          @@last_base_layer = base
          @@last_base_key = key
          base
        end

        # Render OG image directly to PNG file. Returns true on success.
        # Accepts optional pre-loaded CachedImage for logo/background to avoid
        # repeated decode+resize when generating many pages.
        #
        # When `base_layer` is given, the config-only layers (background,
        # pattern, top accent bar) are memcpy'd from it instead of being
        # re-rendered per page. Callers that render many pages should
        # build the base layer once via `build_base_layer` and pass it
        # in here.
        def self.render_png(
          page : Models::Page,
          config : Models::Config,
          png_path : String,
          logo_image_path : String? = nil,
          bg_image_path : String? = nil,
          font_ctx : FontContext? = nil,
          cached_logo : CachedImage? = nil,
          cached_bg : CachedImage? = nil,
          base_layer : Bytes? = nil,
        ) : Bool
          ai = config.og.auto_image

          # Minimal / modern / geometric styles drop the classic accent bars.
          show_accent_bars = ai.accent_bars && !OgImage.no_accent_bars?(ai.style)

          # Parse colors
          bg_color = parse_hex_color(ai.background)
          text_color = parse_hex_color(ai.text_color)
          accent_color = parse_hex_color(ai.accent_color)
          secondary_color = parse_hex_color(OgImage.resolve_secondary(ai))

          # Allocate pixel buffer (RGBA) with LibC.malloc for explicit lifecycle control.
          buf_size = WIDTH * HEIGHT * CHANNELS
          pixels = LibC.malloc(buf_size).as(UInt8*)
          return false if pixels.null?

          begin
            if base = base_layer
              # Fast path: the config-only layers (steps 1–4) are
              # already baked into `base`; memcpy them in.
              base.to_unsafe.copy_to(pixels, base.size)
            else
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

              # 3b. Per-style signature decoration (color blocks, gradient, glow, frame)
              render_style_decoration(pixels, ai.style, bg_color, accent_color, secondary_color, !bg_image_path.nil?)

              # 4. Accent bar at top (legacy / classic look)
              if show_accent_bars
                fill_rect(pixels, 0, 0, WIDTH, 6, accent_color)
              end
            end

            # 5. Render text
            if ctx = font_ctx
              render_text_content(pixels, page, config, ctx, text_color, accent_color, bg_color)
            end

            # 6. Logo image
            if logo_image_path
              logo_x, logo_y = OgImage.logo_coordinates(ai.logo_position)
              if clogo = cached_logo
                blit_cached_image(pixels, clogo, logo_x, logo_y)
              else
                composite_image(pixels, logo_image_path, logo_x, logo_y, OgImage::LOGO_SIZE, OgImage::LOGO_SIZE)
              end
            end

            # 7. Bottom accent bar (legacy / classic look)
            if show_accent_bars
              fill_rect(pixels, 0, HEIGHT - 6, WIDTH, 6, accent_color)
            end

            # Write PNG
            Hwaro::Utils::FileSafe.mkdir_p(File.dirname(png_path))
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
          bg_color : UInt32,
        )
          ai = config.og.auto_image
          font_size = Math.max(ai.font_size, 1).to_f32

          # Ambitious + geometric styles get much bolder default typography
          case ai.style
          when "hero", "monument", "brutalist"
            if ai.font_size <= 48
              font_size = 78.0
            end
          when "artistic", "surreal"
            if ai.font_size <= 48
              font_size = 64.0
            end
          when "band"
            if ai.font_size <= 48
              font_size = 60.0
            end
          when "split"
            if ai.font_size <= 48
              font_size = 58.0
            end
          end
          desc_size = Math.max((font_size * 0.38).to_i, 1).to_f32 # smaller desc ratio for ambitious styles

          bold_info = ctx.bold_info
          bold_scale = LibStb.hwaro_font_scale_for_pixel_height(bold_info, font_size)

          # Use regular font if available, otherwise fall back to bold
          r_info = ctx.regular_info || bold_info
          r_scale = LibStb.hwaro_font_scale_for_pixel_height(r_info, desc_size)

          # Word-wrap width and margins — modern + geometric styles get tailored treatment
          margin_x = case ai.style
                     when "editorial", "framed"                     then 110
                     when "artistic", "hero", "surreal", "monument" then 140
                     when "split"                                   then OgImage::SPLIT_TEXT_X
                     when "brutalist"                               then OgImage::BRUTALIST_TEXT_X
                     else                                                80
                     end
          wrap_width = case ai.style
                       when "split"     then WIDTH - OgImage::SPLIT_TEXT_X - 80
                       when "brutalist" then WIDTH - OgImage::BRUTALIST_TEXT_X - (OgImage::BRUTALIST_INSET + OgImage::BRUTALIST_FRAME + 40)
                       else                  WIDTH - (margin_x * 2)
                       end

          title_lines = word_wrap_measured(bold_info, bold_scale, page.title, wrap_width)
          # The band style draws the title inside a fixed-height color band;
          # cap the lines so a long title can't overflow the band invisibly.
          title_lines = OgImage.cap_band_title(title_lines, font_size.to_i) if ai.style == "band"
          desc_text = page.description || ""
          desc_lines = desc_text.empty? ? [] of String : word_wrap_measured(r_info, r_scale, desc_text, wrap_width)

          # Vertical positioning — ambitious styles get very bold, confident, centered placement
          title_block_height = title_lines.size * (font_size + 8)
          desc_block_height = desc_lines.empty? ? 0 : desc_lines.size * (desc_size + 6)
          total_text_height = title_block_height + desc_block_height + 20

          case ai.style
          when "editorial", "framed"
            title_start_y = Math.max(font_size + 32, ((HEIGHT - total_text_height) / 2).to_f32 + font_size - 12)
          when "artistic", "surreal"
            title_start_y = Math.max(font_size + 48, ((HEIGHT - total_text_height) / 2).to_f32 + font_size - 28)
          when "hero"
            # Hero: Title dominates, pushed higher for impact
            title_start_y = Math.max(font_size + 20, 180_f32)
          when "monument"
            # Monument: Extremely dominant title with massive breathing room
            title_start_y = Math.max(font_size + 10, 120_f32)
          when "band"
            # Band: vertically centered inside the color band.
            band_center = (OgImage::BAND_TOP + OgImage::BAND_HEIGHT // 2).to_f32
            title_start_y = band_center - (title_block_height / 2) + font_size - 6
          when "brutalist"
            # Brutalist: large title anchored near the top of the framed panel.
            title_start_y = (OgImage::BRUTALIST_INSET + OgImage::BRUTALIST_FRAME + 100).to_f32
          when "split"
            title_start_y = Math.max(font_size + 40, ((HEIGHT - total_text_height) / 2).to_f32 + font_size - 10)
          else
            title_start_y = Math.max(font_size + 20, ((HEIGHT - total_text_height) / 2).to_f32 + font_size)
          end

          # Optional semi-transparent panel behind text for better integration
          # with artistic/complex backgrounds (modern editorial style).
          panel = ai.text_panel
          # Auto panel: strong over a user-supplied photo (for legibility),
          # but light or none over our generated backgrounds so each style's
          # signature reads clearly.
          if panel < 0.01
            has_bg = !((bgi = ai.background_image).nil? || bgi.empty?)
            case ai.style
            when "artistic"  then panel = has_bg ? 0.78 : 0.26
            when "surreal"   then panel = has_bg ? 0.80 : 0.34
            when "hero"      then panel = has_bg ? 0.65 : 0.30
            when "framed"    then panel = has_bg ? 0.55 : 0.0
            when "editorial" then panel = has_bg ? 0.34 : 0.0
            when "monument"  then panel = has_bg ? 0.60 : 0.0
            end
          end

          # Geometric styles are intentionally flat — they never use the soft panel.
          if panel > 0.01 && !OgImage.geometric?(ai.style)
            top_offset : Float32 = ai.style == "framed" ? 48_f32 : 36_f32
            bottom_offset : Float32 = ai.style == "framed" ? 52_f32 : 40_f32
            panel_top = (title_start_y - font_size - top_offset).to_f32.clamp(16_f32, HEIGHT * 0.52_f32)
            panel_bottom = (title_start_y + total_text_height + bottom_offset).to_f32.clamp(panel_top + 90, HEIGHT - 60_f32)
            draw_text_panel(pixels, panel_top, panel_bottom, panel, bg_color, accent_color)
          end

          # Render title lines. `band` knocks the title out of the color band
          # using the background color for strong magazine-cover contrast.
          title_color = ai.style == "band" ? bg_color : text_color
          title_lines.each_with_index do |line, i|
            y = title_start_y + i * (font_size + 8)
            LibStb.hwaro_font_render_text(bold_info, pixels, WIDTH, HEIGHT, margin_x.to_f32, y - font_size, bold_scale, line, title_color, 1.0_f32)
          end

          # Editorial: thin vertical accent rule to the left of the title.
          if ai.style == "editorial"
            rule_x = margin_x - 28
            rule_top = (title_start_y - font_size).to_i.clamp(0, HEIGHT)
            rule_h = title_block_height.to_i
            fill_rect(pixels, rule_x, rule_top, 6, rule_h, accent_color) if rule_x >= 0
          end

          # Monument: a single long thin rule under the title.
          if ai.style == "monument"
            rule_y = (title_start_y + (title_lines.size - 1) * (font_size + 8) + 30).to_i.clamp(0, HEIGHT - 5)
            fill_rect(pixels, margin_x, rule_y, 220, 5, accent_color)
          end

          # Render description — hero and monument get very small or minimal desc treatment
          unless desc_lines.empty?
            desc_start_y = ai.style == "band" ? (OgImage::BAND_TOP + OgImage::BAND_HEIGHT + 24).to_f32 + desc_size : title_start_y + title_block_height + 16

            # For hero/monument, make description much more subtle
            desc_opacity = if ai.style == "hero" || ai.style == "monument"
                             0.45_f32
                           else
                             0.75_f32
                           end

            desc_lines.each_with_index do |line, i|
              y = desc_start_y + i * (desc_size + 6)
              LibStb.hwaro_font_render_text(r_info, pixels, WIDTH, HEIGHT, margin_x.to_f32, y - desc_size, r_scale, line, text_color, desc_opacity)
            end
          end

          # Site name — hide or minimize for the most ambitious styles
          if ai.show_title
            if ai.style == "hero" || ai.style == "monument"
              # Very small and subtle for hero/monument
              site_scale = LibStb.hwaro_font_scale_for_pixel_height(bold_info, 18_f32)
              site_margin = 140_f32
              site_x = (ai.logo && ai.logo_position == "bottom-left") ? (site_margin + OgImage::LOGO_SIZE + OgImage::LOGO_TEXT_GAP).to_f32 : site_margin
              LibStb.hwaro_font_render_text(bold_info, pixels, WIDTH, HEIGHT, site_x, (HEIGHT - 55 - 18).to_f32, site_scale, config.title, accent_color, 0.6_f32)
            else
              site_scale = LibStb.hwaro_font_scale_for_pixel_height(bold_info, 22_f32)
              site_margin = case ai.style
                            when "editorial", "framed" then 110
                            when "artistic", "surreal" then 140
                            when "split"               then 80
                            when "brutalist"           then OgImage::BRUTALIST_TEXT_X
                            else                            OgImage::LOGO_MARGIN
                            end
              site_x = (ai.logo && ai.logo_position == "bottom-left") ? (site_margin + OgImage::LOGO_SIZE + OgImage::LOGO_TEXT_GAP).to_f32 : site_margin.to_f32
              # `split` renders the site name inside the accent block → readable color.
              site_color = ai.style == "split" ? text_color : accent_color
              LibStb.hwaro_font_render_text(bold_info, pixels, WIDTH, HEIGHT, site_x, (HEIGHT - 65 - 22).to_f32, site_scale, config.title, site_color, 1.0_f32)
            end
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

        # Parse "#RRGGBB" to 0xRRGGBB. Also accepts "#rgb" shorthand and
        # "#rrggbbaa" (alpha dropped); falls back to black for invalid input.
        def self.parse_hex_color(hex : String) : UInt32
          if normalized = OgImage.normalize_hex(hex)
            normalized.to_u32(16)
          else
            0x000000_u32
          end
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

        # Draw a soft, premium vertical gradient panel behind the text area.
        # For "framed" style this acts more like a distinct content card.
        private def self.draw_text_panel(pixels : UInt8*, top : Float32, bottom : Float32, strength : Float64, bg_color : UInt32, accent : UInt32 = 0)
          return if strength <= 0.01

          r = ((bg_color >> 16) & 0xFF).to_i
          g = ((bg_color >> 8) & 0xFF).to_i
          b = (bg_color & 0xFF).to_i

          # For strong modern styles (framed/artistic), we tint toward accent color
          # instead of pure darkening — this creates more visible, premium card/frame effect
          if strength > 0.55
            # Mix background with accent for a tinted card look
            ar = ((accent >> 16) & 0xFF).to_i
            ag = ((accent >> 8) & 0xFF).to_i
            ab = (accent & 0xFF).to_i

            mix = 0.18 # how much accent tint
            panel_r = ((r * (1 - mix) + ar * mix)).to_u8
            panel_g = ((g * (1 - mix) + ag * mix)).to_u8
            panel_b = ((b * (1 - mix) + ab * mix)).to_u8

            alpha_base = (strength * 0.55).clamp(0.0, 0.65)
          else
            darken_factor = 0.40
            panel_r = (r * darken_factor).to_u8
            panel_g = (g * darken_factor).to_u8
            panel_b = (b * darken_factor).to_u8
            alpha_base = (strength * 0.70).clamp(0.0, 0.70)
          end

          top_i = top.to_i.clamp(0, HEIGHT)
          bottom_i = bottom.to_i.clamp(0, HEIGHT)

          (top_i...bottom_i).each do |py|
            t = (py - top_i).to_f / [(bottom_i - top_i), 1].max

            # More sophisticated fade:
            # - Stronger near the title (top)
            # - Very gentle falloff toward description
            # - Slight extra softness at the very edges for modern feel
            fade = if t < 0.15
                     1.0 - (t * 1.8) # stronger near title
                   elsif t < 0.65
                     0.73 - (t - 0.15) * 0.9 # main body
                   else
                     0.28 * (1.0 - (t - 0.65) / 0.35) # soft tail
                   end

            alpha = (alpha_base * fade).clamp(0.0, 0.72)

            # Subtle horizontal vignette on the sides for depth
            WIDTH.times do |px|
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]
              dg = pixels[idx + 1]
              db = pixels[idx + 2]

              # Very gentle side softening
              side_t = (px.to_f / WIDTH - 0.5).abs * 0.6
              side_alpha = alpha * (1.0 - side_t * 0.25)

              pixels[idx] = (dr + (panel_r.to_f - dr) * side_alpha).to_u8
              pixels[idx + 1] = (dg + (panel_g.to_f - dg) * side_alpha).to_u8
              pixels[idx + 2] = (db + (panel_b.to_f - db) * side_alpha).to_u8
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
              ix = 0
              while ix < WIDTH && (step - ix) >= 0
                iy = step - ix
                if iy < HEIGHT
                  idx = (iy * WIDTH + ix) * CHANNELS
                  r = ((accent >> 16) & 0xFF).to_u8
                  g = ((accent >> 8) & 0xFF).to_u8
                  b = (accent & 0xFF).to_u8
                  alpha = opacity.clamp(0.0, 1.0)
                  dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
                  pixels[idx] = (dr + (r.to_f - dr) * alpha).to_u8
                  pixels[idx + 1] = (dg + (g.to_f - dg) * alpha).to_u8
                  pixels[idx + 2] = (db + (b.to_f - db) * alpha).to_u8
                end
                ix += 1
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

        # Paint each style's signature background decoration into the
        # config-only base layer (so it costs nothing per page):
        #   - geometric color blocks (split / band / brutalist)
        #   - generated backgrounds for the modern styles when no background
        #     image is configured (gradient / glow / frame)
        # `has_bg_image` suppresses the generated modern backgrounds so a
        # user-supplied photo shows through untouched.
        private def self.render_style_decoration(pixels : UInt8*, style : String, bg : UInt32, accent : UInt32, secondary : UInt32, has_bg_image : Bool)
          case style
          when "split"
            # Secondary strip first (wider), then the accent block on top —
            # leaving a two-tone diagonal seam between them.
            fill_left_diagonal(pixels, secondary, OgImage::SPLIT_TOP_X + OgImage::SPLIT_EDGE, OgImage::SPLIT_BOTTOM_X + OgImage::SPLIT_EDGE)
            fill_left_diagonal(pixels, accent, OgImage::SPLIT_TOP_X, OgImage::SPLIT_BOTTOM_X)
          when "band"
            fill_rect(pixels, 0, OgImage::BAND_TOP, WIDTH, OgImage::BAND_HEIGHT, accent)
          when "brutalist"
            inset = OgImage::BRUTALIST_INSET
            offset = OgImage::BRUTALIST_OFFSET
            frame = OgImage::BRUTALIST_FRAME
            iw = WIDTH - 2 * inset
            ih = HEIGHT - 2 * inset
            # Hard offset shadow block (secondary), peeking down-right.
            fill_rect(pixels, inset + offset, inset + offset, iw, ih, secondary)
            # Main panel (background color) covers the shadow's top-left.
            fill_rect(pixels, inset, inset, iw, ih, bg)
            # Thick accent border around the panel.
            draw_border(pixels, inset, inset, iw, ih, frame, accent)
          when "artistic"
            # Vivid two-color diagonal gradient as a self-contained backdrop.
            fill_linear_gradient(pixels, accent, secondary) unless has_bg_image
          when "hero"
            # Single dramatic spotlight glow behind the title.
            draw_radial_glow(pixels, WIDTH // 2, 230, 640, accent, 0.55) unless has_bg_image
          when "surreal"
            # Aurora: several soft overlapping orbs in accent + secondary.
            unless has_bg_image
              draw_radial_glow(pixels, 300, 200, 470, accent, 0.50)
              draw_radial_glow(pixels, 950, 380, 540, secondary, 0.45)
              draw_radial_glow(pixels, 640, 560, 420, accent, 0.30)
            end
          when "framed"
            # Elegant thin frame inset from the edges.
            fi = OgImage::FRAMED_INSET
            draw_border(pixels, fi, fi, WIDTH - 2 * fi, HEIGHT - 2 * fi, OgImage::FRAMED_WIDTH, accent)
          end
        end

        # Fill every pixel to the left of a diagonal edge that runs from
        # `top_x` (at y=0) to `bottom_x` (at y=HEIGHT). Opaque fill.
        private def self.fill_left_diagonal(pixels : UInt8*, color : UInt32, top_x : Int32, bottom_x : Int32)
          r = ((color >> 16) & 0xFF).to_u8
          g = ((color >> 8) & 0xFF).to_u8
          b = (color & 0xFF).to_u8

          HEIGHT.times do |py|
            edge = top_x + ((bottom_x - top_x) * py) // HEIGHT
            edge = 0 if edge < 0
            edge = WIDTH if edge > WIDTH
            px = 0
            while px < edge
              idx = (py * WIDTH + px) * CHANNELS
              pixels[idx] = r
              pixels[idx + 1] = g
              pixels[idx + 2] = b
              pixels[idx + 3] = 255_u8
              px += 1
            end
          end
        end

        # Draw a solid rectangular border of `thickness` px inside (x, y, w, h).
        private def self.draw_border(pixels : UInt8*, x : Int32, y : Int32, w : Int32, h : Int32, thickness : Int32, color : UInt32)
          fill_rect(pixels, x, y, w, thickness, color)                 # top
          fill_rect(pixels, x, y + h - thickness, w, thickness, color) # bottom
          fill_rect(pixels, x, y, thickness, h, color)                 # left
          fill_rect(pixels, x + w - thickness, y, thickness, h, color) # right
        end

        # Linearly interpolate between two packed RGB colors.
        private def self.lerp_color(c1 : UInt32, c2 : UInt32, t : Float64) : UInt32
          t = t.clamp(0.0, 1.0)
          r1 = ((c1 >> 16) & 0xFF).to_f; g1 = ((c1 >> 8) & 0xFF).to_f; b1 = (c1 & 0xFF).to_f
          r2 = ((c2 >> 16) & 0xFF).to_f; g2 = ((c2 >> 8) & 0xFF).to_f; b2 = (c2 & 0xFF).to_f
          r = (r1 + (r2 - r1) * t).round.to_u32
          g = (g1 + (g2 - g1) * t).round.to_u32
          b = (b1 + (b2 - b1) * t).round.to_u32
          (r << 16) | (g << 8) | b
        end

        # Fill the whole canvas with a diagonal (top-left → bottom-right)
        # two-color gradient. Opaque.
        private def self.fill_linear_gradient(pixels : UInt8*, c1 : UInt32, c2 : UInt32)
          HEIGHT.times do |py|
            ty = py.to_f / HEIGHT
            WIDTH.times do |px|
              t = (px.to_f / WIDTH + ty) * 0.5
              c = lerp_color(c1, c2, t)
              idx = (py * WIDTH + px) * CHANNELS
              pixels[idx] = ((c >> 16) & 0xFF).to_u8
              pixels[idx + 1] = ((c >> 8) & 0xFF).to_u8
              pixels[idx + 2] = (c & 0xFF).to_u8
              pixels[idx + 3] = 255_u8
            end
          end
        end

        # Blend a soft radial glow (orb of `color`) over the existing pixels,
        # fading out quadratically to the edge of `radius`.
        private def self.draw_radial_glow(pixels : UInt8*, cx : Int32, cy : Int32, radius : Int32, color : UInt32, intensity : Float64)
          return if radius <= 0
          cr = ((color >> 16) & 0xFF).to_f
          cg = ((color >> 8) & 0xFF).to_f
          cb = (color & 0xFF).to_f
          rad = radius.to_f
          r2 = rad * rad

          y0 = Math.max(cy - radius, 0)
          y1 = Math.min(cy + radius, HEIGHT)
          x0 = Math.max(cx - radius, 0)
          x1 = Math.min(cx + radius, WIDTH)

          (y0...y1).each do |py|
            dy = (py - cy).to_f
            (x0...x1).each do |px|
              dx = (px - cx).to_f
              d2 = dx * dx + dy * dy
              next if d2 > r2
              f = 1.0 - Math.sqrt(d2) / rad
              a = intensity * f * f
              next if a <= 0.0
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
              pixels[idx] = (dr + (cr - dr) * a).to_u8
              pixels[idx + 1] = (dg + (cg - dg) * a).to_u8
              pixels[idx + 2] = (db + (cb - db) * a).to_u8
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
