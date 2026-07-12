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

        # Emit the "CJK text but no CJK font" advisory at most once per process
        # (the generate hook can run multiple times — e.g. --fast-start's
        # deferred pass, or every rebuild in `serve`).
        @@cjk_font_warning_shown = false

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
        # background shapes (color blocks, bands, frames). "Signature" styles
        # render a complete, self-contained composition (terminal window,
        # bauhaus shapes, halftone fade) and ignore the soft text panel.
        MODERN_STYLES    = {"editorial", "framed", "artistic", "hero", "surreal", "monument"}
        GEOMETRIC_STYLES = {"split", "band", "brutalist"}
        SIGNATURE_STYLES = {"terminal", "bauhaus", "halftone"}

        def self.modern?(style : String) : Bool
          MODERN_STYLES.includes?(style)
        end

        def self.geometric?(style : String) : Bool
          GEOMETRIC_STYLES.includes?(style)
        end

        def self.signature?(style : String) : Bool
          SIGNATURE_STYLES.includes?(style)
        end

        # Styles that drop the classic thin top/bottom accent bars for a
        # cleaner, more modern composition.
        def self.no_accent_bars?(style : String) : Bool
          style == "minimal" || modern?(style) || geometric?(style) || signature?(style)
        end

        # --- Shared typographic design system (SVG + PNG renderers) ---
        # One margin grid, one line-height model, one description hierarchy,
        # and one brand treatment — so the styles differ in composition, not
        # in sloppy metrics.
        MARGIN_X        =   80 # base left/right text margin (matches LOGO_MARGIN)
        TITLE_LINE_H    = 1.12 # title line height as a multiple of font_size
        DESC_RATIO      = 0.42 # desc font size = font_size * DESC_RATIO
        DESC_LINE_H     = 1.45 # desc line height as a multiple of desc size
        DESC_OPACITY    = 0.62 # quiet description hierarchy
        TITLE_MAX_LINES =    3 # capped with a visible ellipsis
        DESC_MAX_LINES  =    2

        # Brand row: a small accent tick + the site name in text color.
        BRAND_SIZE     = 24
        BRAND_TICK_W   =  5
        BRAND_TICK_H   = 24
        BRAND_GAP      = 14 # gap between the tick and the site name
        BRAND_BASELINE = HEIGHT - 64

        # Bump to invalidate incremental OG caches when the renderer's
        # design changes without any config change (it feeds
        # compute_config_hash). rev 2: 2026-07 typography + style redesign.
        RENDER_REVISION = 2

        # `default` ("masthead"): eyebrow on top, title anchored high.
        MASTHEAD_EYEBROW_Y    =  96 # eyebrow baseline
        MASTHEAD_EYEBROW_SIZE =  20
        MASTHEAD_TITLE_TOP    = 210

        # `dots`: corner-weighted halftone fade; text sits lower-left.
        DOTS_TITLE_TOP = 330

        # `waves`: text centers over the calm region above the tide bands.
        WAVES_TEXT_REGION_H = 410

        # `grid` ("blueprint"): focal crosshair + registration marks.
        GRID_FOCAL_X =  56
        GRID_FOCAL_Y = 470

        # `diagonal`: stripe wedge in the bottom-right corner triangle
        # (DIAG_WEDGE_X0, HEIGHT) - (WIDTH, HEIGHT) - (WIDTH, DIAG_WEDGE_Y1).
        DIAG_WEDGE_X0 = 700
        DIAG_WEDGE_Y1 = 150

        # `editorial` ("magazine front"): hairline rules + kicker.
        EDITORIAL_RULE_X0     =   80
        EDITORIAL_RULE_X1     = 1120
        EDITORIAL_RULE_TOP    =   84
        EDITORIAL_RULE_BOT    =  546
        EDITORIAL_KICKER_Y    =  132 # kicker baseline
        EDITORIAL_KICKER_SIZE =   19
        EDITORIAL_TITLE_TOP   =  190

        # `monument`: accent rule ABOVE the title, brand row bottom-right.
        MONUMENT_TITLE_TOP   =  250
        MONUMENT_RULE_Y      =  208
        MONUMENT_RULE_W      =   64
        MONUMENT_RULE_H      =    6
        MONUMENT_BRAND_RIGHT = 1120

        # --- Geometric style layout (shared by SVG + PNG so both stay in sync) ---
        # `split`: a diagonal color block on the left; text lives on the right.
        SPLIT_TOP_X    = 480 # block's right edge at the top
        SPLIT_BOTTOM_X = 320 # block's right edge at the bottom (slanted)
        SPLIT_EDGE     =  16 # secondary-color accent strip along the diagonal
        SPLIT_TEXT_X   = 540 # left margin of the title/description block

        # `band`: a full-width solid band behind the (knocked-out) title,
        # echoed by a thin secondary band above it.
        BAND_TOP      = 210
        BAND_HEIGHT   = 200
        BAND_ECHO_H   =   8
        BAND_ECHO_GAP =  22

        # `framed` ("invitation card"): a neutral hairline frame + accent
        # corner brackets; the only centered composition.
        FRAMED_INSET         =  26
        FRAMED_WIDTH         =   1
        FRAMED_BRACKET_INSET =  44
        FRAMED_BRACKET_ARM   =  40
        FRAMED_BRACKET_W     =   3
        FRAMED_WRAP_W        = 880
        FRAMED_TITLE_TOP     = 250
        FRAMED_BRAND_Y       = HEIGHT - 88

        # `brutalist`: thick framed panel with a hard offset shadow block.
        BRUTALIST_INSET  = 36 # gap from the canvas edge to the panel
        BRUTALIST_FRAME  = 14 # border thickness
        BRUTALIST_OFFSET = 20 # hard shadow offset (down-right)
        BRUTALIST_TEXT_X = 88 # left margin of the title inside the frame

        # `terminal`: a code-editor window with a title bar + traffic lights.
        TERMINAL_INSET      =  36                               # window inset from the canvas edge
        TERMINAL_RADIUS     =  18                               # window corner radius
        TERMINAL_BAR_H      =  64                               # title-bar height
        TERMINAL_TEXT_X     = 110                               # left margin of the prompt/title inside the window
        TERMINAL_LIGHTS     = {"#ff5f57", "#febc2e", "#28c840"} # classic traffic lights
        TERMINAL_GHOST_ROWS = {300, 440, 240}                   # widths of the faint "output" skeleton rows

        # `bauhaus`: flat geometric art composition on the right side.
        BAUHAUS_TEXT_X =  90
        BAUHAUS_TEXT_W = 600 # wrap width so the title clears the shapes

        # `halftone`: print-style dot field growing toward the right edge.
        HALFTONE_TEXT_X  =  90
        HALFTONE_TEXT_W  = 620
        HALFTONE_FIELD_X = 660 # dots begin here and grow rightward

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

        # Rotate a hex color's hue by `degrees`, optionally forcing a minimum
        # saturation so derived tones stay vivid on flat compositions.
        def self.shift_hue(hex : String, degrees : Float64, min_sat : Float64 = 0.0) : String
          h, s, l = hex_to_hsl(hex)
          hsl_to_hex(h + degrees, Math.max(s, min_sat), l)
        end

        # Lighten (positive delta) or darken (negative) a hex color in HSL space.
        def self.adjust_lightness(hex : String, delta : Float64) : String
          h, s, l = hex_to_hsl(hex)
          hsl_to_hex(h, s, (l + delta).clamp(0.0, 1.0))
        end

        # Normalize a user-supplied hex color to a bare 6-digit "rrggbb" form.
        # Accepts "#rgb" shorthand (expanded to "rrggbb"), "#rrggbb", and
        # "#rrggbbaa" (alpha is dropped). Returns nil for anything that isn't
        # a valid hex color so callers can fall back deterministically.
        def self.normalize_hex(hex : String) : String?
          h = hex.lchop("#").strip
          case h.size
          when 3
            h = String.build { |s| h.each_char { |c| s << c << c } }
          when 6
            # already the canonical length
          when 8
            h = h[0, 6] # drop the alpha byte
          else
            return
          end
          h.matches?(/\A[0-9a-fA-F]{6}\z/) ? h : nil
        end

        # Convert "#RRGGBB" to {hue(0-360), saturation(0-1), lightness(0-1)}.
        def self.hex_to_hsl(hex : String) : Tuple(Float64, Float64, Float64)
          h = normalize_hex(hex)
          return {0.0, 0.0, 0.0} unless h
          r = h[0, 2].to_i(16) / 255.0
          g = h[2, 2].to_i(16) / 255.0
          b = h[4, 2].to_i(16) / 255.0
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
            # Does any page need CJK glyph coverage? If so, prefer a CJK-capable
            # system font (which also covers Latin) so titles don't render as
            # blank "tofu" boxes. A user-set font_path always takes precedence.
            needs_cjk = ai.font_path.nil? &&
                        pages.any? { |p| contains_cjk?(p.title) || contains_cjk?(p.description || "") }

            font_ctx = OgPngRenderer.load_fonts(ai.font_path, prefer_cjk: needs_cjk)
            png_available = !font_ctx.nil?
            unless png_available
              Logger.warn "  PNG format requested but font initialization failed. Falling back to SVG."
            end

            # Warn only when CJK text is present but no CJK-capable font could be
            # found on the system (and the user set no font_path) — i.e. when we
            # genuinely can't avoid the blank "tofu" boxes.
            if png_available && needs_cjk && !@@cjk_font_warning_shown &&
               OgPngRenderer.find_cjk_font.nil?
              @@cjk_font_warning_shown = true
              Logger.warn "  OG images: page titles/descriptions contain CJK characters, " \
                          "but no CJK-capable system font was found — they will render " \
                          "as blank boxes. Set [og.auto_image].font_path to a CJK-capable font " \
                          "(e.g. Noto Sans CJK)."
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
          # slug => page.url that owns it, so colliding slugs get disambiguated.
          seen_slugs = {} of String => String
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

            # The gsub("/", "-") collapses distinct URLs that differ only in
            # slash-vs-hyphen placement (e.g. /posts/foo/ and /posts-foo/) onto
            # the same slug. Left unresolved, the second page overwrites the
            # first's manifest entry and both Pass-2 workers issue a concurrent
            # File.write to the SAME .png/.svg path (torn file under -Dpreview_mt),
            # and one page advertises an OG image rendered for the other. Append
            # a short stable hash of the URL so each distinct URL owns a path.
            if (owner = seen_slugs[slug]?) && owner != page.url
              slug = "#{slug}-#{Digest::SHA256.hexdigest(page.url)[0, 8]}"
            end
            seen_slugs[slug] = page.url

            page_hash = compute_page_hash(page)
            new_entries[slug] = page_hash

            expected_png = File.join(img_dir, "#{slug}.png")
            expected_svg = File.join(img_dir, "#{slug}.svg")

            if !config_changed && old_entries[slug]? == page_hash
              if ext == "png" && File.exists?(expected_png)
                page.image = "/#{ai.output_dir}/#{slug}.png"
                skipped += 1
                Logger.debug "  OG image: #{page.image} (cached)" if verbose
                next
              elsif ext == "svg" && File.exists?(expected_svg)
                # SVG-mode build (PNG unavailable or format=svg): a previously
                # emitted SVG is a valid hit. Gated on ext=="svg" so that when
                # PNG becomes available again (ext flips to "png") a page that
                # only has a stale SVG falls through to re-render as PNG instead
                # of being pinned to the old SVG.
                page.image = "/#{ai.output_dir}/#{slug}.svg"
                skipped += 1
                Logger.debug "  OG image: #{page.image} (cached, svg)" if verbose
                next
              end
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
            # Surface render/I-O failures (e.g. File.write raising on disk full /
            # permission). Without this, an exception is swallowed by the worker
            # pool, page.image stays nil (no og:image tag), and the only signal
            # is a silently lower "Generated N" count.
            results.each do |result|
              next if result.success
              failed_slug = pending[result.index]?.try(&.[1])
              Logger.warn "  OG image generation failed for #{failed_slug || "page ##{result.index}"}: #{result.error}"
            end
            generated = results.count(&.success)
          end

          save_manifest(manifest_path, config_hash, new_entries)

          if generated > 0 || skipped > 0
            Logger.info "  Generated #{generated} OG image(s)#{skipped > 0 ? ", skipped #{skipped} unchanged" : ""}"
          end

          {generated: generated, skipped: skipped}
        end

        # Font stacks for the SVG fallback renderer. They lead with the
        # bundled brand faces so environments that have them render in
        # parity with the PNG output, then degrade gracefully.
        SVG_DISPLAY_FONT = "'Space Grotesk', 'DejaVu Sans', system-ui, -apple-system, sans-serif"
        SVG_MONO_FONT    = "'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace"

        # Render an SVG image for a page
        def self.render_svg(page : Models::Page, config : Models::Config, logo_data_uri : String? = nil, bg_data_uri : String? = nil) : String
          ai = config.og.auto_image
          bg = escape_attr(ai.background)
          text_color = escape_attr(ai.text_color)
          accent = escape_attr(ai.accent_color)
          secondary = escape_attr(resolve_secondary(ai))
          style = ai.style
          site_name = escape_xml(config.title)

          # Style-tuned default type scale unless the user raised it explicitly.
          font_size = Math.max(ai.font_size, 1)
          if ai.font_size <= 48
            font_size = case style
                        when "monument"          then 84
                        when "hero", "brutalist" then 78
                        when "artistic", "surreal", "bauhaus", "halftone", "minimal"
                          64
                        when "band"     then 60
                        when "split"    then 58
                        when "terminal" then 54
                        else                 56
                        end
          end
          desc_size = Math.max((font_size * DESC_RATIO).to_i, 1)
          title_line_h = (font_size * TITLE_LINE_H).to_i
          desc_line_h = (desc_size * DESC_LINE_H).to_i

          # `terminal` prefixes the title with an accent "$" prompt; the title
          # block shifts right by this advance on every line.
          prompt_advance = style == "terminal" ? (font_size * 0.9).to_i : 0

          # Per-style horizontal text box (left margin + wrap width).
          text_x = case style
                   when "split"                       then SPLIT_TEXT_X
                   when "brutalist"                   then BRUTALIST_TEXT_X
                   when "terminal"                    then TERMINAL_TEXT_X
                   when "bauhaus"                     then BAUHAUS_TEXT_X
                   when "halftone"                    then HALFTONE_TEXT_X
                   when "artistic", "hero", "surreal" then 140
                   else                                    MARGIN_X
                   end
          text_w = case style
                   when "split"                       then WIDTH - SPLIT_TEXT_X - 80
                   when "brutalist"                   then WIDTH - BRUTALIST_TEXT_X - (BRUTALIST_INSET + BRUTALIST_FRAME + 40)
                   when "terminal"                    then WIDTH - TERMINAL_TEXT_X * 2 - prompt_advance
                   when "bauhaus"                     then BAUHAUS_TEXT_W
                   when "halftone"                    then HALFTONE_TEXT_W
                   when "framed"                      then FRAMED_WRAP_W
                   when "artistic", "hero", "surreal" then WIDTH - 280
                   else                                    Math.min(WIDTH - text_x - 80, 980)
                   end
          chars_per_line = Math.max((text_w / (font_size * 0.55)).to_i, 1)
          desc_chars = Math.max((text_w / (desc_size * 0.55)).to_i, 1)

          title_lines = balanced_word_wrap(page.title, chars_per_line)
          # The band style draws the title inside a fixed-height color band;
          # cap the lines so a long title can't overflow the band invisibly.
          title_cap = case style
                      when "monument" then 2
                      when "band"     then band_line_capacity(font_size)
                      else                 TITLE_MAX_LINES
                      end
          title_lines = cap_lines(title_lines, title_cap)
          desc_lines = word_wrap(page.description || "", desc_chars)
          desc_lines = cap_lines(desc_lines, style == "monument" ? 1 : DESC_MAX_LINES)

          title_block_height = title_lines.size * title_line_h
          desc_gap = (font_size * 0.55).to_i
          desc_block_height = desc_lines.empty? ? 0 : desc_lines.size * desc_line_h
          total_text_height = title_block_height + (desc_lines.empty? ? 0 : desc_gap + desc_block_height)

          # Per-style vertical placement + title color. `title_start_y` is
          # the baseline of the first title line.
          title_fill = text_color
          case style
          when "default"
            title_start_y = MASTHEAD_TITLE_TOP + font_size
          when "dots"
            title_start_y = DOTS_TITLE_TOP + font_size
          when "waves"
            title_start_y = Math.max(font_size + 20, ((WAVES_TEXT_REGION_H - total_text_height) / 2).to_i + font_size)
          when "editorial"
            title_start_y = EDITORIAL_TITLE_TOP + font_size
          when "framed"
            title_start_y = FRAMED_TITLE_TOP + font_size
          when "band"
            title_fill = bg # knock the title out of the color band
            band_center = BAND_TOP + BAND_HEIGHT // 2
            title_start_y = band_center - title_block_height // 2 + font_size - 6
          when "brutalist"
            title_start_y = BRUTALIST_INSET + BRUTALIST_FRAME + 100
          when "split"
            title_start_y = Math.max(font_size + 40, ((HEIGHT - total_text_height) / 2).to_i + font_size - 10)
          when "hero"
            title_start_y = Math.max(font_size + 20, 180)
          when "monument"
            title_start_y = MONUMENT_TITLE_TOP + font_size
          when "artistic", "surreal"
            title_start_y = Math.max(font_size + 48, ((HEIGHT - total_text_height) / 2).to_i + font_size - 28)
          when "terminal"
            # Anchored near the top of the window content area, prompt-style.
            title_start_y = TERMINAL_INSET + TERMINAL_BAR_H + 60 + font_size
          else
            title_start_y = Math.max(font_size + 20, ((HEIGHT - total_text_height) / 2).to_i + font_size)
          end

          # Thin top/bottom accent bars are opt-in via `accent_bars` and are
          # never drawn for minimal / modern / geometric styles. Mirrors the
          # PNG renderer so both formats stay in sync.
          show_accent_bars = ai.accent_bars && !no_accent_bars?(style)

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

          title_font = style == "terminal" ? SVG_MONO_FONT : SVG_DISPLAY_FONT

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

            # Classic background pattern (dots/grid/diagonal/waves)
            pattern_svg = render_style_pattern(style, accent, bg, ai.pattern_opacity, ai.pattern_scale)
            svg << pattern_svg unless pattern_svg.empty?

            # Per-style signature background (color blocks, gradient, glow, frame)
            has_bg = !bg_data_uri.nil?
            geo_svg = render_style_background(style, accent, bg, secondary, has_bg)
            svg << geo_svg unless geo_svg.empty?

            # Hero: oversized "ghost" echo of the title's first word behind
            # the composition for poster-style depth. Kept on-canvas and
            # width-capped so a long first word can't run off both sides.
            if style == "hero"
              if ghost = page.title.split(/\s+/).first?
                unless ghost.empty?
                  ghost_size = (font_size * 2.6).to_i
                  approx_w = (ghost.size * ghost_size * 0.62).to_i
                  ghost_size = (ghost_size * 1500.0 / approx_w).to_i if approx_w > 1500
                  ghost_top = Math.max(title_start_y - (font_size * 2.35).to_i, 16)
                  svg << %(<text x="#{text_x - 10}" y="#{ghost_top + (ghost_size * 0.78).to_i}" )
                  svg << %(font-family="#{SVG_DISPLAY_FONT}" )
                  svg << %(font-size="#{ghost_size}" font-weight="700" letter-spacing="4" fill="#{text_color}" opacity="0.06">)
                  svg << escape_xml(ghost.upcase)
                  svg << %(</text>\n)
                end
              end
            end

            # Legibility scrim behind text over generated gradient/glow backdrops.
            if !has_bg && (style == "artistic" || style == "hero" || style == "surreal")
              scrim_top = (title_start_y - font_size - 28).clamp(0, HEIGHT)
              scrim_h = total_text_height + 56
              svg << %(<rect x="0" y="#{scrim_top}" width="#{WIDTH}" height="#{scrim_h}" fill="#{bg}" opacity="0.34" />\n)
            end

            # Accent bar at top (opt-in; skipped for minimal / modern / geometric)
            if show_accent_bars
              svg << %(<rect width="#{WIDTH}" height="6" fill="#{accent}" />\n)
            end

            # `default` masthead: uppercase tracked site-name eyebrow at the
            # top (an accent tick stands in when the site name is hidden).
            if style == "default"
              if ai.show_title && !site_name.empty?
                svg << %(<text x="#{MARGIN_X}" y="#{MASTHEAD_EYEBROW_Y}" font-family="#{SVG_DISPLAY_FONT}" )
                svg << %(font-size="#{MASTHEAD_EYEBROW_SIZE}" font-weight="700" letter-spacing="2" fill="#{accent}">)
                svg << site_name.upcase
                svg << %(</text>\n)
              else
                svg << %(<rect x="#{MARGIN_X}" y="#{MASTHEAD_EYEBROW_Y - 6}" width="48" height="6" fill="#{accent}" />\n)
              end
            end

            # Editorial: uppercase tracked kicker between the hairline rules.
            if style == "editorial" && ai.show_title && !site_name.empty?
              svg << %(<text x="#{MARGIN_X}" y="#{EDITORIAL_KICKER_Y}" font-family="#{SVG_DISPLAY_FONT}" )
              svg << %(font-size="#{EDITORIAL_KICKER_SIZE}" font-weight="700" letter-spacing="2" fill="#{accent}">)
              svg << site_name.upcase
              svg << %(</text>\n)
            end

            # Terminal: accent "$" prompt on the first title line.
            if style == "terminal"
              svg << %(<text x="#{text_x}" y="#{title_start_y}" )
              svg << %(font-family="#{SVG_MONO_FONT}" )
              svg << %(font-size="#{font_size}" font-weight="700" fill="#{accent}">$</text>\n)
            end

            # Title text. `framed` centers every line; `monument` sets tight
            # tracking.
            title_text_x = text_x + prompt_advance
            title_anchor = style == "framed" ? %( text-anchor="middle") : ""
            title_tracking = style == "monument" ? %( letter-spacing="-1") : ""
            title_lines.each_with_index do |line, i|
              y = title_start_y + i * title_line_h
              x = style == "framed" ? WIDTH // 2 : title_text_x
              svg << %(<text x="#{x}" y="#{y}"#{title_anchor}#{title_tracking} )
              svg << %(font-family="#{title_font}" )
              svg << %(font-size="#{font_size}" font-weight="700" fill="#{title_fill}">)
              svg << escape_xml(line)
              # Terminal: blinking-cursor block after the last title line.
              if style == "terminal" && i == title_lines.size - 1
                svg << %(<tspan fill="#{accent}">&#x2588;</tspan>)
              end
              svg << %(</text>\n)
            end

            # Minimal: an accent full stop after the last title line.
            if style == "minimal" && !title_lines.empty?
              r = Math.max((font_size * 0.11).to_i, 3)
              last_line = title_lines.last
              approx_w = (last_line.size * font_size * 0.52).to_i
              dot_cx = text_x + approx_w + (font_size * 0.18).to_i + r
              dot_cy = title_start_y + (title_lines.size - 1) * title_line_h - r
              svg << %(<circle cx="#{dot_cx}" cy="#{dot_cy}" r="#{r}" fill="#{accent}" />\n)
            end

            # Editorial: thin vertical accent rule, cap-height aligned.
            if style == "editorial"
              rule_top = title_start_y - (font_size * 0.72).to_i
              rule_h = (title_lines.size - 1) * title_line_h + (font_size * 0.72).to_i
              svg << %(<rect x="#{text_x - 28}" y="#{rule_top}" width="4" height="#{rule_h}" fill="#{accent}" />\n)
            end

            # Description text (terminal indents it under the prompt's title)
            desc_last_y = title_start_y + (title_lines.size - 1) * title_line_h
            unless desc_lines.empty?
              desc_start_y = style == "band" ? BAND_TOP + BAND_HEIGHT + desc_size + 24 : desc_last_y + desc_gap + desc_size
              desc_opacity = (style == "hero" || style == "monument") ? 0.45 : DESC_OPACITY
              desc_anchor = style == "framed" ? %( text-anchor="middle") : ""
              desc_x = style == "framed" ? WIDTH // 2 : title_text_x
              desc_lines.each_with_index do |line, i|
                y = desc_start_y + i * desc_line_h
                svg << %(<text x="#{desc_x}" y="#{y}"#{desc_anchor} )
                svg << %(font-family="#{SVG_DISPLAY_FONT}" )
                svg << %(font-size="#{desc_size}" font-weight="500" fill="#{text_color}" opacity="#{desc_opacity}">)
                svg << escape_xml(line)
                svg << %(</text>\n)
              end
              desc_last_y = desc_start_y + (desc_lines.size - 1) * desc_line_h
            end

            # Terminal: faint "output" skeleton rows under the text.
            if style == "terminal"
              rows_top = desc_last_y + 44
              TERMINAL_GHOST_ROWS.each_with_index do |w, i|
                ry = rows_top + i * 32
                break if ry + 10 > HEIGHT - TERMINAL_INSET - 24
                svg << %(<rect x="#{TERMINAL_TEXT_X}" y="#{ry}" width="#{w}" height="10" rx="5" fill="#{text_color}" opacity="0.08" />\n)
              end
            end

            # Site name / brand row. Several styles relocate it: terminal
            # puts it in the window title bar, default/editorial replace it
            # with the eyebrow/kicker, monument right-aligns it, framed
            # centers it. Everything else gets the accent tick + name row.
            if ai.show_title && !site_name.empty?
              case style
              when "default", "editorial"
                # handled above (eyebrow / kicker)
              when "terminal"
                bar_text_y = TERMINAL_INSET + 2 + TERMINAL_BAR_H // 2 + 7
                svg << %(<text x="#{WIDTH // 2}" y="#{bar_text_y}" text-anchor="middle" )
                svg << %(font-family="#{SVG_MONO_FONT}" font-size="20" font-weight="700" fill="#{text_color}" opacity="0.5">)
                svg << site_name
                svg << %(</text>\n)
              when "monument"
                approx_w = (config.title.size * BRAND_SIZE * 0.6).to_i
                tick_x = MONUMENT_BRAND_RIGHT - approx_w - BRAND_TICK_W - BRAND_GAP
                svg << %(<rect x="#{tick_x}" y="#{BRAND_BASELINE - BRAND_TICK_H + 4}" width="#{BRAND_TICK_W}" height="#{BRAND_TICK_H}" fill="#{accent}" />\n)
                svg << %(<text x="#{MONUMENT_BRAND_RIGHT}" y="#{BRAND_BASELINE}" text-anchor="end" )
                svg << %(font-family="#{SVG_DISPLAY_FONT}" font-size="#{BRAND_SIZE}" font-weight="700" letter-spacing="1" fill="#{text_color}" opacity="0.92">)
                svg << site_name
                svg << %(</text>\n)
              when "framed"
                svg << %(<text x="#{WIDTH // 2}" y="#{FRAMED_BRAND_Y}" text-anchor="middle" )
                svg << %(font-family="#{SVG_DISPLAY_FONT}" font-size="#{BRAND_SIZE}" font-weight="700" letter-spacing="1" fill="#{text_color}" opacity="0.7">)
                svg << site_name
                svg << %(</text>\n)
              else
                base_margin = case style
                              when "split"                       then 80
                              when "brutalist"                   then BRUTALIST_TEXT_X
                              when "bauhaus", "halftone"         then BAUHAUS_TEXT_X
                              when "artistic", "surreal", "hero" then 140
                              else                                    LOGO_MARGIN
                              end
                site_name_x = if !logo_svg.empty? && ai.logo_position == "bottom-left"
                                base_margin + LOGO_SIZE + LOGO_TEXT_GAP
                              else
                                base_margin
                              end
                row_opacity = style == "minimal" ? 0.5 : 0.92
                if style == "split"
                  # Inside the accent block an accent tick would vanish — name only.
                  svg << %(<text x="#{site_name_x}" y="#{BRAND_BASELINE}" )
                  svg << %(font-family="#{SVG_DISPLAY_FONT}" font-size="#{BRAND_SIZE}" font-weight="700" letter-spacing="1" fill="#{text_color}">)
                  svg << site_name
                  svg << %(</text>\n)
                else
                  svg << %(<rect x="#{site_name_x}" y="#{BRAND_BASELINE - BRAND_TICK_H + 4}" width="#{BRAND_TICK_W}" height="#{BRAND_TICK_H}" fill="#{accent}" opacity="#{row_opacity}" />\n)
                  svg << %(<text x="#{site_name_x + BRAND_TICK_W + BRAND_GAP}" y="#{BRAND_BASELINE}" )
                  svg << %(font-family="#{SVG_DISPLAY_FONT}" font-size="#{BRAND_SIZE}" font-weight="700" letter-spacing="1" fill="#{text_color}" opacity="#{row_opacity}">)
                  svg << site_name
                  svg << %(</text>\n)
                end
              end
            end

            # Logo
            svg << logo_svg << "\n" unless logo_svg.empty?

            # Bottom border (opt-in; skipped for minimal / modern / geometric)
            if show_accent_bars
              svg << %(<rect y="#{HEIGHT - 6}" width="#{WIDTH}" height="6" fill="#{accent}" />\n)
            end

            svg << %(</svg>\n)
          end
        end

        # Render each style's signature background: bold geometric shapes
        # (split / band / brutalist) plus generated backdrops for the modern
        # styles (artistic gradient, hero glow, surreal aurora, framed frame).
        # The generated modern backdrops are skipped when a background image is
        # present so a user photo shows through. Returns "" for plain styles.
        def self.render_style_background(style : String, accent : String, bg : String, secondary : String, has_bg_image : Bool = false) : String
          case style
          when "default"
            # Masthead: a low corner glow + gentle vignette for depth.
            return "" if has_bg_image
            String.build do |s|
              s << %(<defs><radialGradient id="ogMastGlow" gradientUnits="userSpaceOnUse" cx="1160" cy="700" r="720">)
              s << %(<stop offset="0%" stop-color="#{accent}" stop-opacity="0.14" /><stop offset="100%" stop-color="#{accent}" stop-opacity="0" /></radialGradient>)
              s << vignette_def("ogMastVig", 0.12)
              s << %(</defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogMastGlow)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogMastVig)" />\n)
            end
          when "gradient"
            # Duotone wash: accent-tinted diagonal gradient + corner glow +
            # vignette + grain — real depth instead of a fade-to-nothing.
            return "" if has_bg_image
            c1 = adjust_lightness(mix_hex(bg, accent, 0.45), -0.06)
            c2 = adjust_lightness(bg, -0.03)
            String.build do |s|
              s << %(<defs><linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">)
              s << %(<stop offset="0%" stop-color="#{c1}" /><stop offset="100%" stop-color="#{c2}" /></linearGradient>)
              s << %(<radialGradient id="ogGradGlow" gradientUnits="userSpaceOnUse" cx="140" cy="640" r="560">)
              s << %(<stop offset="0%" stop-color="#{accent}" stop-opacity="0.2" /><stop offset="100%" stop-color="#{accent}" stop-opacity="0" /></radialGradient>)
              s << vignette_def("ogGradVig", 0.15)
              s << grain_filter_def
              s << %(</defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#grad)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogGradGlow)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogGradVig)" />\n)
              s << grain_rect
            end
          when "editorial"
            # Magazine front: quiet hairline rules above and below the
            # content area.
            rule = neutral_line_hex(bg)
            String.build do |s|
              s << %(<rect x="#{EDITORIAL_RULE_X0}" y="#{EDITORIAL_RULE_TOP}" width="#{EDITORIAL_RULE_X1 - EDITORIAL_RULE_X0}" height="1" fill="#{rule}" />\n)
              s << %(<rect x="#{EDITORIAL_RULE_X0}" y="#{EDITORIAL_RULE_BOT}" width="#{EDITORIAL_RULE_X1 - EDITORIAL_RULE_X0}" height="1" fill="#{rule}" />\n)
            end
          when "monument"
            # A short accent rule ABOVE the title; the whitespace is the design.
            %(<rect x="#{MARGIN_X}" y="#{MONUMENT_RULE_Y}" width="#{MONUMENT_RULE_W}" height="#{MONUMENT_RULE_H}" fill="#{accent}" />\n)
          when "artistic"
            return "" if has_bg_image
            # Mesh-gradient color field: diagonal base + analogous-hue color
            # blobs + a dark anchor for text legibility + film grain.
            a2 = shift_hue(accent, 28.0)
            s2 = shift_hue(secondary, -20.0)
            String.build do |s|
              s << %(<defs><linearGradient id="ogGrad" x1="0%" y1="0%" x2="100%" y2="100%">)
              s << %(<stop offset="0%" stop-color="#{accent}" /><stop offset="100%" stop-color="#{secondary}" />)
              s << %(</linearGradient>)
              s << %(<radialGradient id="ogM1" cx="18%" cy="10%" r="55%"><stop offset="0%" stop-color="#{a2}" stop-opacity="0.8" /><stop offset="100%" stop-color="#{a2}" stop-opacity="0" /></radialGradient>)
              s << %(<radialGradient id="ogM2" cx="88%" cy="90%" r="60%"><stop offset="0%" stop-color="#{s2}" stop-opacity="0.7" /><stop offset="100%" stop-color="#{s2}" stop-opacity="0" /></radialGradient>)
              s << %(<radialGradient id="ogM3" cx="50%" cy="115%" r="75%"><stop offset="0%" stop-color="#{bg}" stop-opacity="0.85" /><stop offset="100%" stop-color="#{bg}" stop-opacity="0" /></radialGradient>)
              s << grain_filter_def
              s << %(</defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogGrad)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogM1)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogM2)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogM3)" />\n)
              s << grain_rect
            end
          when "hero"
            return "" if has_bg_image
            String.build do |s|
              s << %(<defs><radialGradient id="ogGlow" cx="50%" cy="37%" r="60%">)
              s << %(<stop offset="0%" stop-color="#{accent}" stop-opacity="0.6" />)
              s << %(<stop offset="100%" stop-color="#{accent}" stop-opacity="0" />)
              s << %(</radialGradient>)
              s << %(<radialGradient id="ogGlow2" cx="88%" cy="95%" r="55%">)
              s << %(<stop offset="0%" stop-color="#{secondary}" stop-opacity="0.22" />)
              s << %(<stop offset="100%" stop-color="#{secondary}" stop-opacity="0" />)
              s << %(</radialGradient>)
              s << grain_filter_def
              s << %(</defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogGlow)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogGlow2)" />\n)
              s << grain_rect
            end
          when "surreal"
            return "" if has_bg_image
            # Aurora: soft orbs plus blurred ribbon bands flowing across.
            a3 = shift_hue(accent, 40.0)
            String.build do |s|
              s << %(<defs>)
              s << %(<radialGradient id="ogO1" cx="25%" cy="30%" r="42%"><stop offset="0%" stop-color="#{accent}" stop-opacity="0.55" /><stop offset="100%" stop-color="#{accent}" stop-opacity="0" /></radialGradient>)
              s << %(<radialGradient id="ogO2" cx="80%" cy="62%" r="46%"><stop offset="0%" stop-color="#{secondary}" stop-opacity="0.5" /><stop offset="100%" stop-color="#{secondary}" stop-opacity="0" /></radialGradient>)
              s << %(<radialGradient id="ogO3" cx="52%" cy="95%" r="45%"><stop offset="0%" stop-color="#{a3}" stop-opacity="0.35" /><stop offset="100%" stop-color="#{a3}" stop-opacity="0" /></radialGradient>)
              s << %(<filter id="ogBlur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="18" /></filter>)
              s << grain_filter_def
              s << %(</defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogO1)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogO2)" />\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogO3)" />\n)
              s << %(<path d="M -60 250 C 280 160, 580 320, 880 230 S 1180 180, 1280 220" fill="none" stroke="#{accent}" stroke-width="60" opacity="0.3" filter="url(#ogBlur)" />\n)
              s << %(<path d="M -60 420 C 240 340, 540 500, 840 410 S 1160 350, 1280 410" fill="none" stroke="#{secondary}" stroke-width="90" opacity="0.25" filter="url(#ogBlur)" />\n)
              s << grain_rect
            end
          when "terminal"
            render_terminal_window(bg, has_bg_image)
          when "bauhaus"
            # Flat geometric art composition on the right: circle, dot,
            # triangle, quarter disc — layered in accent/secondary/derived.
            tertiary = shift_hue(accent, 60.0, 0.45)
            String.build do |s|
              s << %(<circle cx="940" cy="190" r="220" fill="#{accent}" />\n)
              s << %(<circle cx="690" cy="150" r="30" fill="#{secondary}" />\n)
              s << %(<polygon points="690,500 830,260 970,500" fill="#{tertiary}" />\n)
              s << %(<path d="M 1200 630 L 1200 320 A 310 310 0 0 0 890 630 Z" fill="#{secondary}" />\n)
            end
          when "halftone"
            render_halftone_field(accent)
          when "framed"
            # Invitation card: a neutral hairline frame plus accent corner
            # brackets inset from it.
            rule = neutral_line_hex(bg)
            bi = FRAMED_BRACKET_INSET
            arm = FRAMED_BRACKET_ARM
            bw = FRAMED_BRACKET_W
            String.build do |s|
              s << %(<rect x="#{FRAMED_INSET}" y="#{FRAMED_INSET}" width="#{WIDTH - 2 * FRAMED_INSET}" height="#{HEIGHT - 2 * FRAMED_INSET}" fill="none" stroke="#{rule}" stroke-width="#{FRAMED_WIDTH}" />\n)
              # Corner brackets: two rects per corner.
              s << %(<g fill="#{accent}">)
              s << %(<rect x="#{bi}" y="#{bi}" width="#{arm}" height="#{bw}" /><rect x="#{bi}" y="#{bi}" width="#{bw}" height="#{arm}" />)
              s << %(<rect x="#{WIDTH - bi - arm}" y="#{bi}" width="#{arm}" height="#{bw}" /><rect x="#{WIDTH - bi - bw}" y="#{bi}" width="#{bw}" height="#{arm}" />)
              s << %(<rect x="#{bi}" y="#{HEIGHT - bi - bw}" width="#{arm}" height="#{bw}" /><rect x="#{bi}" y="#{HEIGHT - bi - arm}" width="#{bw}" height="#{arm}" />)
              s << %(<rect x="#{WIDTH - bi - arm}" y="#{HEIGHT - bi - bw}" width="#{arm}" height="#{bw}" /><rect x="#{WIDTH - bi - bw}" y="#{HEIGHT - bi - arm}" width="#{bw}" height="#{arm}" />)
              s << %(</g>\n)
            end
          when "split"
            String.build do |s|
              # Diagonal accent color block on the left.
              s << %(<polygon points="0,0 #{SPLIT_TOP_X},0 #{SPLIT_BOTTOM_X},#{HEIGHT} 0,#{HEIGHT}" fill="#{accent}" />\n)
              # Secondary-color strip along the diagonal edge for a two-tone seam.
              s << %(<polygon points="#{SPLIT_TOP_X},0 #{SPLIT_TOP_X + SPLIT_EDGE},0 )
              s << %(#{SPLIT_BOTTOM_X + SPLIT_EDGE},#{HEIGHT} #{SPLIT_BOTTOM_X},#{HEIGHT}" fill="#{secondary}" />\n)
            end
          when "band"
            # A thin muted echo band above the main band for print feel.
            String.build do |s|
              s << %(<rect x="0" y="#{BAND_TOP - BAND_ECHO_GAP}" width="#{WIDTH}" height="#{BAND_ECHO_H}" fill="#{accent}" opacity="0.4" />\n)
              s << %(<rect x="0" y="#{BAND_TOP}" width="#{WIDTH}" height="#{BAND_HEIGHT}" fill="#{accent}" />\n)
            end
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

        # Deterministic film-grain filter definition (shared by the modern
        # generated backdrops). Breaks up gradient banding and adds texture.
        private def self.grain_filter_def : String
          %(<filter id="ogGrain" x="0%" y="0%" width="100%" height="100%">) +
            %(<feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" seed="7" stitchTiles="stitch" />) +
            %(<feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0.6 0.6 0.6 0 0" />) +
            %(</filter>)
        end

        private def self.grain_rect : String
          %(<rect width="#{WIDTH}" height="#{HEIGHT}" filter="url(#ogGrain)" opacity="0.16" />\n)
        end

        # Corner-darkening vignette as a radial gradient definition
        # (transparent center, black edges). `strength` is the corner opacity.
        private def self.vignette_def(id : String, strength : Float64) : String
          %(<radialGradient id="#{id}" cx="50%" cy="50%" r="75%">) +
            %(<stop offset="0%" stop-color="#000000" stop-opacity="0" />) +
            %(<stop offset="55%" stop-color="#000000" stop-opacity="0" />) +
            %(<stop offset="100%" stop-color="#000000" stop-opacity="#{strength}" />) +
            %(</radialGradient>)
        end

        # Mix two hex colors in RGB space (`t` toward `other`). Mirrors the
        # PNG renderer's lerp_color so gradient stops match across formats.
        def self.mix_hex(base : String, other : String, t : Float64) : String
          b = normalize_hex(base) || "000000"
          o = normalize_hex(other) || "000000"
          t = t.clamp(0.0, 1.0)
          ch = {0, 2, 4}.map do |i|
            bv = b[i, 2].to_i(16)
            ov = o[i, 2].to_i(16)
            (bv + (ov - bv) * t).round.to_i.clamp(0, 255)
          end
          "#%02x%02x%02x" % {ch[0], ch[1], ch[2]}
        end

        # `terminal`: code-editor window — rounded panel, title bar with
        # traffic lights, faint scanlines. Slightly translucent over a photo.
        private def self.render_terminal_window(bg : String, has_bg_image : Bool) : String
          inset = TERMINAL_INSET
          win_w = WIDTH - 2 * inset
          win_h = HEIGHT - 2 * inset
          bar_h = TERMINAL_BAR_H
          window = adjust_lightness(bg, 0.045)
          bar = adjust_lightness(bg, 0.085)
          border = adjust_lightness(bg, 0.16)
          fill_opacity = has_bg_image ? 0.88 : 1.0

          String.build do |s|
            s << %(<defs><pattern id="ogScan" width="4" height="4" patternUnits="userSpaceOnUse">)
            s << %(<rect width="4" height="1" fill="#000000" /></pattern></defs>\n)
            # Window panel with border.
            s << %(<rect x="#{inset}" y="#{inset}" width="#{win_w}" height="#{win_h}" rx="#{TERMINAL_RADIUS}" )
            s << %(fill="#{window}" fill-opacity="#{fill_opacity}" stroke="#{border}" stroke-width="2" />\n)
            # Title bar (rounded top corners, square bottom).
            s << %(<rect x="#{inset + 1}" y="#{inset + 1}" width="#{win_w - 2}" height="#{bar_h}" rx="#{TERMINAL_RADIUS - 1}" fill="#{bar}" />\n)
            s << %(<rect x="#{inset + 1}" y="#{inset + 1 + bar_h // 2}" width="#{win_w - 2}" height="#{bar_h - bar_h // 2}" fill="#{bar}" />\n)
            s << %(<rect x="#{inset + 1}" y="#{inset + bar_h}" width="#{win_w - 2}" height="2" fill="#{border}" />\n)
            # Traffic lights.
            TERMINAL_LIGHTS.each_with_index do |color, i|
              s << %(<circle cx="#{inset + 40 + i * 34}" cy="#{inset + bar_h // 2}" r="11" fill="#{color}" />\n)
            end
            # Faint scanlines in the content area for a subtle CRT feel.
            s << %(<rect x="#{inset + 2}" y="#{inset + bar_h + 6}" width="#{win_w - 4}" height="#{win_h - bar_h - 10}" fill="url(#ogScan)" opacity="0.05" />\n)
          end
        end

        # `halftone`: print-style dot field — dots grow toward the right
        # edge, rows staggered like a press halftone screen, with a gentle
        # vertical cosine weight so the field breathes instead of tiling.
        private def self.render_halftone_field(accent : String) : String
          spacing = 28
          max_r = 15.0
          field_w = (WIDTH - HALFTONE_FIELD_X).to_f
          mid_y = HEIGHT / 2.0
          String.build do |s|
            row = 0
            y = spacing // 2
            while y < HEIGHT
              x_off = row.odd? ? spacing // 2 : 0
              x = HALFTONE_FIELD_X + x_off
              breath = 0.65 + 0.35 * Math.cos((y - mid_y) / mid_y * Math::PI / 2.0)
              while x < WIDTH + spacing
                tx = ((x - HALFTONE_FIELD_X).to_f / field_w).clamp(0.0, 1.0)
                r = max_r * (tx ** 1.6) * breath
                if r >= 1.0
                  s << %(<circle cx="#{x}" cy="#{y}" r="#{r.round(1)}" fill="#{accent}" opacity="0.92" />\n)
                end
                x += spacing
              end
              y += spacing
              row += 1
            end
          end
        end

        # Render a style/pattern SVG snippet based on the configured style.
        # Every pattern is a composition with a focal point rather than
        # uniform wallpaper; `opacity` acts as the peak alpha with internal
        # falloff. Mirrors the PNG renderer's render_pattern.
        def self.render_style_pattern(style : String, accent : String, bg : String, opacity : Float64, scale : Float64) : String
          opacity = opacity.clamp(0.0, 1.0)
          scale = Math.max(scale, 0.1)

          case style
          when "dots"
            # Corner-weighted halftone fade: staggered dots grow and
            # brighten toward the top-right focal corner.
            spacing = Math.max((26 * scale).to_i, 4)
            String.build do |s|
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
                  if r >= 0.8 && alpha > 0.004
                    s << %(<circle cx="#{x}" cy="#{y}" r="#{r.round(1)}" fill="#{accent}" opacity="#{alpha.round(3)}" />\n)
                  end
                  x += spacing
                end
                y += spacing
                row += 1
              end
            end
          when "grid"
            # Blueprint: a fine quiet grid plus one focal crosshair with
            # registration marks.
            spacing = Math.max((48 * scale).to_i, 8)
            minor = (opacity * 0.4).clamp(0.0, 1.0)
            focal = (opacity * 1.3).clamp(0.0, 1.0)
            String.build do |s|
              s << %(<defs><pattern id="grid" width="#{spacing}" height="#{spacing}" patternUnits="userSpaceOnUse">)
              s << %(<path d="M #{spacing} 0 L 0 0 0 #{spacing}" fill="none" stroke="#{accent}" stroke-width="1" />)
              s << %(</pattern></defs>\n)
              s << %(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#grid)" opacity="#{minor}" />\n)
              s << %(<rect x="#{GRID_FOCAL_X}" y="0" width="1" height="#{HEIGHT}" fill="#{accent}" opacity="#{focal}" />\n)
              s << %(<rect x="0" y="#{GRID_FOCAL_Y}" width="#{WIDTH}" height="1" fill="#{accent}" opacity="#{focal}" />\n)
              s << %(<circle cx="#{GRID_FOCAL_X}" cy="#{GRID_FOCAL_Y}" r="7" fill="#{accent}" opacity="#{(opacity * 2.0).clamp(0.0, 1.0)}" />\n)
              s << %(<rect x="435" y="#{GRID_FOCAL_Y - 5}" width="10" height="10" fill="none" stroke="#{accent}" stroke-width="1" />\n)
            end
          when "diagonal"
            # 45° stripes clipped to the bottom-right corner wedge with an
            # alpha ramp from the hypotenuse to the corner, plus an accent
            # rule along the hypotenuse.
            mid_x = (DIAG_WEDGE_X0 + WIDTH) // 2
            mid_y = (HEIGHT + DIAG_WEDGE_Y1) // 2
            String.build do |s|
              s << %(<defs>)
              s << %(<pattern id="diagonal" width="26" height="26" patternUnits="userSpaceOnUse" patternTransform="rotate(-45)">)
              s << %(<rect x="0" y="0" width="10" height="26" fill="#{accent}" /></pattern>)
              s << %(<linearGradient id="ogWedgeGrad" gradientUnits="userSpaceOnUse" x1="#{mid_x}" y1="#{mid_y}" x2="#{WIDTH}" y2="#{HEIGHT}">)
              s << %(<stop offset="0%" stop-color="#ffffff" stop-opacity="0" /><stop offset="100%" stop-color="#ffffff" stop-opacity="1" /></linearGradient>)
              s << %(<mask id="ogWedgeMask"><rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ogWedgeGrad)" /></mask>)
              s << %(</defs>\n)
              s << %(<polygon points="#{DIAG_WEDGE_X0},#{HEIGHT} #{WIDTH},#{HEIGHT} #{WIDTH},#{DIAG_WEDGE_Y1}" fill="url(#diagonal)" mask="url(#ogWedgeMask)" opacity="#{opacity}" />\n)
              s << %(<line x1="#{DIAG_WEDGE_X0}" y1="#{HEIGHT}" x2="#{WIDTH}" y2="#{DIAG_WEDGE_Y1}" stroke="#{accent}" stroke-width="3" opacity="#{(opacity * 1.4).clamp(0.0, 1.0)}" />\n)
            end
          when "waves"
            # Layered tide bands anchored to the bottom edge (closed filled
            # paths sampled from the same sine curves the PNG renderer uses).
            String.build do |s|
              bands = {
                {430.0, 26.0, 1050.0, 0.0, shift_hue(accent, -16.0), opacity * 0.35},
                {474.0, 34.0, 800.0, 1.9, accent, opacity * 0.5},
                {522.0, 22.0, 1250.0, 4.1, shift_hue(accent, 18.0), opacity * 0.75},
              }
              bands.each do |base_y, amp, wavelength, phase, color, alpha|
                s << %(<path d="M -20 #{HEIGHT} L -20 #{(base_y + Math.sin(-20.0 * Math::PI * 2.0 / wavelength + phase) * amp).round(1)})
                x = 0
                while x <= WIDTH + 20
                  yv = base_y + Math.sin(x.to_f * Math::PI * 2.0 / wavelength + phase) * amp
                  s << %( L #{x} #{yv.round(1)})
                  x += 24
                end
                s << %( L #{WIDTH + 20} #{HEIGHT} Z" fill="#{color}" opacity="#{alpha.clamp(0.0, 1.0).round(3)}" />\n)
              end
            end
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
          lines
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

        # True if the text contains CJK ideographs, kana, hangul, or fullwidth
        # forms — glyphs the bundled/system Latin fonts cannot render, so PNG
        # OG images would show blank "tofu" boxes unless a CJK-capable
        # `font_path` is configured.
        def self.contains_cjk?(text : String) : Bool
          text.each_char.any? { |c| cjk_char?(c) }
        end

        # How many title lines fit inside the fixed-height color band used by
        # the `band` style. Beyond this the title overflows the band and, being
        # drawn in the background color, renders invisibly off-band.
        def self.band_line_capacity(font_size : Int32) : Int32
          Math.max(1, (BAND_HEIGHT / (font_size * TITLE_LINE_H)).to_i)
        end

        # Cap `lines` to `max`, marking the last kept line with an ellipsis
        # so the truncation is visible rather than silent.
        def self.cap_lines(lines : Array(String), max : Int32) : Array(String)
          return lines if lines.size <= max
          capped = lines.first(max)
          capped[-1] = "#{capped[-1].rstrip}…"
          capped
        end

        # Cap a `band`-style title to the lines that fit the band.
        def self.cap_band_title(lines : Array(String), font_size : Int32) : Array(String)
          cap_lines(lines, band_line_capacity(font_size))
        end

        # A quiet hairline color derived from the background: slightly
        # lighter on dark backgrounds, slightly darker on light ones.
        def self.neutral_line_hex(bg_hex : String) : String
          _, _, l = hex_to_hsl(bg_hex)
          adjust_lightness(bg_hex, l > 0.5 ? -0.30 : 0.32)
        end

        # Balanced title wrap (character-count analog of the PNG renderer's
        # measured version): greedy wrap first; when the last line is an
        # orphan (much shorter than the longest line), re-wrap against a
        # tighter target so line lengths even out. Only accepted when it
        # does not add lines.
        def self.balanced_word_wrap(text : String, max_chars : Int32) : Array(String)
          lines = word_wrap(text, max_chars)
          return lines if lines.size < 2 || lines.size > 3
          longest = lines.max_of(&.size)
          return lines if longest <= 0 || lines.last.size >= longest * 0.55
          target = Math.max((lines.sum(&.size) / lines.size * 1.08).to_i, (longest * 0.6).to_i)
          rebalanced = word_wrap(text, target)
          rebalanced.size <= lines.size ? rebalanced : lines
        end

        # Compute a hash of OG-relevant config properties. RENDER_REVISION
        # is folded in so a renderer design change regenerates cached images
        # on existing sites even though no config value changed.
        def self.compute_config_hash(config : Models::Config) : String
          ai = config.og.auto_image
          Digest::SHA256.hexdigest(
            "#{config.title}|#{ai.background}|#{ai.text_color}|#{ai.accent_color}|" \
            "#{ai.secondary_color}|#{ai.font_size}|#{ai.logo}|#{ai.logo_position}|#{ai.show_title}|" \
            "#{ai.style}|#{ai.pattern_opacity}|#{ai.pattern_scale}|" \
            "#{ai.background_image}|#{ai.overlay_opacity}|#{ai.format}|#{ai.font_path}|" \
            "#{ai.accent_bars}|#{ai.text_panel}|" \
            "#{asset_digest(ai.logo)}|#{asset_digest(ai.background_image)}|" \
            "r#{RENDER_REVISION}" # pixel-affecting; changing them must invalidate the cache
          )
        end

        # Content digest of an on-disk asset (logo / background image).
        # Replacing the file at the same path must invalidate cached OG
        # images — hashing only the path string left stale logos baked into
        # cached images forever.
        def self.asset_digest(path : String?) : String
          return "" unless path
          abs = path.starts_with?("/") ? path : File.join(Dir.current, path)
          return "" unless File.exists?(abs)
          Digest::SHA256.new.file(abs).hexfinal
        rescue IO::Error
          ""
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
