# Config section — [og] and [og.auto_image].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # Auto-generated OG image configuration
    class AutoImageConfig
      property enabled : Bool
      property background : String
      property text_color : String
      property accent_color : String

      # Optional second color for two-tone geometric styles (split / brutalist).
      # When nil, a complementary tone is auto-derived from accent_color.
      property secondary_color : String?

      property font_size : Int32
      property logo : String?
      property output_dir : String
      property show_title : Bool
      property style : String
      property pattern_opacity : Float64
      property pattern_scale : Float64
      property background_image : String?
      property overlay_opacity : Float64
      property format : String
      property font_path : String?
      property logo_position : String

      # Controls a semi-transparent panel behind the title/description area.
      # Higher values make text more readable on busy/artistic backgrounds
      # while still letting the background show through (0.0 = disabled).
      # Modern editorial/brand styles benefit from 0.25~0.45.
      property text_panel : Float64

      # Whether to draw the thin top/bottom accent bars using accent_color.
      # These are the classic "old school" OG accent lines, drawn for the
      # pattern styles (default / dots / grid / diagonal / gradient / waves).
      # Off by default for a cleaner, more modern look; set to true to opt in.
      property accent_bars : Bool

      # If true, skip automatic OG image generation during `hwaro serve`.
      # Images will be generated on-demand the first time they are requested
      # from the dev server. Greatly improves initial serve time on large sites.
      property lazy_generate : Bool

      def initialize
        @enabled = false
        # Ember identity defaults (warm charcoal / warm off-white / ember),
        # matching the scaffold and docs design tokens.
        @background = "#171310"
        @text_color = "#f4ede4"
        @accent_color = "#ec7a66"
        @secondary_color = nil
        @font_size = 48
        @logo = nil
        @output_dir = "og-images"
        @show_title = true
        @style = "default"
        # Peak alpha for the pattern styles — each pattern applies its own
        # internal falloff, so this is visible without being loud.
        @pattern_opacity = 0.35
        @pattern_scale = 1.0
        @background_image = nil
        @overlay_opacity = 0.45
        # PNG is the default because social platforms (Facebook, X/Twitter,
        # LinkedIn, Slack, Discord, iMessage) do not render SVG og:image —
        # an SVG preview silently shows nothing. Generation falls back to SVG
        # automatically if PNG font initialization is unavailable.
        @format = "png"
        @font_path = nil
        @logo_position = "bottom-left"
        @text_panel = 0.0
        @accent_bars = false
        @lazy_generate = false
      end
    end

    # OpenGraph and Twitter Card configuration
    class OpenGraphConfig
      property default_image : String?
      property twitter_card : String
      property twitter_site : String?
      property twitter_creator : String?
      property fb_app_id : String?
      property og_type : String
      property auto_image : AutoImageConfig

      def initialize
        @default_image = nil
        @twitter_card = "summary_large_image"
        @twitter_site = nil
        @twitter_creator = nil
        @fb_app_id = nil
        @og_type = "article"
        @auto_image = AutoImageConfig.new
      end

      # Append a single conditional `<meta>` line (leading newline + 2-space
      # indent) for the OG/Twitter tag builders.
      private def append_meta(str, attr : String, name : String, value : String)
        str << %(\n  <meta #{attr}="#{name}" content="#{Utils::TextUtils.escape_xml(value)}">)
      end

      # Generate OG meta tags.
      #
      # `og_type_override` lets the renderer force `og:type="website"` for
      # the homepage, section indexes, taxonomy listings, and the 404
      # page — the configured `@og_type` ("article" by default) only fits
      # content pages. See render.cr's `og_type_for` helper (gh#522).
      def og_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
        og_type_override : String? = nil,
      ) : String
        og_type = og_type_override || @og_type
        # Subsequent lines are joined with `\n  ` so the rendered output
        # keeps the same 2-space indent the scaffold templates use for the
        # `{{ og_all_tags }}` line. Without this, only the first tag picks
        # up the template's indent and the rest start at column 0.
        String.build(256) do |str|
          str << %(<meta property="og:title" content="#{Utils::TextUtils.escape_xml(title)}">\n  )
          str << %(<meta property="og:type" content="#{Utils::TextUtils.escape_xml(og_type)}">\n  )
          # Percent-encode the path like feeds/sitemap do, so a non-ASCII URL
          # (e.g. a Unicode taxonomy term) yields one consistent RFC 3986
          # URL across every surface instead of raw UTF-8 here only.
          str << %(<meta property="og:url" content="#{Utils::TextUtils.escape_xml(base_url)}#{Utils::TextUtils.escape_xml(Utils::TextUtils.encode_url_path(url))}">)
          if desc = description
            append_meta(str, "property", "og:description", desc)
          end
          if img_url = resolve_image_url(image, base_url)
            append_meta(str, "property", "og:image", img_url)
          end
          if fb_id = @fb_app_id
            append_meta(str, "property", "fb:app_id", fb_id)
          end
        end
      end

      # Generate Twitter Card meta tags
      def twitter_tags(
        title : String,
        description : String?,
        image : String?,
        base_url : String,
      ) : String
        # A "summary_large_image" card with no image renders as a blank preview
        # on most platforms, so downgrade to the plain "summary" card when this
        # page resolves to no image (e.g. auto OG images disabled and no
        # per-page or default image set).
        img_url = resolve_image_url(image, base_url)
        card = (@twitter_card == "summary_large_image" && img_url.nil?) ? "summary" : @twitter_card

        # See `og_tags` above for why subsequent lines are pre-indented.
        String.build(256) do |str|
          str << %(<meta name="twitter:card" content="#{Utils::TextUtils.escape_xml(card)}">\n  )
          str << %(<meta name="twitter:title" content="#{Utils::TextUtils.escape_xml(title)}">)
          if desc = description
            append_meta(str, "name", "twitter:description", desc)
          end
          if img_url
            append_meta(str, "name", "twitter:image", img_url)
          end
          if site = @twitter_site
            append_meta(str, "name", "twitter:site", site)
          end
          if creator = @twitter_creator
            append_meta(str, "name", "twitter:creator", creator)
          end
        end
      end

      # Resolve an image path to an absolute URL, falling back to default_image.
      # A value that already carries its own origin (any `scheme:` URL, or a
      # protocol-relative `//cdn.example.com/og.png`) is returned untouched:
      # the old `starts_with?("http")` test sent `//cdn…` down the
      # root-relative branch and emitted `https://site.com//cdn.example.com/og.png`
      # as og:image, while a relative path merely starting with the letters
      # "http" (`http-guide/cover.png`) was left relative — invalid for OG.
      def resolve_image_url(image : String?, base_url : String) : String?
        img = image || @default_image
        return unless img
        return img if Content::Processors::InternalLinkResolver.has_own_origin?(img)
        "#{base_url}#{img.starts_with?("/") ? img : "/#{img}"}"
      end

      # Generate both OG and Twitter tags
      def all_tags(
        title : String,
        description : String?,
        url : String,
        image : String?,
        base_url : String,
        og_type_override : String? = nil,
      ) : String
        og = og_tags(title, description, url, image, base_url, og_type_override)
        twitter = twitter_tags(title, description, image, base_url)
        Models.join_tags(og, twitter)
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_og(config : Config)
        return unless s = config.raw["og"]?.try(&.as_h?)

        config.og.default_image = s["default_image"]?.try(&.as_s?)
        config.og.twitter_card = s["twitter_card"]?.try(&.as_s?) || config.og.twitter_card
        config.og.twitter_site = s["twitter_site"]?.try(&.as_s?)
        config.og.twitter_creator = s["twitter_creator"]?.try(&.as_s?)
        config.og.fb_app_id = s["fb_app_id"]?.try(&.as_s?)
        config.og.og_type = s["type"]?.try(&.as_s?) || config.og.og_type

        if ai = s["auto_image"]?.try(&.as_h?)
          config.og.auto_image.enabled = bool_value(ai["enabled"]?, config.og.auto_image.enabled)
          config.og.auto_image.background = ai["background"]?.try(&.as_s?) || config.og.auto_image.background
          config.og.auto_image.text_color = ai["text_color"]?.try(&.as_s?) || config.og.auto_image.text_color
          config.og.auto_image.accent_color = ai["accent_color"]?.try(&.as_s?) || config.og.auto_image.accent_color
          config.og.auto_image.secondary_color = ai["secondary_color"]?.try(&.as_s?)
          # Clamp to the OG canvas: og_image.cr hands this straight to
          # stb_truetype as the glyph pixel scale, and a value far past the
          # 1200x630 canvas (150000 was the observed threshold) makes
          # stbtt_Rasterize write past its glyph bitmap — an out-of-bounds C
          # write that takes the process down with SIGSEGV, or kills `hwaro
          # serve` outright on one request when `lazy_generate` is on. A glyph
          # taller than the image can never render usefully, so 630 is both the
          # safe bound and the last visually meaningful one. The low bound is
          # cosmetic: og_image.cr replaces anything <= 48 with a style default.
          config.og.auto_image.font_size = int_value(ai["font_size"]?, config.og.auto_image.font_size).clamp(8, 630)
          config.og.auto_image.logo = ai["logo"]?.try(&.as_s?)
          config.og.auto_image.output_dir = ai["output_dir"]?.try(&.as_s?) || config.og.auto_image.output_dir
          config.og.auto_image.show_title = bool_value(ai["show_title"]?, config.og.auto_image.show_title)
          config.og.auto_image.style = ai["style"]?.try(&.as_s?) || config.og.auto_image.style
          # Opacity-style floats share pattern_scale's hazard below: TOML
          # accepts `nan`/`inf` literals, NaN survives the renderer's
          # clamp(0.0, 1.0) (NaN comparisons are all false), and the pixel
          # blend's `.to_u8` then raises OverflowError, aborting the build.
          # A non-finite value falls back to the field's default.
          po = float_value(ai["pattern_opacity"]?, config.og.auto_image.pattern_opacity)
          config.og.auto_image.pattern_opacity = po.finite? ? po : config.og.auto_image.pattern_opacity
          # Clamp to a sane range: the pattern renderer multiplies scale into
          # Int32 expressions (e.g. (80 * scale).to_i), so a huge value overflows
          # Int32 and crashes OG generation. 0.1..10.0 covers every visible scale;
          # a non-finite (nan) value falls back to the default.
          ps = float_value(ai["pattern_scale"]?, config.og.auto_image.pattern_scale)
          config.og.auto_image.pattern_scale = ps.finite? ? ps.clamp(0.1, 10.0) : 1.0
          config.og.auto_image.background_image = ai["background_image"]?.try(&.as_s?)
          oo = float_value(ai["overlay_opacity"]?, config.og.auto_image.overlay_opacity)
          config.og.auto_image.overlay_opacity = oo.finite? ? oo : config.og.auto_image.overlay_opacity
          config.og.auto_image.format = ai["format"]?.try(&.as_s?) || config.og.auto_image.format
          config.og.auto_image.font_path = ai["font_path"]?.try(&.as_s?)
          if lp = ai["logo_position"]?.try(&.as_s?)
            if {"bottom-left", "bottom-right", "top-left", "top-right"}.includes?(lp)
              config.og.auto_image.logo_position = lp
            end
          end
          tp = float_value(ai["text_panel"]?, config.og.auto_image.text_panel)
          config.og.auto_image.text_panel = tp.finite? ? tp : config.og.auto_image.text_panel
          config.og.auto_image.accent_bars = bool_value(ai["accent_bars"]?, config.og.auto_image.accent_bars)
          config.og.auto_image.lazy_generate = bool_value(ai["lazy_generate"]?, config.og.auto_image.lazy_generate)
        end
      end
    end
  end
end
