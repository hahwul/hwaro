# Color values for SassScript.
#
# The v2 subset had no color model at all: `#336699` lexed as `Raw` token
# soup and `darken($c, 10%)` fell through `reconstruct_call`, emitting the
# literal text `darken(#336699, 10%)` — invalid CSS that browsers drop
# silently. This module adds the value type and the math behind
# `sass:color`.
#
# Byte-compat rule: a color written in the source keeps its exact spelling
# (`lexeme`), the same way `Number` does, so `color: #FFF` and
# `color: red` round-trip untouched. Only a *computed* color serializes
# canonically — `#rrggbb` when opaque, `rgba(r, g, b, a)` otherwise, which
# is what dart-sass emits. Colors are never produced by lexing or
# `Expr.coerce`; they only appear when a color function parses one of its
# arguments, so no existing declaration changes shape.

require "./value"

module Hwaro
  module Assets
    module Sass
      # An RGBA color. Channels are kept as Float64 through intermediate
      # math (HSL round-trips lose precision at integer width) and only
      # round to 0..255 on output.
      class ColorV < Value
        getter red : Float64
        getter green : Float64
        getter blue : Float64
        getter alpha : Float64
        # Source spelling, when this color came from the stylesheet
        # rather than from a computation. Nil for computed colors.
        getter lexeme : String?

        def initialize(red : Float64, green : Float64, blue : Float64,
                       alpha : Float64 = 1.0, @lexeme : String? = nil)
          @red = red.clamp(0.0, 255.0)
          @green = green.clamp(0.0, 255.0)
          @blue = blue.clamp(0.0, 255.0)
          @alpha = alpha.clamp(0.0, 1.0)
        end

        def red8 : Int32
          ColorV.fuzzy_round(@red)
        end

        def green8 : Int32
          ColorV.fuzzy_round(@green)
        end

        def blue8 : Int32
          ColorV.fuzzy_round(@blue)
        end

        # dart-sass's `fuzzyRound`: halves go away from zero, but a value
        # within 1e-11 of .5 counts as exactly .5.
        #
        # Both halves of that rule matter. Crystal's default `round` is
        # ties-to-even, which sends 127.5 up but 76.5 down. And the exact
        # halves an HSL round-trip produces don't survive float
        # arithmetic — `hsl(210, 50%, 30%)` computes green as
        # 76.49999999999996, so even ties-away rounding lands a whole
        # channel step below dart-sass. Channels are clamped to 0..255,
        # so only the positive branch is reachable.
        def self.fuzzy_round(value : Float64) : Int32
          fraction = value - value.floor
          (fraction < 0.5 - 1e-11 ? value.floor : value.ceil).to_i
        end

        def opaque? : Bool
          @alpha >= 1.0
        end

        def to_css : String
          if lex = @lexeme
            lex
          elsif opaque?
            "#%02x%02x%02x" % {red8, green8, blue8}
          else
            "rgba(#{red8}, #{green8}, #{blue8}, #{Number.format(@alpha)})"
          end
        end

        # Colors compare by channel, not by spelling: `#fff`, `#ffffff`
        # and `white` are one value in Sass even though their lexemes
        # differ. Comparing `to_css` (the Value default) would call them
        # three different colors and pick the wrong `@if` branch.
        def eq?(other : Value) : Bool
          return false unless other.is_a?(ColorV)
          red8 == other.red8 && green8 == other.green8 &&
            blue8 == other.blue8 && @alpha == other.alpha
        end

        # Drops the source spelling — used when a function returns a color
        # it did not actually change, so the result still serializes
        # canonically like every other computed color.
        def computed : ColorV
          return self unless @lexeme
          ColorV.new(@red, @green, @blue, @alpha)
        end

        def with_alpha(alpha : Float64) : ColorV
          ColorV.new(@red, @green, @blue, alpha)
        end

        # ---------------------------------------------------------------
        # HSL
        # ---------------------------------------------------------------

        # Returns {hue 0..360, saturation 0..100, lightness 0..100}.
        def to_hsl : Tuple(Float64, Float64, Float64)
          r = @red / 255.0
          g = @green / 255.0
          b = @blue / 255.0
          max = {r, g, b}.max
          min = {r, g, b}.min
          delta = max - min
          lightness = (max + min) / 2.0

          if delta == 0.0
            return {0.0, 0.0, lightness * 100.0}
          end

          saturation =
            if lightness > 0.5
              delta / (2.0 - max - min)
            else
              delta / (max + min)
            end

          hue =
            if max == r
              (g - b) / delta + (g < b ? 6.0 : 0.0)
            elsif max == g
              (b - r) / delta + 2.0
            else
              (r - g) / delta + 4.0
            end

          {hue * 60.0, saturation * 100.0, lightness * 100.0}
        end

        def hue : Float64
          to_hsl[0]
        end

        def saturation : Float64
          to_hsl[1]
        end

        def lightness : Float64
          to_hsl[2]
        end

        def self.from_hsl(hue : Float64, saturation : Float64,
                          lightness : Float64, alpha : Float64 = 1.0) : ColorV
          # Hue is circular: -30deg and 330deg name the same color. Crystal's
          # `%` keeps the sign of the left operand, so the second wrap is
          # what actually normalizes a negative hue.
          h = ((hue % 360.0) + 360.0) % 360.0 / 360.0
          s = saturation.clamp(0.0, 100.0) / 100.0
          l = lightness.clamp(0.0, 100.0) / 100.0

          if s == 0.0
            gray = l * 255.0
            return new(gray, gray, gray, alpha)
          end

          q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
          p = 2.0 * l - q
          new(
            hue_to_rgb(p, q, h + 1.0 / 3.0) * 255.0,
            hue_to_rgb(p, q, h) * 255.0,
            hue_to_rgb(p, q, h - 1.0 / 3.0) * 255.0,
            alpha
          )
        end

        private def self.hue_to_rgb(p : Float64, q : Float64, t : Float64) : Float64
          t += 1.0 if t < 0.0
          t -= 1.0 if t > 1.0
          return p + (q - p) * 6.0 * t if t < 1.0 / 6.0
          return q if t < 1.0 / 2.0
          return p + (q - p) * (2.0 / 3.0 - t) * 6.0 if t < 2.0 / 3.0
          p
        end

        # ---------------------------------------------------------------
        # Parsing
        # ---------------------------------------------------------------

        # Parses a color literal — `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`
        # or a CSS named color. Returns nil for anything else (including
        # `rgb(...)`/`hsl(...)` call syntax, which stays verbatim CSS: see
        # the note in `functions.cr` on why those aren't evaluated).
        #
        # The parsed color carries the original text as its lexeme, so an
        # untouched color still serializes exactly as written.
        def self.parse?(text : String) : ColorV?
          stripped = text.strip
          return if stripped.empty?
          return parse_hex?(stripped) if stripped[0] == '#'
          named?(stripped)
        end

        private def self.parse_hex?(text : String) : ColorV?
          digits = text[1..]
          return unless digits.each_char.all?(&.to_i?(16))

          case digits.size
          when 3, 4
            channels = digits.each_char.map { |c| (c.to_i(16) * 17).to_f }.to_a
            alpha = digits.size == 4 ? channels[3] / 255.0 : 1.0
            new(channels[0], channels[1], channels[2], alpha, lexeme: text)
          when 6, 8
            channels = (0...digits.size // 2).map { |i| digits[i * 2, 2].to_i(16).to_f }
            alpha = digits.size == 8 ? channels[3] / 255.0 : 1.0
            new(channels[0], channels[1], channels[2], alpha, lexeme: text)
          end
        end

        private def self.named?(text : String) : ColorV?
          key = text.downcase
          # `transparent` is the one CSS color name that isn't opaque, so
          # it can't live in the RGB-triple table below.
          return new(0.0, 0.0, 0.0, 0.0, lexeme: text) if key == "transparent"
          return unless rgb = NAMED_COLORS[key]?
          new(rgb[0].to_f, rgb[1].to_f, rgb[2].to_f, 1.0, lexeme: text)
        end

        # CSS named colors (CSS Color Level 4). `transparent` is handled
        # separately in `named?` because it carries an alpha.
        NAMED_COLORS = {
          "aliceblue"            => {240, 248, 255},
          "antiquewhite"         => {250, 235, 215},
          "aqua"                 => {0, 255, 255},
          "aquamarine"           => {127, 255, 212},
          "azure"                => {240, 255, 255},
          "beige"                => {245, 245, 220},
          "bisque"               => {255, 228, 196},
          "black"                => {0, 0, 0},
          "blanchedalmond"       => {255, 235, 205},
          "blue"                 => {0, 0, 255},
          "blueviolet"           => {138, 43, 226},
          "brown"                => {165, 42, 42},
          "burlywood"            => {222, 184, 135},
          "cadetblue"            => {95, 158, 160},
          "chartreuse"           => {127, 255, 0},
          "chocolate"            => {210, 105, 30},
          "coral"                => {255, 127, 80},
          "cornflowerblue"       => {100, 149, 237},
          "cornsilk"             => {255, 248, 220},
          "crimson"              => {220, 20, 60},
          "cyan"                 => {0, 255, 255},
          "darkblue"             => {0, 0, 139},
          "darkcyan"             => {0, 139, 139},
          "darkgoldenrod"        => {184, 134, 11},
          "darkgray"             => {169, 169, 169},
          "darkgreen"            => {0, 100, 0},
          "darkgrey"             => {169, 169, 169},
          "darkkhaki"            => {189, 183, 107},
          "darkmagenta"          => {139, 0, 139},
          "darkolivegreen"       => {85, 107, 47},
          "darkorange"           => {255, 140, 0},
          "darkorchid"           => {153, 50, 204},
          "darkred"              => {139, 0, 0},
          "darksalmon"           => {233, 150, 122},
          "darkseagreen"         => {143, 188, 143},
          "darkslateblue"        => {72, 61, 139},
          "darkslategray"        => {47, 79, 79},
          "darkslategrey"        => {47, 79, 79},
          "darkturquoise"        => {0, 206, 209},
          "darkviolet"           => {148, 0, 211},
          "deeppink"             => {255, 20, 147},
          "deepskyblue"          => {0, 191, 255},
          "dimgray"              => {105, 105, 105},
          "dimgrey"              => {105, 105, 105},
          "dodgerblue"           => {30, 144, 255},
          "firebrick"            => {178, 34, 34},
          "floralwhite"          => {255, 250, 240},
          "forestgreen"          => {34, 139, 34},
          "fuchsia"              => {255, 0, 255},
          "gainsboro"            => {220, 220, 220},
          "ghostwhite"           => {248, 248, 255},
          "gold"                 => {255, 215, 0},
          "goldenrod"            => {218, 165, 32},
          "gray"                 => {128, 128, 128},
          "green"                => {0, 128, 0},
          "greenyellow"          => {173, 255, 47},
          "grey"                 => {128, 128, 128},
          "honeydew"             => {240, 255, 240},
          "hotpink"              => {255, 105, 180},
          "indianred"            => {205, 92, 92},
          "indigo"               => {75, 0, 130},
          "ivory"                => {255, 255, 240},
          "khaki"                => {240, 230, 140},
          "lavender"             => {230, 230, 250},
          "lavenderblush"        => {255, 240, 245},
          "lawngreen"            => {124, 252, 0},
          "lemonchiffon"         => {255, 250, 205},
          "lightblue"            => {173, 216, 230},
          "lightcoral"           => {240, 128, 128},
          "lightcyan"            => {224, 255, 255},
          "lightgoldenrodyellow" => {250, 250, 210},
          "lightgray"            => {211, 211, 211},
          "lightgreen"           => {144, 238, 144},
          "lightgrey"            => {211, 211, 211},
          "lightpink"            => {255, 182, 193},
          "lightsalmon"          => {255, 160, 122},
          "lightseagreen"        => {32, 178, 170},
          "lightskyblue"         => {135, 206, 250},
          "lightslategray"       => {119, 136, 153},
          "lightslategrey"       => {119, 136, 153},
          "lightsteelblue"       => {176, 196, 222},
          "lightyellow"          => {255, 255, 224},
          "lime"                 => {0, 255, 0},
          "limegreen"            => {50, 205, 50},
          "linen"                => {250, 240, 230},
          "magenta"              => {255, 0, 255},
          "maroon"               => {128, 0, 0},
          "mediumaquamarine"     => {102, 205, 170},
          "mediumblue"           => {0, 0, 205},
          "mediumorchid"         => {186, 85, 211},
          "mediumpurple"         => {147, 112, 219},
          "mediumseagreen"       => {60, 179, 113},
          "mediumslateblue"      => {123, 104, 238},
          "mediumspringgreen"    => {0, 250, 154},
          "mediumturquoise"      => {72, 209, 204},
          "mediumvioletred"      => {199, 21, 133},
          "midnightblue"         => {25, 25, 112},
          "mintcream"            => {245, 255, 250},
          "mistyrose"            => {255, 228, 225},
          "moccasin"             => {255, 228, 181},
          "navajowhite"          => {255, 222, 173},
          "navy"                 => {0, 0, 128},
          "oldlace"              => {253, 245, 230},
          "olive"                => {128, 128, 0},
          "olivedrab"            => {107, 142, 35},
          "orange"               => {255, 165, 0},
          "orangered"            => {255, 69, 0},
          "orchid"               => {218, 112, 214},
          "palegoldenrod"        => {238, 232, 170},
          "palegreen"            => {152, 251, 152},
          "paleturquoise"        => {175, 238, 238},
          "palevioletred"        => {219, 112, 147},
          "papayawhip"           => {255, 239, 213},
          "peachpuff"            => {255, 218, 185},
          "peru"                 => {205, 133, 63},
          "pink"                 => {255, 192, 203},
          "plum"                 => {221, 160, 221},
          "powderblue"           => {176, 224, 230},
          "purple"               => {128, 0, 128},
          "rebeccapurple"        => {102, 51, 153},
          "red"                  => {255, 0, 0},
          "rosybrown"            => {188, 143, 143},
          "royalblue"            => {65, 105, 225},
          "saddlebrown"          => {139, 69, 19},
          "salmon"               => {250, 128, 114},
          "sandybrown"           => {244, 164, 96},
          "seagreen"             => {46, 139, 87},
          "seashell"             => {255, 245, 238},
          "sienna"               => {160, 82, 45},
          "silver"               => {192, 192, 192},
          "skyblue"              => {135, 206, 235},
          "slateblue"            => {106, 90, 205},
          "slategray"            => {112, 128, 144},
          "slategrey"            => {112, 128, 144},
          "snow"                 => {255, 250, 250},
          "springgreen"          => {0, 255, 127},
          "steelblue"            => {70, 130, 180},
          "tan"                  => {210, 180, 140},
          "teal"                 => {0, 128, 128},
          "thistle"              => {216, 191, 216},
          "tomato"               => {255, 99, 71},
          "turquoise"            => {64, 224, 208},
          "violet"               => {238, 130, 238},
          "wheat"                => {245, 222, 179},
          "white"                => {255, 255, 255},
          "whitesmoke"           => {245, 245, 245},
          "yellow"               => {255, 255, 0},
          "yellowgreen"          => {154, 205, 50},
        }
      end
    end
  end
end
