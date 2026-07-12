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

        # Bundled DejaVu Sans Bold font (compiled into the binary as the
        # wide-coverage Latin/Cyrillic/Greek fallback at the end of every
        # font chain).
        BUNDLED_FONT_BOLD = {{ read_file("#{__DIR__}/../../ext/fonts/DejaVuSans-Bold.ttf") }}

        # Bundled brand fonts (OFL 1.1 — license texts live next to the
        # TTFs). Space Grotesk carries titles and descriptions; JetBrains
        # Mono carries the `terminal` style. Static instances, not variable
        # fonts — stb_truetype ignores variation axes.
        BUNDLED_FONT_DISPLAY = {{ read_file("#{__DIR__}/../../ext/fonts/SpaceGrotesk-Bold.ttf") }}
        BUNDLED_FONT_TEXT    = {{ read_file("#{__DIR__}/../../ext/fonts/SpaceGrotesk-Medium.ttf") }}
        BUNDLED_FONT_MONO    = {{ read_file("#{__DIR__}/../../ext/fonts/JetBrainsMono-Bold.ttf") }}

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

        # CJK-capable system fonts. A title/description containing Hangul, kana,
        # or Han ideographs renders as blank "tofu" boxes in the Latin-only
        # fonts above; these cover CJK *and* Latin, so swapping the whole font
        # to one of these renders mixed "Noir v1.0 — 한국어" lines correctly.
        # Ordered by coverage breadth, then likelihood of being installed.
        CJK_FONT_SEARCH_PATHS = [
          # macOS
          "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
          "/Library/Fonts/Arial Unicode.ttf",
          "/System/Library/Fonts/AppleSDGothicNeo.ttc",
          "/System/Library/Fonts/PingFang.ttc",
          "/System/Library/Fonts/Hiragino Sans GB.ttc",
          # Linux (Noto CJK — common package layouts)
          "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
          "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
          "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
          "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
          "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
          "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc",
        ]

        # First installed CJK-capable font, or nil if none is available.
        def self.find_cjk_font : String?
          CJK_FONT_SEARCH_PATHS.find { |path| File.exists?(path) }
        end

        # True if the font defines a glyph for `codepoint` (delegates to stb's
        # glyph lookup). Used to verify CJK coverage.
        def self.font_has_glyph?(info : LibStb::HwaroFontInfo, codepoint : Int32) : Bool
          LibStb.hwaro_font_has_glyph(info, codepoint) != 0
        end

        # Drop codepoints `info` has no glyph for. stb draws missing glyphs
        # as blank "tofu" boxes — emoji are the common case, since color
        # emoji fonts can't be loaded here — so degrade "🔥 Title" to
        # "Title" instead of "☐ Title". Whitespace always passes; leftover
        # double spaces from removed runs are collapsed. Returns the
        # original string untouched when everything is drawable.
        def self.drop_missing_glyphs(info : LibStb::HwaroFontInfo, text : String) : String
          return text if text.empty?
          filtered = text.chars.select { |c| c.whitespace? || font_has_glyph?(info, c.ord) }.join
          return text if filtered.size == text.size
          filtered.gsub(/\s{2,}/, " ").strip
        end

        # Chain variant: drop a codepoint only when *no* font in the chain
        # covers it.
        def self.drop_missing_glyphs(chain : Array(FontEntry), text : String) : String
          return text if text.empty?
          filtered = text.chars.select { |c| c.whitespace? || chain_font_index(chain, c.ord) }.join
          return text if filtered.size == text.size
          filtered.gsub(/\s{2,}/, " ").strip
        end

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

        # One loaded font: the opaque stbtt_fontinfo pointer plus the raw
        # TTF bytes it points into (the bytes must stay alive as long as
        # the info is in use).
        alias FontEntry = {LibStb::HwaroFontInfo, Bytes}

        # Pre-loaded font context for reuse across multiple render calls.
        # Holds one fallback *chain* per typographic role — brand font
        # first, then (when the content needs it) a CJK-capable system
        # font, then the wide-coverage bundled DejaVu. Text is rendered
        # run-by-run using the first chain font that covers each glyph.
        # The same underlying font may appear in several chains; finalize
        # frees each unique font exactly once.
        class FontContext
          getter display : Array(FontEntry) # titles, eyebrows, site name
          getter text : Array(FontEntry)    # descriptions
          getter mono : Array(FontEntry)    # `terminal` style

          def initialize(@display, @text, @mono)
          end

          # True when any font in any chain covers `codepoint`.
          def covers?(codepoint : Int32) : Bool
            {@display, @text, @mono}.any? do |chain|
              chain.any? { |info, _| LibStb.hwaro_font_has_glyph(info, codepoint) != 0 }
            end
          end

          def finalize
            freed = Set(UInt64).new
            {@display, @text, @mono}.each do |chain|
              chain.each do |info, _|
                next if info.null?
                next unless freed.add?(info.address)
                LibStb.hwaro_font_free(info)
              end
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

        # Load fonts once, return a reusable context of per-role fallback
        # chains. Priority within every chain:
        #   user font_path → bundled brand font (Space Grotesk / JetBrains
        #   Mono) → CJK-capable system font when the content needs it →
        #   bundled DejaVu Sans Bold (wide coverage).
        # A user font no longer *replaces* everything — it merely leads the
        # chain, so glyphs it lacks still fall back to the bundled fonts.
        # Results are memoized so repeated calls (fast-start priority +
        # deferred passes, or watch rebuilds) do not re-scan the filesystem
        # or re-parse TTF data.
        def self.load_fonts(custom_font_path : String? = nil, prefer_cjk : Bool = false) : FontContext?
          key = "#{custom_font_path}|#{prefer_cjk}"

          if @@cached_font_key == key && (cached = @@cached_font_ctx)
            return cached
          end

          # Chain head: a user-specified font overrides the brand fonts in
          # every role (it may be a CJK font — that's the documented use).
          custom : FontEntry? = nil
          if cfp = custom_font_path
            abs = cfp.starts_with?("/") ? cfp : File.join(Dir.current, cfp)
            custom = load_font_file(abs)
            unless custom
              Logger.warn "  Custom font '#{cfp}' not found or failed to load. Using bundled fonts."
            end
          end

          # Shared chain tail: CJK coverage (when needed), then DejaVu.
          tail = [] of FontEntry
          if prefer_cjk && (cjk_path = find_cjk_font)
            if cjk = load_font_file(cjk_path)
              tail << cjk
            end
          end
          if dejavu = init_font(BUNDLED_FONT_BOLD.to_slice.dup)
            tail << dejavu
          end

          display = [] of FontEntry
          text = [] of FontEntry
          mono = [] of FontEntry
          if c = custom
            display << c
            text << c
            mono << c
          end
          if d = init_font(BUNDLED_FONT_DISPLAY.to_slice.dup)
            display << d
          end
          if t = init_font(BUNDLED_FONT_TEXT.to_slice.dup)
            text << t
          end
          if m = init_font(BUNDLED_FONT_MONO.to_slice.dup)
            mono << m
          end
          display.concat(tail)
          text.concat(tail)
          mono.concat(tail)

          # Last-ditch: if even the bundled fonts failed to parse, fall
          # back to any system font so PNG output stays possible.
          if display.empty?
            if (path = find_system_font(bold: true)) && (sys = load_font_file(path))
              display << sys
            end
          end
          return if display.empty?
          text = display if text.empty?
          mono = display if mono.empty?

          ctx = FontContext.new(display, text, mono)
          @@cached_font_ctx = ctx
          @@cached_font_key = key
          ctx
        end

        # --- Font-chain rendering helpers ---

        # Index of the first font in `chain` that has a glyph for
        # `codepoint`, or nil when none covers it.
        protected def self.chain_font_index(chain : Array(FontEntry), codepoint : Int32) : Int32?
          chain.each_with_index do |(info, _), i|
            return i if LibStb.hwaro_font_has_glyph(info, codepoint) != 0
          end
          nil
        end

        # Split `text` into runs of consecutive characters drawable by the
        # same (first-covering) chain font. Whitespace sticks to the current
        # run so spaces never force a font switch. Characters covered by no
        # font are skipped (drop_missing_glyphs upstream makes this a no-op
        # in practice).
        private def self.chain_split_runs(chain : Array(FontEntry), text : String) : Array({Int32, String})
          runs = [] of {Int32, String}
          current = -1
          buf = IO::Memory.new
          text.each_char do |ch|
            idx = if ch.whitespace? && current >= 0
                    current
                  else
                    chain_font_index(chain, ch.ord)
                  end
            next unless idx
            if idx != current && buf.size > 0
              runs << {current, buf.to_s}
              buf = IO::Memory.new
            end
            current = idx
            buf << ch
          end
          runs << {current, buf.to_s} if buf.size > 0 && current >= 0
          runs
        end

        # Per-font {scale, y-offset} so different chain fonts share one
        # baseline: the chain's primary font defines the baseline for the
        # requested pixel height; every other font is shifted so its own
        # ascent lands on that same baseline.
        private def self.chain_metrics(chain : Array(FontEntry), px_size : Float32) : Array({Float32, Float32})
          primary_scale = LibStb.hwaro_font_scale_for_pixel_height(chain.first[0], px_size)
          pa = 0; pd = 0; pg = 0
          LibStb.hwaro_font_get_vmetrics(chain.first[0], pointerof(pa), pointerof(pd), pointerof(pg))
          baseline = primary_scale * pa
          chain.map do |(info, _)|
            scale = LibStb.hwaro_font_scale_for_pixel_height(info, px_size)
            a = 0; d = 0; g = 0
            LibStb.hwaro_font_get_vmetrics(info, pointerof(a), pointerof(d), pointerof(g))
            {scale, baseline - scale * a}
          end
        end

        # Measure `text` at `px_size` across the chain. `tracking` adds a
        # fixed per-character advance (used for eyebrow/brand labels).
        def self.chain_measure(chain : Array(FontEntry), px_size : Float32, text : String, tracking : Float32 = 0_f32) : Float32
          return 0_f32 if text.empty? || chain.empty?
          metrics = chain_metrics(chain, px_size)
          width = 0_f32
          drawn = 0
          chain_split_runs(chain, text).each do |idx, run|
            info = chain[idx][0]
            scale = metrics[idx][0]
            if tracking.zero?
              width += LibStb.hwaro_font_measure_text(info, run, scale)
            else
              run.each_char do |ch|
                width += LibStb.hwaro_font_measure_text(info, ch.to_s, scale) + tracking
                drawn += 1
              end
            end
          end
          width -= tracking if !tracking.zero? && drawn > 0
          width
        end

        # Render `text` at `px_size` with per-glyph font fallback. `y_top`
        # is the top of the text box (same convention as
        # hwaro_font_render_text: baseline = y_top + scale * ascent).
        # Returns the final x position.
        def self.chain_render(chain : Array(FontEntry), pixels : UInt8*, x : Float32, y_top : Float32, px_size : Float32, text : String, color : UInt32, opacity : Float32, tracking : Float32 = 0_f32) : Float32
          return x if text.empty? || chain.empty?
          metrics = chain_metrics(chain, px_size)
          cursor = x
          chain_split_runs(chain, text).each do |idx, run|
            info = chain[idx][0]
            scale, y_off = metrics[idx]
            if tracking.zero?
              cursor = LibStb.hwaro_font_render_text(info, pixels, WIDTH, HEIGHT, cursor, y_top + y_off, scale, run, color, opacity)
            else
              run.each_char do |ch|
                cursor = LibStb.hwaro_font_render_text(info, pixels, WIDTH, HEIGHT, cursor, y_top + y_off, scale, ch.to_s, color, opacity)
                cursor += tracking
              end
            end
          end
          cursor
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
          style = ai.style
          font_size = Math.max(ai.font_size, 1).to_f32

          # Style-tuned default type scale unless the user raised it explicitly.
          if ai.font_size <= 48
            font_size = case style
                        when "monument"          then 84.0_f32
                        when "hero", "brutalist" then 78.0_f32
                        when "artistic", "surreal", "bauhaus", "halftone", "minimal"
                          64.0_f32
                        when "band"     then 60.0_f32
                        when "split"    then 58.0_f32
                        when "terminal" then 54.0_f32
                        else                 56.0_f32
                        end
          end
          desc_size = Math.max((font_size * OgImage::DESC_RATIO).to_i, 1).to_f32

          # `terminal` is a full monospace composition; everything else sets
          # titles in the display face and descriptions in the text face.
          title_chain = style == "terminal" ? ctx.mono : ctx.display
          desc_chain = style == "terminal" ? ctx.mono : ctx.text
          brand_chain = style == "terminal" ? ctx.mono : ctx.display

          title_line_h = (font_size * OgImage::TITLE_LINE_H).to_f32
          desc_line_h = (desc_size * OgImage::DESC_LINE_H).to_f32

          # `terminal` prefixes the title with an accent "$" prompt; the title
          # block shifts right by this advance on every line.
          prompt_advance = 0_f32
          if style == "terminal"
            prompt_advance = chain_measure(ctx.mono, font_size, "$") + font_size * 0.4_f32
          end

          # Word-wrap width and margins — modern + geometric styles get tailored treatment
          margin_x = case style
                     when "artistic", "hero", "surreal" then 140
                     when "split"                       then OgImage::SPLIT_TEXT_X
                     when "brutalist"                   then OgImage::BRUTALIST_TEXT_X
                     when "terminal"                    then OgImage::TERMINAL_TEXT_X
                     when "bauhaus"                     then OgImage::BAUHAUS_TEXT_X
                     when "halftone"                    then OgImage::HALFTONE_TEXT_X
                     else                                    OgImage::MARGIN_X
                     end
          wrap_width = case style
                       when "split"                       then WIDTH - OgImage::SPLIT_TEXT_X - 80
                       when "brutalist"                   then WIDTH - OgImage::BRUTALIST_TEXT_X - (OgImage::BRUTALIST_INSET + OgImage::BRUTALIST_FRAME + 40)
                       when "terminal"                    then WIDTH - OgImage::TERMINAL_TEXT_X * 2 - prompt_advance.to_i
                       when "bauhaus"                     then OgImage::BAUHAUS_TEXT_W
                       when "halftone"                    then OgImage::HALFTONE_TEXT_W
                       when "framed"                      then OgImage::FRAMED_WRAP_W
                       when "artistic", "hero", "surreal" then WIDTH - 280
                       else                                    Math.min(WIDTH - margin_x * 2, 980)
                       end

          # Sanitize every string the fonts will draw: codepoints without a
          # glyph in any chain font (emoji, mostly) would render as tofu
          # boxes otherwise.
          title_text = drop_missing_glyphs(title_chain, page.title)
          site_title = drop_missing_glyphs(brand_chain, config.title)

          title_lines = balanced_wrap_chain(title_chain, font_size, title_text, wrap_width)
          # The band style draws the title inside a fixed-height color band;
          # cap the lines so a long title can't overflow the band invisibly.
          title_cap = case style
                      when "monument" then 2
                      when "band"     then OgImage.band_line_capacity(font_size.to_i)
                      else                 OgImage::TITLE_MAX_LINES
                      end
          title_lines = OgImage.cap_lines(title_lines, title_cap)

          desc_text = drop_missing_glyphs(desc_chain, page.description || "")
          desc_lines = desc_text.empty? ? [] of String : word_wrap_chain(desc_chain, desc_size, desc_text, wrap_width)
          desc_lines = OgImage.cap_lines(desc_lines, style == "monument" ? 1 : OgImage::DESC_MAX_LINES)

          # Vertical geometry. `title_start_y` is the BASELINE of the first
          # title line (rendering converts to top with `y - font_size`).
          title_block_height = title_lines.size * title_line_h
          desc_gap = font_size * 0.55_f32
          desc_block_height = desc_lines.empty? ? 0_f32 : desc_lines.size * desc_line_h
          total_text_height = title_block_height + (desc_lines.empty? ? 0_f32 : desc_gap + desc_block_height)

          case style
          when "default"
            title_start_y = OgImage::MASTHEAD_TITLE_TOP + font_size
          when "dots"
            title_start_y = OgImage::DOTS_TITLE_TOP + font_size
          when "waves"
            # Centered over the calm region above the tide bands.
            region = OgImage::WAVES_TEXT_REGION_H.to_f32
            title_start_y = Math.max(font_size + 20, ((region - total_text_height) / 2) + font_size)
          when "editorial"
            title_start_y = OgImage::EDITORIAL_TITLE_TOP + font_size
          when "framed"
            title_start_y = OgImage::FRAMED_TITLE_TOP + font_size
          when "monument"
            title_start_y = OgImage::MONUMENT_TITLE_TOP + font_size
          when "artistic", "surreal"
            title_start_y = Math.max(font_size + 48, ((HEIGHT - total_text_height) / 2).to_f32 + font_size - 28)
          when "hero"
            # Hero: Title dominates, pushed higher for impact
            title_start_y = Math.max(font_size + 20, 180_f32)
          when "band"
            # Band: vertically centered inside the color band.
            band_center = (OgImage::BAND_TOP + OgImage::BAND_HEIGHT // 2).to_f32
            title_start_y = band_center - (title_block_height / 2) + font_size - 6
          when "brutalist"
            # Brutalist: large title anchored near the top of the framed panel.
            title_start_y = (OgImage::BRUTALIST_INSET + OgImage::BRUTALIST_FRAME + 100).to_f32
          when "split"
            title_start_y = Math.max(font_size + 40, ((HEIGHT - total_text_height) / 2).to_f32 + font_size - 10)
          when "terminal"
            # Anchored near the top of the window content area, prompt-style.
            title_start_y = (OgImage::TERMINAL_INSET + OgImage::TERMINAL_BAR_H + 60).to_f32 + font_size
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
            case style
            when "artistic"  then panel = has_bg ? 0.78 : 0.26
            when "surreal"   then panel = has_bg ? 0.80 : 0.34
            when "hero"      then panel = has_bg ? 0.65 : 0.30
            when "framed"    then panel = has_bg ? 0.55 : 0.0
            when "editorial" then panel = has_bg ? 0.34 : 0.0
            when "monument"  then panel = has_bg ? 0.60 : 0.0
            end
          end

          # Hero: oversized "ghost" echo of the title's first word behind
          # the composition for poster-style depth. Kept fully on-canvas
          # (the old fixed placement clipped its cap at the top edge) and
          # width-capped so a long first word can't run off both sides.
          if style == "hero"
            if ghost = title_text.split(/\s+/).first?
              unless ghost.empty?
                ghost_text = ghost.upcase
                ghost_size = font_size * 2.6_f32
                gw = chain_measure(ctx.display, ghost_size, ghost_text)
                ghost_size *= 1500_f32 / gw if gw > 1500
                ghost_top = Math.max(title_start_y - font_size * 2.35_f32, 16_f32)
                chain_render(ctx.display, pixels, (margin_x - 10).to_f32, ghost_top, ghost_size, ghost_text, text_color, 0.06_f32)
              end
            end
          end

          # Geometric and signature styles are intentionally flat — they never use the soft panel.
          if panel > 0.01 && !OgImage.geometric?(style) && !OgImage.signature?(style)
            top_offset : Float32 = style == "framed" ? 48_f32 : 36_f32
            bottom_offset : Float32 = style == "framed" ? 52_f32 : 40_f32
            panel_top = (title_start_y - font_size - top_offset).to_f32.clamp(16_f32, HEIGHT * 0.52_f32)
            panel_bottom = (title_start_y + total_text_height + bottom_offset).to_f32.clamp(panel_top + 90, HEIGHT - 60_f32)
            draw_text_panel(pixels, panel_top, panel_bottom, panel, bg_color, accent_color)
          end

          # Terminal: accent "$" prompt before the first title line.
          if style == "terminal"
            chain_render(ctx.mono, pixels, margin_x.to_f32, title_start_y - font_size, font_size, "$", accent_color, 1.0_f32)
          end

          # `default` masthead: uppercase tracked site-name eyebrow at the
          # top instead of the bottom brand row (an accent tick stands in
          # when the site name is hidden).
          if style == "default"
            if ai.show_title && !site_title.empty?
              chain_render(ctx.display, pixels, OgImage::MARGIN_X.to_f32,
                (OgImage::MASTHEAD_EYEBROW_Y - OgImage::MASTHEAD_EYEBROW_SIZE).to_f32,
                OgImage::MASTHEAD_EYEBROW_SIZE.to_f32, site_title.upcase, accent_color, 1.0_f32, 2.0_f32)
            else
              fill_rect(pixels, OgImage::MARGIN_X, OgImage::MASTHEAD_EYEBROW_Y - 6, 48, 6, accent_color)
            end
          end

          # Editorial: uppercase tracked kicker between the hairline rules.
          if style == "editorial" && ai.show_title && !site_title.empty?
            chain_render(ctx.display, pixels, margin_x.to_f32,
              (OgImage::EDITORIAL_KICKER_Y - OgImage::EDITORIAL_KICKER_SIZE).to_f32,
              OgImage::EDITORIAL_KICKER_SIZE.to_f32, site_title.upcase, accent_color, 1.0_f32, 2.0_f32)
          end

          # Render title lines. `band` knocks the title out of the color band
          # using the background color for strong magazine-cover contrast.
          # `framed` centers every line; `monument` sets tight tracking.
          title_color = style == "band" ? bg_color : text_color
          title_tracking = style == "monument" ? -1.0_f32 : 0.0_f32
          title_x = margin_x.to_f32 + prompt_advance
          last_line_end_x = title_x
          title_lines.each_with_index do |line, i|
            y = title_start_y + i * title_line_h
            x = if style == "framed"
                  (WIDTH - chain_measure(title_chain, font_size, line)) / 2
                else
                  title_x
                end
            end_x = chain_render(title_chain, pixels, x, y - font_size, font_size, line, title_color, 1.0_f32, title_tracking)
            last_line_end_x = end_x if i == title_lines.size - 1
          end

          # Terminal: block cursor after the last title line.
          if style == "terminal" && !title_lines.empty?
            cursor_x = (last_line_end_x + font_size * 0.25_f32).to_i
            cursor_y = (title_start_y + (title_lines.size - 1) * title_line_h - font_size * 0.88_f32).to_i
            fill_rect(pixels, cursor_x, cursor_y, (font_size * 0.52_f32).to_i, (font_size * 0.95_f32).to_i, accent_color)
          end

          # Minimal: an accent full stop after the last title line — the
          # entire composition is type plus one period.
          if style == "minimal" && !title_lines.empty?
            r = Math.max((font_size * 0.11_f32).to_i, 3)
            last_baseline = title_start_y + (title_lines.size - 1) * title_line_h
            dot_cx = (last_line_end_x + font_size * 0.18_f32).to_i + r
            dot_cy = (last_baseline - r).to_i
            draw_filled_circle(pixels, dot_cx, dot_cy, r, accent_color, 1.0)
          end

          # Editorial: thin vertical accent rule, cap-height aligned to the title.
          if style == "editorial"
            rule_x = margin_x - 28
            rule_top = (title_start_y - font_size * 0.72_f32).to_i.clamp(0, HEIGHT)
            rule_bottom = (title_start_y + (title_lines.size - 1) * title_line_h).to_i.clamp(rule_top, HEIGHT)
            fill_rect(pixels, rule_x, rule_top, 4, rule_bottom - rule_top, accent_color) if rule_x >= 0
          end

          # Render description — hero and monument get very small or minimal desc treatment
          desc_last_baseline = title_start_y + (title_lines.size - 1) * title_line_h
          unless desc_lines.empty?
            desc_start_y = if style == "band"
                             (OgImage::BAND_TOP + OgImage::BAND_HEIGHT + 24).to_f32 + desc_size
                           else
                             desc_last_baseline + desc_gap + desc_size
                           end

            # For hero/monument, make description much more subtle
            desc_opacity = if style == "hero" || style == "monument"
                             0.45_f32
                           else
                             OgImage::DESC_OPACITY.to_f32
                           end

            desc_lines.each_with_index do |line, i|
              y = desc_start_y + i * desc_line_h
              x = if style == "framed"
                    (WIDTH - chain_measure(desc_chain, desc_size, line)) / 2
                  else
                    margin_x.to_f32 + prompt_advance
                  end
              chain_render(desc_chain, pixels, x, y - desc_size, desc_size, line, text_color, desc_opacity)
              desc_last_baseline = y
            end
          end

          # Terminal: faint "output" skeleton rows under the text, like a
          # command that already printed something.
          if style == "terminal"
            rows_top = desc_last_baseline + 44_f32
            OgImage::TERMINAL_GHOST_ROWS.each_with_index do |w, i|
              ry = (rows_top + i * 32).to_i
              break if ry + 10 > HEIGHT - OgImage::TERMINAL_INSET - 24
              fill_rounded_rect(pixels, OgImage::TERMINAL_TEXT_X, ry, w, 10, 5, text_color, 0.08)
            end
          end

          # Site name / brand row. Several styles relocate it: terminal puts
          # it in the window title bar, default/editorial replace it with the
          # eyebrow/kicker, monument right-aligns it, framed centers it.
          if ai.show_title && !site_title.empty?
            case style
            when "default", "editorial"
              # handled above (eyebrow / kicker)
            when "terminal"
              name_size = 20_f32
              name_w = chain_measure(ctx.mono, name_size, site_title)
              bar_center_y = (OgImage::TERMINAL_INSET + 2 + OgImage::TERMINAL_BAR_H // 2).to_f32
              chain_render(ctx.mono, pixels, (WIDTH - name_w) / 2, bar_center_y - name_size / 2, name_size, site_title, text_color, 0.5_f32)
            when "monument"
              name_w = chain_measure(brand_chain, OgImage::BRAND_SIZE.to_f32, site_title, 1.0_f32)
              tick_x = (OgImage::MONUMENT_BRAND_RIGHT - name_w - OgImage::BRAND_TICK_W - OgImage::BRAND_GAP).to_i
              fill_rect(pixels, tick_x, OgImage::BRAND_BASELINE - OgImage::BRAND_TICK_H + 4, OgImage::BRAND_TICK_W, OgImage::BRAND_TICK_H, accent_color)
              chain_render(brand_chain, pixels, (tick_x + OgImage::BRAND_TICK_W + OgImage::BRAND_GAP).to_f32,
                (OgImage::BRAND_BASELINE - OgImage::BRAND_SIZE).to_f32, OgImage::BRAND_SIZE.to_f32,
                site_title, text_color, 0.92_f32, 1.0_f32)
            when "framed"
              name_w = chain_measure(brand_chain, OgImage::BRAND_SIZE.to_f32, site_title, 1.0_f32)
              chain_render(brand_chain, pixels, (WIDTH - name_w) / 2,
                (OgImage::FRAMED_BRAND_Y - OgImage::BRAND_SIZE).to_f32, OgImage::BRAND_SIZE.to_f32,
                site_title, text_color, 0.7_f32, 1.0_f32)
            else
              base_margin = case style
                            when "split"                       then 80
                            when "brutalist"                   then OgImage::BRUTALIST_TEXT_X
                            when "bauhaus", "halftone"         then OgImage::BAUHAUS_TEXT_X
                            when "artistic", "surreal", "hero" then 140
                            else                                    OgImage::LOGO_MARGIN
                            end
              site_x = (ai.logo && ai.logo_position == "bottom-left") ? (base_margin + OgImage::LOGO_SIZE + OgImage::LOGO_TEXT_GAP) : base_margin
              row_opacity = style == "minimal" ? 0.5_f32 : 0.92_f32
              if style == "split"
                # Inside the accent block an accent tick would vanish — name only.
                chain_render(brand_chain, pixels, site_x.to_f32, (OgImage::BRAND_BASELINE - OgImage::BRAND_SIZE).to_f32,
                  OgImage::BRAND_SIZE.to_f32, site_title, text_color, 1.0_f32, 1.0_f32)
              else
                fill_rect_alpha(pixels, site_x, OgImage::BRAND_BASELINE - OgImage::BRAND_TICK_H + 4,
                  OgImage::BRAND_TICK_W, OgImage::BRAND_TICK_H, accent_color, row_opacity.to_f64)
                chain_render(brand_chain, pixels, (site_x + OgImage::BRAND_TICK_W + OgImage::BRAND_GAP).to_f32,
                  (OgImage::BRAND_BASELINE - OgImage::BRAND_SIZE).to_f32, OgImage::BRAND_SIZE.to_f32,
                  site_title, text_color, row_opacity, 1.0_f32)
              end
            end
          end
        end

        # Word-wrap using incremental chain-measured text width.
        # Handles CJK characters by allowing breaks between any CJK characters.
        private def self.word_wrap_chain(chain : Array(FontEntry), px_size : Float32, text : String, max_width : Int32) : Array(String)
          return [] of String if text.empty?
          segments = Content::Seo::OgImage.split_into_segments(text)
          lines = [] of String
          current_line = ""
          current_width = 0_f32

          segments.each do |seg|
            seg_width = chain_measure(chain, px_size, seg)
            if current_line.empty?
              current_line = seg
              current_width = seg_width
            elsif current_width + seg_width <= max_width
              current_line += seg
              current_width += seg_width
            else
              lines << current_line.strip
              current_line = seg.lstrip
              current_width = chain_measure(chain, px_size, current_line)
            end
          end
          lines << current_line.strip unless current_line.strip.empty?
          lines
        end

        # Balanced title wrap: greedy first; when the last line is an orphan
        # (much shorter than the widest line), re-wrap against a tighter
        # target width so line lengths even out. Only accepted when it does
        # not add lines.
        private def self.balanced_wrap_chain(chain : Array(FontEntry), px_size : Float32, text : String, max_width : Int32) : Array(String)
          lines = word_wrap_chain(chain, px_size, text, max_width)
          return lines if lines.size < 2 || lines.size > 3
          widths = lines.map { |l| chain_measure(chain, px_size, l) }
          widest = widths.max
          return lines if widest <= 0 || widths.last >= widest * 0.55_f32
          target = Math.max(widths.sum / lines.size * 1.08_f32, widest * 0.6_f32)
          rebalanced = word_wrap_chain(chain, px_size, text, target.to_i)
          rebalanced.size <= lines.size ? rebalanced : lines
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

        # Render style patterns onto pixel buffer. Every pattern is a
        # composition with a focal point rather than uniform wallpaper;
        # `opacity` acts as the peak alpha with internal falloff.
        private def self.render_pattern(pixels : UInt8*, style : String, accent : UInt32, opacity : Float64, scale : Float64)
          case style
          when "dots"
            # Corner-weighted halftone fade: staggered dots grow and
            # brighten toward the top-right focal corner.
            spacing = Math.max((26 * scale).to_i, 4)
            row = 0
            y = spacing // 2
            while y < HEIGHT
              x = row.odd? ? spacing // 2 : 0
              while x < WIDTH + spacing
                dx = (WIDTH - x).to_f
                dy = y.to_f
                t = (1.0 - Math.sqrt(dx * dx + dy * dy) / 950.0).clamp(0.0, 1.0)
                r = 1.0 + 4.2 * (t ** 1.8)
                alpha = opacity * t
                draw_filled_circle(pixels, x, y, r.to_i, accent, alpha) if r >= 0.8 && alpha > 0.004
                x += spacing
              end
              y += spacing
              row += 1
            end
          when "grid"
            # Blueprint: a fine quiet grid plus one focal crosshair with
            # registration marks.
            spacing = Math.max((48 * scale).to_i, 8)
            minor = (opacity * 0.4).clamp(0.0, 1.0)
            y = 0
            while y < HEIGHT
              fill_rect_alpha(pixels, 0, y, WIDTH, 1, accent, minor)
              y += spacing
            end
            x = 0
            while x < WIDTH
              fill_rect_alpha(pixels, x, 0, 1, HEIGHT, accent, minor)
              x += spacing
            end
            focal = (opacity * 1.3).clamp(0.0, 1.0)
            fill_rect_alpha(pixels, OgImage::GRID_FOCAL_X, 0, 1, HEIGHT, accent, focal)
            fill_rect_alpha(pixels, 0, OgImage::GRID_FOCAL_Y, WIDTH, 1, accent, focal)
            draw_filled_circle(pixels, OgImage::GRID_FOCAL_X, OgImage::GRID_FOCAL_Y, 7, accent, (opacity * 2.0).clamp(0.0, 1.0))
            draw_border(pixels, 435, OgImage::GRID_FOCAL_Y - 5, 10, 10, 1, accent)
          when "diagonal"
            stripe_wedge(pixels, accent, opacity)
          when "waves"
            # Layered tide bands anchored to the bottom edge.
            fill_wave_band(pixels, 430.0, 26.0, 1050.0, 0.0, shifted_hue(accent, -16.0), opacity * 0.35)
            fill_wave_band(pixels, 474.0, 34.0, 800.0, 1.9, accent, opacity * 0.5)
            fill_wave_band(pixels, 522.0, 22.0, 1250.0, 4.1, shifted_hue(accent, 18.0), opacity * 0.75)
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
          when "default"
            # Masthead: a low corner glow + gentle vignette give the flat
            # canvas depth without competing with the type.
            unless has_bg_image
              draw_radial_glow(pixels, 1160, 700, 720, accent, 0.14)
              draw_vignette(pixels, 0.12)
            end
          when "gradient"
            # Duotone wash: accent-tinted diagonal gradient + corner glow +
            # vignette + grain — real depth instead of a fade-to-nothing.
            unless has_bg_image
              c1 = shifted_lightness(lerp_color(bg, accent, 0.45), -0.06)
              c2 = shifted_lightness(bg, -0.03)
              fill_linear_gradient(pixels, c1, c2)
              draw_radial_glow(pixels, 140, 640, 560, accent, 0.20)
              draw_vignette(pixels, 0.15)
              apply_grain(pixels, 0.035)
            end
          when "editorial"
            # Magazine front: quiet full-width hairline rules above and
            # below the content area (the kicker/title live between them).
            rule = neutral_line(bg)
            fill_rect(pixels, OgImage::EDITORIAL_RULE_X0, OgImage::EDITORIAL_RULE_TOP, OgImage::EDITORIAL_RULE_X1 - OgImage::EDITORIAL_RULE_X0, 1, rule)
            fill_rect(pixels, OgImage::EDITORIAL_RULE_X0, OgImage::EDITORIAL_RULE_BOT, OgImage::EDITORIAL_RULE_X1 - OgImage::EDITORIAL_RULE_X0, 1, rule)
          when "monument"
            # A short accent rule ABOVE the title; the vast top-left
            # whitespace is the design.
            fill_rect(pixels, OgImage::MARGIN_X, OgImage::MONUMENT_RULE_Y, OgImage::MONUMENT_RULE_W, OgImage::MONUMENT_RULE_H, accent)
          when "split"
            # Secondary strip first (wider), then the accent block on top —
            # leaving a two-tone diagonal seam between them.
            fill_left_diagonal(pixels, secondary, OgImage::SPLIT_TOP_X + OgImage::SPLIT_EDGE, OgImage::SPLIT_BOTTOM_X + OgImage::SPLIT_EDGE)
            fill_left_diagonal(pixels, accent, OgImage::SPLIT_TOP_X, OgImage::SPLIT_BOTTOM_X)
          when "band"
            # A thin muted echo band above the main band for print feel.
            fill_rect_alpha(pixels, 0, OgImage::BAND_TOP - OgImage::BAND_ECHO_GAP, WIDTH, OgImage::BAND_ECHO_H, accent, 0.4)
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
            # Mesh-gradient color field: diagonal base + analogous-hue blobs
            # (arbitrary rotations read as AI-purple) + a dark anchor for
            # text legibility + film grain.
            unless has_bg_image
              fill_linear_gradient(pixels, accent, secondary)
              draw_radial_glow(pixels, 210, 60, 540, shifted_hue(accent, 28.0), 0.55)
              draw_radial_glow(pixels, 1060, 570, 580, shifted_hue(secondary, -20.0), 0.5)
              draw_radial_glow(pixels, 600, 730, 580, bg, 0.6)
              apply_grain(pixels, 0.05)
            end
          when "hero"
            # Dramatic spotlight glow + secondary counter-glow + grain.
            unless has_bg_image
              draw_radial_glow(pixels, WIDTH // 2, 230, 640, accent, 0.6)
              draw_radial_glow(pixels, 1060, 600, 480, secondary, 0.22)
              apply_grain(pixels, 0.045)
            end
          when "surreal"
            # Aurora: soft orbs + flowing ribbon bands + grain.
            unless has_bg_image
              draw_radial_glow(pixels, 300, 190, 470, accent, 0.55)
              draw_radial_glow(pixels, 960, 390, 540, secondary, 0.5)
              draw_radial_glow(pixels, 620, 600, 460, shifted_hue(accent, 40.0), 0.35)
              draw_ribbon(pixels, 230.0, 55.0, 56.0, accent, 0.30, 760.0, 0.6)
              draw_ribbon(pixels, 410.0, 70.0, 90.0, secondary, 0.25, 920.0, 2.4)
              apply_grain(pixels, 0.05)
            end
          when "framed"
            # Invitation card: a neutral hairline frame plus accent corner
            # brackets inset from it.
            fi = OgImage::FRAMED_INSET
            draw_border(pixels, fi, fi, WIDTH - 2 * fi, HEIGHT - 2 * fi, OgImage::FRAMED_WIDTH, neutral_line(bg))
            bi = OgImage::FRAMED_BRACKET_INSET
            arm = OgImage::FRAMED_BRACKET_ARM
            bw = OgImage::FRAMED_BRACKET_W
            draw_corner_bracket(pixels, bi, bi, arm, bw, accent, :tl)
            draw_corner_bracket(pixels, WIDTH - bi, bi, arm, bw, accent, :tr)
            draw_corner_bracket(pixels, bi, HEIGHT - bi, arm, bw, accent, :bl)
            draw_corner_bracket(pixels, WIDTH - bi, HEIGHT - bi, arm, bw, accent, :br)
          when "terminal"
            draw_terminal_window(pixels, bg, has_bg_image)
          when "bauhaus"
            # Flat geometric art composition on the right: circle, dot,
            # triangle, quarter disc — layered in accent/secondary/derived.
            tertiary = shifted_hue(accent, 60.0, 0.45)
            draw_filled_circle(pixels, 940, 190, 220, accent, 1.0)
            draw_filled_circle(pixels, 690, 150, 30, secondary, 1.0)
            fill_triangle(pixels, 690, 500, 830, 260, 970, 500, tertiary)
            # Quarter disc at the bottom-right corner (canvas clips it).
            draw_filled_circle(pixels, WIDTH, HEIGHT, 310, secondary, 1.0)
          when "halftone"
            draw_halftone_field(pixels, accent)
          end
        end

        # A quiet hairline color derived from the background: slightly
        # lighter on dark backgrounds, slightly darker on light ones.
        private def self.neutral_line(bg : UInt32) : UInt32
          _, _, l = OgImage.hex_to_hsl("#%06x" % bg)
          shifted_lightness(bg, l > 0.5 ? -0.30 : 0.32)
        end

        # Rotate a packed RGB color's hue by `degrees` (HSL round-trip).
        private def self.shifted_hue(color : UInt32, degrees : Float64, min_sat : Float64 = 0.0) : UInt32
          parse_hex_color(OgImage.shift_hue("#%06x" % color, degrees, min_sat))
        end

        # Lighten (positive delta) or darken (negative) a packed RGB color.
        private def self.shifted_lightness(color : UInt32, delta : Float64) : UInt32
          parse_hex_color(OgImage.adjust_lightness("#%06x" % color, delta))
        end

        # Deterministic film grain — breaks up gradient banding and adds a
        # subtle premium texture. Hash-based so builds stay byte-identical.
        private def self.apply_grain(pixels : UInt8*, amount : Float64)
          return if amount <= 0.0
          max_shift = amount * 255.0
          total = WIDTH * HEIGHT
          i = 0
          while i < total
            h = i.to_u32 &* 2654435761_u32
            h ^= h >> 13
            h = h &* 1274126177_u32
            h ^= h >> 16
            n = (((h & 0xFF).to_f / 255.0) - 0.5) * 2.0 * max_shift
            idx = i * CHANNELS
            pixels[idx] = (pixels[idx].to_f + n).clamp(0.0, 255.0).to_u8
            pixels[idx + 1] = (pixels[idx + 1].to_f + n).clamp(0.0, 255.0).to_u8
            pixels[idx + 2] = (pixels[idx + 2].to_f + n).clamp(0.0, 255.0).to_u8
            i += 1
          end
        end

        # Soft horizontal "aurora" ribbon following a sine curve, fading
        # out quadratically from its center line.
        private def self.draw_ribbon(pixels : UInt8*, base_y : Float64, amplitude : Float64, thickness : Float64, color : UInt32, intensity : Float64, wavelength : Float64, phase : Float64)
          cr = ((color >> 16) & 0xFF).to_f
          cg = ((color >> 8) & 0xFF).to_f
          cb = (color & 0xFF).to_f
          half = thickness / 2.0
          WIDTH.times do |px|
            cy = base_y + Math.sin(px.to_f * Math::PI * 2.0 / wavelength + phase) * amplitude
            y0 = (cy - half).to_i
            y1 = (cy + half).to_i
            (y0..y1).each do |py|
              next if py < 0 || py >= HEIGHT
              d = ((py - cy) / half).abs
              next if d >= 1.0
              a = intensity * (1.0 - d * d)
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
              pixels[idx] = (dr + (cr - dr) * a).to_u8
              pixels[idx + 1] = (dg + (cg - dg) * a).to_u8
              pixels[idx + 2] = (db + (cb - db) * a).to_u8
            end
          end
        end

        # Fill a rounded rectangle (optionally translucent).
        private def self.fill_rounded_rect(pixels : UInt8*, x : Int32, y : Int32, w : Int32, h : Int32, radius : Int32, color : UInt32, opacity : Float64 = 1.0)
          radius = Math.min(radius, Math.min(w, h) // 2)
          rf = radius.to_f
          h.times do |ry|
            py = y + ry
            next if py < 0 || py >= HEIGHT
            inset = 0
            if ry < radius
              dy = rf - ry - 0.5
              inset = (rf - Math.sqrt(Math.max(rf * rf - dy * dy, 0.0))).round.to_i
            elsif ry >= h - radius
              dy = ry - (h - radius) + 0.5
              inset = (rf - Math.sqrt(Math.max(rf * rf - dy * dy, 0.0))).round.to_i
            end
            row_x = x + inset
            row_w = w - 2 * inset
            next if row_w <= 0
            if opacity >= 1.0
              fill_rect(pixels, row_x, py, row_w, 1, color)
            else
              fill_rect_alpha(pixels, row_x, py, row_w, 1, color, opacity)
            end
          end
        end

        # Fill a triangle via half-plane (edge function) tests over its bbox.
        private def self.fill_triangle(pixels : UInt8*, x1 : Int32, y1 : Int32, x2 : Int32, y2 : Int32, x3 : Int32, y3 : Int32, color : UInt32)
          r = ((color >> 16) & 0xFF).to_u8
          g = ((color >> 8) & 0xFF).to_u8
          b = (color & 0xFF).to_u8
          min_x = {x1, x2, x3}.min.clamp(0, WIDTH - 1)
          max_x = {x1, x2, x3}.max.clamp(0, WIDTH - 1)
          min_y = {y1, y2, y3}.min.clamp(0, HEIGHT - 1)
          max_y = {y1, y2, y3}.max.clamp(0, HEIGHT - 1)
          area = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
          return if area == 0
          (min_y..max_y).each do |py|
            (min_x..max_x).each do |px|
              w0 = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)
              w1 = (x3 - x2) * (py - y2) - (y3 - y2) * (px - x2)
              w2 = (x1 - x3) * (py - y3) - (y1 - y3) * (px - x3)
              inside = area > 0 ? (w0 >= 0 && w1 >= 0 && w2 >= 0) : (w0 <= 0 && w1 <= 0 && w2 <= 0)
              next unless inside
              idx = (py * WIDTH + px) * CHANNELS
              pixels[idx] = r
              pixels[idx + 1] = g
              pixels[idx + 2] = b
              pixels[idx + 3] = 255_u8
            end
          end
        end

        # `terminal`: code-editor window — rounded panel, title bar with
        # traffic lights, faint scanlines. Slightly translucent over a photo.
        private def self.draw_terminal_window(pixels : UInt8*, bg : UInt32, has_bg_image : Bool)
          inset = OgImage::TERMINAL_INSET
          radius = OgImage::TERMINAL_RADIUS
          bar_h = OgImage::TERMINAL_BAR_H
          win_w = WIDTH - 2 * inset
          win_h = HEIGHT - 2 * inset
          window = shifted_lightness(bg, 0.045)
          bar = shifted_lightness(bg, 0.085)
          border = shifted_lightness(bg, 0.16)

          # Border ring, then the panel inset by 2px on top of it.
          fill_rounded_rect(pixels, inset, inset, win_w, win_h, radius, border)
          fill_rounded_rect(pixels, inset + 2, inset + 2, win_w - 4, win_h - 4, radius - 2, window, has_bg_image ? 0.92 : 1.0)
          # Title bar: rounded top corners, squared bottom half.
          fill_rounded_rect(pixels, inset + 2, inset + 2, win_w - 4, bar_h, radius - 2, bar)
          fill_rect(pixels, inset + 2, inset + 2 + bar_h // 2, win_w - 4, bar_h - bar_h // 2, bar)
          fill_rect(pixels, inset + 2, inset + 2 + bar_h, win_w - 4, 2, border)
          # Traffic lights.
          OgImage::TERMINAL_LIGHTS.each_with_index do |hex, i|
            draw_filled_circle(pixels, inset + 40 + i * 34, inset + 2 + bar_h // 2, 11, parse_hex_color(hex), 1.0)
          end
          # Faint scanlines in the content area for a subtle CRT feel.
          y = inset + bar_h + 8
          while y < HEIGHT - inset - 4
            fill_rect_alpha(pixels, inset + 2, y, win_w - 4, 1, 0x000000_u32, 0.05)
            y += 4
          end
        end

        # `halftone`: print-style dot field — dots grow toward the right
        # edge, rows staggered like a press halftone screen, with a gentle
        # vertical cosine weight so the field breathes instead of tiling.
        private def self.draw_halftone_field(pixels : UInt8*, accent : UInt32)
          spacing = 28
          max_r = 15.0
          field_x = OgImage::HALFTONE_FIELD_X
          field_w = (WIDTH - field_x).to_f
          mid_y = HEIGHT / 2.0
          row = 0
          y = spacing // 2
          while y < HEIGHT
            x = field_x + (row.odd? ? spacing // 2 : 0)
            breath = 0.65 + 0.35 * Math.cos((y - mid_y) / mid_y * Math::PI / 2.0)
            while x < WIDTH + spacing
              tx = ((x - field_x).to_f / field_w).clamp(0.0, 1.0)
              r = max_r * (tx ** 1.6) * breath
              draw_filled_circle(pixels, x, y, r.to_i, accent, 0.92) if r >= 1.0
              x += spacing
            end
            y += spacing
            row += 1
          end
        end

        # Darken toward the corners (inverse radial vignette). `strength`
        # is the blend factor at the farthest corner; falloff is quadratic
        # so the center stays untouched.
        private def self.draw_vignette(pixels : UInt8*, strength : Float64)
          return if strength <= 0.0
          cx = WIDTH / 2.0
          cy = HEIGHT / 2.0
          max_d2 = cx * cx + cy * cy
          HEIGHT.times do |py|
            dy = py - cy
            WIDTH.times do |px|
              dx = px - cx
              a = strength * ((dx * dx + dy * dy) / max_d2)
              next if a <= 0.002
              idx = (py * WIDTH + px) * CHANNELS
              keep = 1.0 - a
              pixels[idx] = (pixels[idx] * keep).to_u8
              pixels[idx + 1] = (pixels[idx + 1] * keep).to_u8
              pixels[idx + 2] = (pixels[idx + 2] * keep).to_u8
            end
          end
        end

        # Fill from a sine curve down to the bottom edge — one "tide band".
        # Overlapping bands accumulate, which is the point.
        private def self.fill_wave_band(pixels : UInt8*, base_y : Float64, amplitude : Float64, wavelength : Float64, phase : Float64, color : UInt32, alpha : Float64)
          alpha = alpha.clamp(0.0, 1.0)
          return if alpha <= 0.0
          cr = ((color >> 16) & 0xFF).to_f
          cg = ((color >> 8) & 0xFF).to_f
          cb = (color & 0xFF).to_f
          WIDTH.times do |px|
            edge = base_y + Math.sin(px.to_f * Math::PI * 2.0 / wavelength + phase) * amplitude
            y0 = edge.to_i.clamp(0, HEIGHT)
            (y0...HEIGHT).each do |py|
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
              pixels[idx] = (dr + (cr - dr) * alpha).to_u8
              pixels[idx + 1] = (dg + (cg - dg) * alpha).to_u8
              pixels[idx + 2] = (db + (cb - db) * alpha).to_u8
            end
          end
        end

        # Two rects forming an L-shaped bracket at a corner point (x, y).
        private def self.draw_corner_bracket(pixels : UInt8*, x : Int32, y : Int32, arm : Int32, thickness : Int32, color : UInt32, corner : Symbol)
          case corner
          when :tl
            fill_rect(pixels, x, y, arm, thickness, color)
            fill_rect(pixels, x, y, thickness, arm, color)
          when :tr
            fill_rect(pixels, x - arm, y, arm, thickness, color)
            fill_rect(pixels, x - thickness, y, thickness, arm, color)
          when :bl
            fill_rect(pixels, x, y - thickness, arm, thickness, color)
            fill_rect(pixels, x, y - arm, thickness, arm, color)
          when :br
            fill_rect(pixels, x - arm, y - thickness, arm, thickness, color)
            fill_rect(pixels, x - thickness, y - arm, thickness, arm, color)
          end
        end

        # `diagonal`: 45° stripes clipped to the bottom-right corner wedge
        # with an alpha ramp from the hypotenuse (0) to the corner (peak),
        # plus an accent rule along the hypotenuse.
        private def self.stripe_wedge(pixels : UInt8*, accent : UInt32, opacity : Float64)
          x0 = OgImage::DIAG_WEDGE_X0
          y1 = OgImage::DIAG_WEDGE_Y1
          # Edge function: 0 on the hypotenuse (x0,HEIGHT)-(WIDTH,y1), most
          # negative at the (WIDTH,HEIGHT) corner.
          e_corner = ((WIDTH - x0) * (y1 - HEIGHT)).to_f
          cr = ((accent >> 16) & 0xFF).to_f
          cg = ((accent >> 8) & 0xFF).to_f
          cb = (accent & 0xFF).to_f
          (y1...HEIGHT).each do |py|
            (x0...WIDTH).each do |px|
              e = ((px - x0) * (y1 - HEIGHT) - (py - HEIGHT) * (WIDTH - x0)).to_f
              next if e > 0 # hypotenuse side — outside the wedge
              next unless ((px + py) % 36) < 14
              a = (opacity * (e / e_corner)).clamp(0.0, 1.0)
              next if a <= 0.004
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
              pixels[idx] = (dr + (cr - dr) * a).to_u8
              pixels[idx + 1] = (dg + (cg - dg) * a).to_u8
              pixels[idx + 2] = (db + (cb - db) * a).to_u8
            end
          end
          # Accent rule along the hypotenuse.
          rule_a = (opacity * 1.4).clamp(0.0, 1.0)
          slope = (y1 - HEIGHT).to_f / (WIDTH - x0)
          (x0...WIDTH).each do |px|
            yline = HEIGHT + ((px - x0) * slope)
            3.times do |o|
              py = yline.to_i - o
              next if py < 0 || py >= HEIGHT
              idx = (py * WIDTH + px) * CHANNELS
              dr = pixels[idx]; dg = pixels[idx + 1]; db = pixels[idx + 2]
              pixels[idx] = (dr + (cr - dr) * rule_a).to_u8
              pixels[idx + 1] = (dg + (cg - dg) * rule_a).to_u8
              pixels[idx + 2] = (db + (cb - db) * rule_a).to_u8
            end
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
