require "base64"
require "digest/sha256"
require "file_utils"
require "json"
require "../../core/build/parallel"
require "../../models/config"
require "../../models/page"
require "../../utils/logger"
require "../../utils/text_utils"
require "./og_png_renderer"

module Hwaro
  module Content
    module Seo
      # Auto-generate OG (Open Graph) preview images as SVG files.
      # Produces 1200x630 SVG images with the page title, description,
      # site name, and optional logo — all without external dependencies.
      class OgImage
        WIDTH  = 1200
        HEIGHT =  630

        LOGO_SIZE          =  48
        LOGO_MARGIN        =  80
        LOGO_TOP_Y         =  20
        LOGO_BOTTOM_OFFSET = 100
        LOGO_TEXT_GAP      =  12 # gap between logo and site name text

        # Yield frequency inside the heavy OG PNG (and fallback SVG) rendering
        # worker loop (see generate()).
        #
        # Yielding after every single render adds scheduler overhead on
        # CPU-bound work. Yielding too rarely can starve the HTTP accept
        # fiber during `serve --fast-start` background OG generation.
        #
        # 8 is a pragmatic balance for current workloads.
        PNG_YIELD_INTERVAL = 8

        MIME_TYPES = {
          ".png"  => "image/png",
          ".jpg"  => "image/jpeg",
          ".jpeg" => "image/jpeg",
          ".svg"  => "image/svg+xml",
          ".gif"  => "image/gif",
          ".webp" => "image/webp",
        }

        # --- Style families (single source of truth, shared by SVG + PNG renderers) ---
        #
        # "Modern" styles are typography/panel-driven and reuse the classic
        # background patterns. "Geometric" styles paint bold, distinctive
        # background shapes (color blocks, bands, frames) and are the
        # high-contrast, design-forward additions.
        MODERN_STYLES    = {"editorial", "framed", "artistic", "hero", "surreal", "monument"}
        GEOMETRIC_STYLES = {"split", "band", "brutalist"}

        def self.modern?(style : String) : Bool
          MODERN_STYLES.includes?(style)
        end

        def self.geometric?(style : String) : Bool
          GEOMETRIC_STYLES.includes?(style)
        end

        # Styles that drop the classic thin top/bottom accent bars for a
        # cleaner, more modern composition.
        def self.no_accent_bars?(style : String) : Bool
          style == "minimal" || modern?(style) || geometric?(style)
        end

        # --- Geometric style layout (shared by SVG + PNG so both stay in sync) ---
        # `split`: a diagonal color block on the left; text lives on the right.
        SPLIT_TOP_X    = 480 # block's right edge at the top
        SPLIT_BOTTOM_X = 320 # block's right edge at the bottom (slanted)
        SPLIT_EDGE     =  16 # secondary-color accent strip along the diagonal
        SPLIT_TEXT_X   = 540 # left margin of the title/description block

        # `band`: a full-width solid band behind the (knocked-out) title.
        BAND_TOP    = 210
        BAND_HEIGHT = 200

        # `brutalist`: thick framed panel with a hard offset shadow block.
        BRUTALIST_INSET  = 36 # gap from the canvas edge to the panel
        BRUTALIST_FRAME  = 14 # border thickness
        BRUTALIST_OFFSET = 20 # hard shadow offset (down-right)
        BRUTALIST_TEXT_X = 88 # left margin of the title inside the frame

        # Resolve the second color for two-tone geometric styles. Falls back
        # to a complementary tone auto-derived from the accent color.
        def self.resolve_secondary(ai : Models::AutoImageConfig) : String
          sc = ai.secondary_color
          (sc && !sc.empty?) ? sc : derive_secondary(ai.accent_color)
        end

        # Derive a punchy complementary color from a hex string via HSL.
        def self.derive_secondary(accent_hex : String) : String
          h, s, l = hex_to_hsl(accent_hex)
          h2 = (h + 180.0) % 360.0 # complementary hue
          s2 = Math.max(s, 0.45)   # keep it vivid
          l2 = l < 0.5 ? Math.min(l + 0.14, 0.74) : Math.max(l - 0.14, 0.30)
          hsl_to_hex(h2, s2, l2)
        end

        # Convert "#RRGGBB" to {hue(0-360), saturation(0-1), lightness(0-1)}.
        def self.hex_to_hsl(hex : String) : Tuple(Float64, Float64, Float64)
          h = hex.lchop("#")
          return {0.0, 0.0, 0.0} if h.size < 6
          r = (h[0, 2].to_i(16) rescue 0) / 255.0
          g = (h[2, 2].to_i(16) rescue 0) / 255.0
          b = (h[4, 2].to_i(16) rescue 0) / 255.0
          max = {r, g, b}.max
          min = {r, g, b}.min
          l = (max + min) / 2.0
          return {0.0, 0.0, l} if max == min
          d = max - min
          s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min)
          hue = case max
                when r then (g - b) / d + (g < b ? 6.0 : 0.0)
                when g then (b - r) / d + 2.0
                else        (r - g) / d + 4.0
                end
          {hue * 60.0, s, l}
        end

        # Convert HSL back to a "#rrggbb" hex string.
        def self.hsl_to_hex(h : Float64, s : Float64, l : Float64) : String
          h = h % 360.0
          c = (1.0 - (2.0 * l - 1.0).abs) * s
          x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs)
          m = l - c / 2.0
          r1, g1, b1 = case
                       when h < 60.0  then {c, x, 0.0}
                       when h < 120.0 then {x, c, 0.0}
                       when h < 180.0 then {0.0, c, x}
                       when h < 240.0 then {0.0, x, c}
                       when h < 300.0 then {x, 0.0, c}
                       else                {c, 0.0, x}
                       end
          r = ((r1 + m) * 255.0).round.to_i.clamp(0, 255)
          g = ((g1 + m) * 255.0).round.to_i.clamp(0, 255)
          b = ((b1 + m) * 255.0).round.to_i.clamp(0, 255)
          "#%02x%02x%02x" % {r, g, b}
        end

        # Generate OG images for all pages that lack a custom image.
        # Sets page.image to the generated SVG path so that og:image
        # meta tags pick it up automatically.
        #
        # `partial` signals that the caller is only handing in a subset
        # of the site's pages (e.g. `--fast-start` runs this once for
        # the priority subset and again for the deferred remainder).
        # In partial mode we accumulate manifest entries across calls
        # rather than overwriting; in full mode (default) we still
        # truncate so manifest entries — and the disk files they
        # describe — for deleted pages get pruned naturally.
        def self.generate(
          pages : Array(Models::Page),
          config : Models::Config,
          output_dir : String,
          verbose : Bool = false,
          partial : Bool = false,
          parallel : Bool = true,
        )
          ai = config.og.auto_image
          return {generated: 0, skipped: 0} unless ai.enabled

          # Validate and resolve output format
          format = ai.format
          unless {"svg", "png"}.includes?(format)
            Logger.warn "  Unknown OG image format '#{format}', falling back to SVG."
            format = "svg"
          end

          # Check PNG rendering availability and pre-load resources once
          png_available = false
          font_ctx = nil
          cached_logo = nil
          cached_bg = nil
          if format == "png"
            font_ctx = OgPngRenderer.load_fonts(ai.font_path)
            png_available = !font_ctx.nil?
            unless png_available
              Logger.warn "  PNG format requested but font initialization failed. Falling back to SVG."
            end
          end

          # Resolve absolute paths for logo and background image
          logo_abs_path = nil
          if logo_path = ai.logo
            abs = logo_path.starts_with?("/") ? logo_path : File.join(Dir.current, logo_path)
            logo_abs_path = abs if File.exists?(abs)
          end

          bg_abs_path = nil
          if bg_image_path = ai.background_image
            abs = bg_image_path.starts_with?("/") ? bg_image_path : File.join(Dir.current, bg_image_path)
            bg_abs_path = abs if File.exists?(abs)
          end

          # Pre-compute base64 data URIs once for SVG rendering.
          # Always compute them even in PNG mode because individual pages
          # may fall back to SVG if PNG rendering fails.
          logo_data_uri = logo_abs_path ? file_to_data_uri(logo_abs_path) : nil
          bg_data_uri = bg_abs_path ? file_to_data_uri(bg_abs_path) : nil

          # Pre-decode and resize images once for PNG rendering
          if png_available
            cached_logo = OgPngRenderer.load_image(logo_abs_path, LOGO_SIZE, LOGO_SIZE) if logo_abs_path
            cached_bg = OgPngRenderer.load_image(bg_abs_path, WIDTH, HEIGHT) if bg_abs_path
          end

          # Pre-render the config-only layers once. Per-page rendering
          # then memcpy's this 3MB base buffer instead of redoing the
          # background fill, optional background image blit, overlay,
          # style pattern, and top accent bar on every page — work
          # that dominates the per-page cost (the "gradient" pattern
          # alone touches all 756,000 pixels in Crystal math).
          base_layer = nil
          if png_available
            base_layer = OgPngRenderer.build_base_layer(config, bg_abs_path, cached_bg)
          end

          img_dir = File.join(output_dir, ai.output_dir)
          Hwaro::Utils::FileSafe.mkdir_p(img_dir) unless Dir.exists?(img_dir)

          # Load manifest for incremental generation
          manifest_path = File.join(img_dir, ".og_manifest.json")
          config_hash = compute_config_hash(config)
          old_config_hash, old_entries = load_manifest(manifest_path)
          config_changed = old_config_hash != config_hash
          # In partial mode, start from the old manifest so a follow-up
          # call (e.g. the `--fast-start` deferred pass) doesn't truncate
          # the entries the previous call just wrote. In full mode we
          # truncate so entries for deleted pages don't accumulate
          # forever — the on-disk PNG/SVG for a removed page becomes
          # orphaned, and the manifest growing unbounded across builds
          # would defeat the cache-hit check by always "matching"
          # stale slugs. Config-changed always truncates.
          new_entries = if config_changed || !partial
                          {} of String => String
                        else
                          old_entries.dup
                        end

          generated = 0
          skipped = 0
          ext = (format == "png" && png_available) ? "png" : "svg"

          # Pass 1 (sequential): work out the slug, hash the page, and
          # short-circuit on a cache hit. The cache-hit path is just a
          # hash + stat + property assignment, far too cheap to be worth
          # parallelising. Only the cache-miss renders go into the
          # worker pool below.
          pending = [] of Tuple(Models::Page, String)
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

            page_hash = compute_page_hash(page)
            new_entries[slug] = page_hash

            expected_file = File.join(img_dir, "#{slug}.#{ext}")

            if !config_changed && old_entries[slug]? == page_hash && File.exists?(expected_file)
              page.image = "/#{ai.output_dir}/#{slug}.#{ext}"
              skipped += 1
              Logger.debug "  OG image: #{page.image} (cached)" if verbose
              next
            end

            pending << {page, slug}
          end

          # Pass 2 (parallel): render the cache-miss pages. Each worker
          # owns its own pixel buffer and file path so there is no
          # shared mutable state to guard. The stb bindings have no
          # global state, and `page.image = ...` writes only to a page
          # touched by exactly one worker. The font context, cached
          # logo/bg, and base layer are read-only after build.
          unless pending.empty?
            config_struct = Hwaro::Core::Build::ParallelConfig.new(enabled: parallel)
            processor = Hwaro::Core::Build::Parallel(Tuple(Models::Page, String), Bool).new(config_struct)
            results = processor.process(pending) do |item, _idx|
              page, slug = item
              if format == "png" && png_available
                png_filename = "#{slug}.png"
                png_path = File.join(img_dir, png_filename)
                if OgPngRenderer.render_png(page, config, png_path, logo_abs_path, bg_abs_path, font_ctx, cached_logo, cached_bg, base_layer)
                  page.image = "/#{ai.output_dir}/#{png_filename}"
                else
                  # Fallback to SVG on render failure
                  svg_filename = "#{slug}.svg"
                  svg = render_svg(page, config, logo_data_uri, bg_data_uri)
                  File.write(File.join(img_dir, svg_filename), svg)
                  page.image = "/#{ai.output_dir}/#{svg_filename}"
                  Logger.warn "  PNG render failed for #{slug}, falling back to SVG"
                end
              else
                svg_filename = "#{slug}.svg"
                svg = render_svg(page, config, logo_data_uri, bg_data_uri)
                File.write(File.join(img_dir, svg_filename), svg)
                page.image = "/#{ai.output_dir}/#{svg_filename}"
              end
              Logger.debug "  OG image: #{page.image}" if verbose

              # Cooperative yielding for responsiveness during heavy OG
              # generation (especially PNG) when running in a background
              # fiber (e.g. `serve --fast-start`).
              #
              # PNG rendering is pure CPU work and never yields by itself.
              # Without periodic yields, a saturated worker pool (or the
              # sequential path) can starve the main HTTP accept fiber.
              #
              # We batch the yields (every N renders) rather than yielding
              # after every single item. This significantly reduces
              # scheduler overhead while still giving other fibers regular
              # opportunities to run. The constant is defined at the top
              # of the class for easy tuning.
              if (_idx + 1) % PNG_YIELD_INTERVAL == 0
                Fiber.yield
              end
              true
            end
            generated = results.count(&.success)
          end

          save_manifest(manifest_path, config_hash, new_entries)

          if generated > 0 || skipped > 0
            Logger.info "  Generated #{generated} OG image(s)#{skipped > 0 ? ", skipped #{skipped} unchanged" : ""}"
          end

          {generated: generated, skipped: skipped}
        end

        # Render an SVG image for a page
        def self.render_svg(page : Models::Page, config : Models::Config, logo_data_uri : String? = nil, bg_data_uri : String? = nil) : String
          ai = config.og.auto_image
          bg = escape_attr(ai.background)
          text_color = escape_attr(ai.text_color)
          accent = escape_attr(ai.accent_color)
          secondary = escape_attr(resolve_secondary(ai))
          style = ai.style
          site_name = escape_xml(config.title)

          # Geometric styles get bolder default typography unless the user
          # explicitly raised the font size.
          font_size = Math.max(ai.font_size, 1)
          if ai.font_size <= 48
            case style
            when "brutalist" then font_size = 76
            when "band"      then font_size = 60
            when "split"     then font_size = 58
            end
          end
          desc_size = Math.max((font_size * 0.45).to_i, 1)

          # Per-style horizontal text box (left margin + wrap width).
          text_x = case style
                   when "split"     then SPLIT_TEXT_X
                   when "brutalist" then BRUTALIST_TEXT_X
                   else                  80
                   end
          text_w = case style
                   when "split"     then WIDTH - SPLIT_TEXT_X - 80
                   when "brutalist" then WIDTH - BRUTALIST_TEXT_X - (BRUTALIST_INSET + BRUTALIST_FRAME + 40)
                   else                  WIDTH - text_x - 80
                   end
          chars_per_line = Math.max((text_w / (font_size * 0.55)).to_i, 1)
          desc_chars = Math.max((text_w / (desc_size * 0.55)).to_i, 1)

          title_lines = word_wrap(page.title, chars_per_line)
          desc_lines = word_wrap(page.description || "", desc_chars)

          title_block_height = title_lines.size * (font_size + 8)
          desc_block_height = desc_lines.empty? ? 0 : desc_lines.size * (desc_size + 6)
          total_text_height = title_block_height + desc_block_height + 20

          # Per-style vertical placement + title color.
          title_fill = text_color
          case style
          when "band"
            title_fill = bg # knock the title out of the color band
            band_center = BAND_TOP + BAND_HEIGHT // 2
            title_start_y = band_center - title_block_height // 2 + font_size
          when "brutalist"
            title_start_y = BRUTALIST_INSET + BRUTALIST_FRAME + 100
          when "split"
            title_start_y = Math.max(font_size + 40, ((HEIGHT - total_text_height) / 2).to_i + font_size)
          else
            title_start_y = Math.max(font_size + 20, ((HEIGHT - total_text_height) / 2).to_i + font_size)
          end

          # Compute logo position
          logo_x, logo_y = logo_coordinates(ai.logo_position)

          # Build logo element
          logo_svg = ""
          if logo = ai.logo
            if logo_data_uri
              logo_svg = %(<image href="#{logo_data_uri}" x="#{logo_x}" y="#{logo_y}" width="#{LOGO_SIZE}" height="#{LOGO_SIZE}" />)
            else
              # Fallback: reference logo as URL (file not found or not pre-computed)
              logo_url = logo.lchop("static/")
              logo_url = logo_url.starts_with?("/") ? logo_url : "/#{logo_url}"
              logo_svg = %(<image href="#{escape_attr(logo_url)}" x="#{logo_x}" y="#{logo_y}" width="#{LOGO_SIZE}" height="#{LOGO_SIZE}" />)
            end
          end

          String.build do |svg|
            svg << %(<?xml version="1.0" encoding="UTF-8"?>\n)
            svg << %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" )
            svg << %(width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">\n)

            # Background
            svg << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{bg}" />\n)

            # Background image (if configured, using pre-computed data URI)
            if bg_data_uri
              svg << %(<image href="#{bg_data_uri}" x="0" y="0" width="#{WIDTH}" height="#{HEIGHT}" preserveAspectRatio="xMidYMid slice" />\n)
              svg << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{bg}" opacity="#{ai.overlay_opacity.clamp(0.0, 1.0)}" />\n)
            end

            # Classic background pattern (dots/grid/diagonal/gradient/waves)
            pattern_svg = render_style_pattern(style, accent, bg, ai.pattern_opacity, ai.pattern_scale)
            svg << pattern_svg unless pattern_svg.empty?

            # Bold geometric background (split / band / brutalist)
            geo_svg = render_style_background(style, accent, bg, secondary)
            svg << geo_svg unless geo_svg.empty?

            # Accent bar at top (skip for minimal / modern / geometric styles)
            unless no_accent_bars?(style)
              svg << %(<rect width="#{WIDTH}" height="6" fill="#{accent}" />\n)
            end

            # Title text
            title_lines.each_with_index do |line, i|
              y = title_start_y + i * (font_size + 8)
              svg << %(<text x="#{text_x}" y="#{y}" )
              svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
              svg << %(font-size="#{font_size}" font-weight="700" fill="#{title_fill}">)
              svg << escape_xml(line)
              svg << %(</text>\n)
            end

            # Description text
            unless desc_lines.empty?
              desc_start_y = style == "band" ? BAND_TOP + BAND_HEIGHT + desc_size + 24 : title_start_y + title_block_height + 16
              desc_lines.each_with_index do |line, i|
                y = desc_start_y + i * (desc_size + 6)
                svg << %(<text x="#{text_x}" y="#{y}" )
                svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
                svg << %(font-size="#{desc_size}" font-weight="400" fill="#{text_color}" opacity="0.78">)
                svg << escape_xml(line)
                svg << %(</text>\n)
              end
            end

            # Site name at bottom (controlled by show_title)
            if ai.show_title
              # `split` places the site name inside the accent block, so it
              # must use the readable text color rather than the accent.
              site_name_fill = style == "split" ? text_color : accent
              base_margin = case style
                            when "split"     then 80
                            when "brutalist" then BRUTALIST_TEXT_X
                            else                  LOGO_MARGIN
                            end
              site_name_x = if !logo_svg.empty? && ai.logo_position == "bottom-left"
                              base_margin + LOGO_SIZE + LOGO_TEXT_GAP
                            else
                              base_margin
                            end
              svg << %(<text x="#{site_name_x}" y="#{HEIGHT - 65}" )
              svg << %(font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" )
              svg << %(font-size="22" font-weight="600" fill="#{site_name_fill}">)
              svg << site_name
              svg << %(</text>\n)
            end

            # Logo
            svg << logo_svg << "\n" unless logo_svg.empty?

            # Bottom border (skip for minimal / modern / geometric styles)
            unless no_accent_bars?(style)
              svg << %(<rect y="#{HEIGHT - 6}" width="#{WIDTH}" height="6" fill="#{accent}" />\n)
            end

            svg << %(</svg>\n)
          end
        end

        # Render a bold geometric background (color block / band / framed panel)
        # for the design-forward geometric styles. Returns "" for other styles.
        def self.render_style_background(style : String, accent : String, bg : String, secondary : String) : String
          case style
          when "split"
            String.build do |s|
              # Diagonal accent color block on the left.
              s << %(<polygon points="0,0 #{SPLIT_TOP_X},0 #{SPLIT_BOTTOM_X},#{HEIGHT} 0,#{HEIGHT}" fill="#{accent}" />\n)
              # Secondary-color strip along the diagonal edge for a two-tone seam.
              s << %(<polygon points="#{SPLIT_TOP_X},0 #{SPLIT_TOP_X + SPLIT_EDGE},0 )
              s << %(#{SPLIT_BOTTOM_X + SPLIT_EDGE},#{HEIGHT} #{SPLIT_BOTTOM_X},#{HEIGHT}" fill="#{secondary}" />\n)
            end
          when "band"
            %(<rect x="0" y="#{BAND_TOP}" width="#{WIDTH}" height="#{BAND_HEIGHT}" fill="#{accent}" />\n)
          when "brutalist"
            iw = WIDTH - 2 * BRUTALIST_INSET
            ih = HEIGHT - 2 * BRUTALIST_INSET
            f = BRUTALIST_FRAME
            String.build do |s|
              # Hard offset shadow block (secondary), peeking down-right.
              s << %(<rect x="#{BRUTALIST_INSET + BRUTALIST_OFFSET}" y="#{BRUTALIST_INSET + BRUTALIST_OFFSET}" )
              s << %(width="#{iw}" height="#{ih}" fill="#{secondary}" />\n)
              # Main panel (background color) covers the shadow's top-left.
              s << %(<rect x="#{BRUTALIST_INSET}" y="#{BRUTALIST_INSET}" width="#{iw}" height="#{ih}" fill="#{bg}" />\n)
              # Thick accent border, inset by half the stroke width.
              s << %(<rect x="#{BRUTALIST_INSET + f // 2}" y="#{BRUTALIST_INSET + f // 2}" )
              s << %(width="#{iw - f}" height="#{ih - f}" fill="none" stroke="#{accent}" stroke-width="#{f}" />\n)
            end
          else
            ""
          end
        end

        # Render a style/pattern SVG snippet based on the configured style
        def self.render_style_pattern(style : String, accent : String, bg : String, opacity : Float64, scale : Float64) : String
          opacity = opacity.clamp(0.0, 1.0)
          scale = Math.max(scale, 0.1)

          case style
          when "dots"
            spacing = Math.max((20 * scale).to_i, 1)
            radius = Math.max((3 * scale).to_i, 1)
            String.build do |s|
              s << %(<defs><pattern id="dots" width="#{spacing}" height="#{spacing}" patternUnits="userSpaceOnUse">)
              s << %(<circle cx="#{spacing // 2}" cy="#{spacing // 2}" r="#{radius}" fill="#{accent}" />)
              s << %(</pattern></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#dots)" opacity="#{opacity}" />\n)
            end
          when "grid"
            spacing = Math.max((40 * scale).to_i, 1)
            String.build do |s|
              s << %(<defs><pattern id="grid" width="#{spacing}" height="#{spacing}" patternUnits="userSpaceOnUse">)
              s << %(<path d="M #{spacing} 0 L 0 0 0 #{spacing}" fill="none" stroke="#{accent}" stroke-width="1" />)
              s << %(</pattern></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#grid)" opacity="#{opacity}" />\n)
            end
          when "diagonal"
            spacing = Math.max((20 * scale).to_i, 1)
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
        def self.file_to_data_uri(file_path : String) : String
          ext = File.extname(file_path).downcase
          mime = MIME_TYPES[ext]? || "application/octet-stream"
          data = File.open(file_path, "rb", &.getb_to_end)
          encoded = Base64.strict_encode(data)
          "data:#{mime};base64,#{encoded}"
        end

        # Compute logo (x, y) for a given position string.
        # Shared by both SVG and PNG renderers.
        def self.logo_coordinates(position : String) : Tuple(Int32, Int32)
          case position
          when "bottom-right" then {WIDTH - LOGO_MARGIN - LOGO_SIZE, HEIGHT - LOGO_BOTTOM_OFFSET}
          when "top-left"     then {LOGO_MARGIN, LOGO_TOP_Y}
          when "top-right"    then {WIDTH - LOGO_MARGIN - LOGO_SIZE, LOGO_TOP_Y}
          else                     {LOGO_MARGIN, HEIGHT - LOGO_BOTTOM_OFFSET} # bottom-left
          end
        end

        # Word-wrap text to fit within a character limit per line.
        # Handles CJK characters (which have no spaces) by allowing
        # breaks between any CJK characters.
        private def self.word_wrap(text : String, max_chars : Int32) : Array(String)
          return [] of String if text.empty?
          max_chars = 10 if max_chars < 10 # safety minimum

          segments = split_into_segments(text)
          lines = [] of String
          current_line = ""

          segments.each do |seg|
            if current_line.empty?
              current_line = seg
            elsif (current_line.size + seg.size) <= max_chars
              current_line += seg
            else
              lines << current_line.strip
              current_line = seg.lstrip
            end

            # Break long segments (e.g., very long words) at max_chars
            while current_line.size > max_chars
              lines << current_line[0, max_chars].strip
              current_line = current_line[max_chars..]
            end
          end

          lines << current_line.strip unless current_line.strip.empty?
          lines.first(4)
        end

        # Split text into wrappable segments: whitespace-separated words
        # for Latin text, individual characters for CJK ranges.
        # Public so OgPngRenderer can reuse it.
        def self.split_into_segments(text : String) : Array(String)
          segments = [] of String
          buf = IO::Memory.new

          text.each_char do |char|
            if cjk_char?(char)
              if buf.size > 0
                segments << buf.to_s
                buf = IO::Memory.new
              end
              segments << char.to_s
            elsif char.whitespace?
              if buf.size > 0
                segments << buf.to_s
                buf = IO::Memory.new
              end
              segments << char.to_s
            else
              buf << char
            end
          end

          segments << buf.to_s if buf.size > 0
          segments
        end

        # Check if a character is in CJK Unicode ranges
        private def self.cjk_char?(char : Char) : Bool
          code = char.ord
          (code >= 0x4E00 && code <= 0x9FFF) ||   # CJK Unified Ideographs
            (code >= 0x3400 && code <= 0x4DBF) || # CJK Extension A
            (code >= 0x3000 && code <= 0x303F) || # CJK Symbols and Punctuation
            (code >= 0x3040 && code <= 0x309F) || # Hiragana
            (code >= 0x30A0 && code <= 0x30FF) || # Katakana
            (code >= 0xAC00 && code <= 0xD7AF) || # Hangul Syllables
            (code >= 0xFF00 && code <= 0xFFEF)    # Fullwidth Forms
        end

        # Compute a hash of OG-relevant config properties.
        def self.compute_config_hash(config : Models::Config) : String
          ai = config.og.auto_image
          Digest::SHA256.hexdigest(
            "#{config.title}|#{ai.background}|#{ai.text_color}|#{ai.accent_color}|" \
            "#{ai.secondary_color}|#{ai.font_size}|#{ai.logo}|#{ai.logo_position}|#{ai.show_title}|" \
            "#{ai.style}|#{ai.pattern_opacity}|#{ai.pattern_scale}|" \
            "#{ai.background_image}|#{ai.overlay_opacity}|#{ai.format}|#{ai.font_path}"
          )
        end

        # Compute a hash of page content that affects OG image rendering.
        def self.compute_page_hash(page : Models::Page) : String
          Digest::SHA256.hexdigest("#{page.title}|#{page.description}|#{page.url}")
        end

        # Load the OG manifest file. Returns {config_hash, entries}.
        def self.load_manifest(manifest_path : String) : Tuple(String, Hash(String, String))
          return {"", {} of String => String} unless File.exists?(manifest_path)
          data = JSON.parse(File.read(manifest_path))
          config_hash = data["config_hash"]?.try(&.as_s?) || ""
          entries = {} of String => String
          if e = data["entries"]?.try(&.as_h?)
            e.each do |k, v|
              if str = v.as_s?
                entries[k] = str
              end
            end
          end
          {config_hash, entries}
        rescue ex : JSON::ParseException | IO::Error
          Logger.debug "OG manifest load failed (#{manifest_path}): #{ex.message}"
          {"", {} of String => String}
        end

        # Save the OG manifest file.
        def self.save_manifest(manifest_path : String, config_hash : String, entries : Hash(String, String))
          json = JSON.build do |j|
            j.object do
              j.field "version", 1
              j.field "config_hash", config_hash
              j.field "entries" do
                j.object do
                  entries.each { |k, v| j.field k, v }
                end
              end
            end
          end
          File.write(manifest_path, json)
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
