require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

# Compiles `x: <expr>` and returns just the emitted value.
private def value_of(expr : String) : String
  css = compile(".a { x: #{expr}; }")
  css.match(/x:\s*(.*?);/).try(&.[1]) || ""
end

describe "Sass colors" do
  # ===========================================================================
  # Byte-compat: the plain-CSS guarantee
  #
  # Adding a color model must not rewrite colors nobody asked to change.
  # These are the shapes every real stylesheet already contains.
  # ===========================================================================
  describe "plain-CSS passthrough" do
    it "leaves color literals exactly as written" do
      value_of("#336699").should eq("#336699")
      value_of("#FFF").should eq("#FFF")
      value_of("#AbCdEf").should eq("#AbCdEf")
      value_of("red").should eq("red")
      value_of("rebeccapurple").should eq("rebeccapurple")
      value_of("transparent").should eq("transparent")
    end

    it "leaves CSS color functions as CSS" do
      value_of("rgb(0, 0, 0)").should eq("rgb(0, 0, 0)")
      # hsl()/hsla() aren't registered at all, so they survive byte-for-byte.
      value_of("hsl(120,50%,50%)").should eq("hsl(120,50%,50%)")
      value_of("hsla(120, 50%, 50%, 0.4)").should eq("hsla(120, 50%, 50%, 0.4)")
    end

    # `rgb()`/`rgba()` ARE registered (the Sass-only two-argument form has to
    # work), so a CSS-shaped call is declined and re-serialized rather than
    # passed through untouched. Numbers keep their source spelling — only
    # argument spacing normalizes, which the plain-CSS guarantee allows
    # ("compiles to itself, whitespace-normalized").
    it "normalizes only the spacing of a CSS-shaped rgba()" do
      value_of("rgba(0,0,0,.5)").should eq("rgba(0, 0, 0, .5)")
      value_of("rgba(0, 0, 0, 0.5)").should eq("rgba(0, 0, 0, 0.5)")
    end

    # The regression this guards: a declined call used to raise
    # SoftEvalError, which unwound the WHOLE declaration to verbatim text
    # and took every other expression down with it.
    it "does not poison sibling expressions in the same declaration" do
      compile("$r: 2; .a { filter: grayscale(50%) blur($r * 1px); }")
        .should contain("filter: grayscale(50%) blur(2px);")
      compile("$r: 2; .a { filter: saturate(180%) blur($r * 1px); }")
        .should contain("blur(2px)")
      compile("$r: 2; .a { filter: invert(1) opacity(0.5) blur($r * 1px); }")
        .should contain("blur(2px)")
      compile("$o: 0.5; .a { box-shadow: 0 0 (2px * 2) rgba(0,0,0,$o); }")
        .should contain("box-shadow: 0 0 4px rgba(0, 0, 0, 0.5);")
    end

    it "leaves the CSS filter forms verbatim" do
      # These names are both CSS filters and Sass color functions. With a
      # number rather than a color they are the filter, and must not evaluate.
      value_of("grayscale(50%)").should eq("grayscale(50%)")
      value_of("invert(20%)").should eq("invert(20%)")
      value_of("saturate(50%)").should eq("saturate(50%)")
      value_of("opacity(50%)").should eq("opacity(50%)")
    end

    it "keeps a color variable's spelling when nothing modifies it" do
      css = compile("$brand: #AABBCC; .a { color: $brand; }")
      css.should contain("color: #AABBCC;")
    end
  end

  # ===========================================================================
  # Lightness / saturation
  # ===========================================================================
  describe "darken / lighten" do
    it "shifts lightness in HSL space" do
      value_of("darken(#336699, 10%)").should eq("#264d73")
      value_of("lighten(#336699, 10%)").should eq("#4080bf")
      value_of("darken(red, 10%)").should eq("#cc0000")
      value_of("lighten(black, 50%)").should eq("#808080")
    end

    it "clamps at the ends of the lightness range" do
      value_of("darken(#336699, 100%)").should eq("#000000")
      value_of("lighten(#336699, 100%)").should eq("#ffffff")
    end

    it "rounds exact halves away from zero like dart-sass" do
      # hsl(210, 50%, 30%) computes green as 76.49999999999996; plain
      # rounding drops it to 76 (#264c73) — a whole channel step off.
      value_of("darken(#336699, 10%)").should eq("#264d73")
    end
  end

  describe "saturate / desaturate / grayscale" do
    it "shifts saturation" do
      value_of("saturate(#808080, 20%)").should eq("#996767")
      value_of("desaturate(#996666, 20%)").should eq("#808080")
    end

    it "drops saturation entirely for grayscale" do
      value_of("grayscale(#336699)").should eq("#666666")
      value_of("greyscale(#336699)").should eq("#666666")
    end
  end

  # ===========================================================================
  # Hue
  # ===========================================================================
  describe "hue rotation" do
    it "adjusts the hue by a signed angle" do
      value_of("adjust-hue(#336699, 60deg)").should eq("#663399")
      value_of("adjust-hue(#336699, -60deg)").should eq("#339966")
    end

    it "wraps a negative hue back into range" do
      value_of("adjust-hue(#ff0000, -120)").should eq("#0000ff")
    end

    it "takes the opposite hue for complement" do
      value_of("complement(#336699)").should eq("#996633")
    end
  end

  # ===========================================================================
  # Mixing
  # ===========================================================================
  describe "mix / invert" do
    it "mixes evenly by default" do
      value_of("mix(#ff0000, #0000ff)").should eq("#800080")
    end

    it "honours an explicit weight" do
      value_of("mix(#ff0000, #0000ff, 25%)").should eq("#4000bf")
      value_of("mix(#ff0000, #0000ff, 100%)").should eq("#ff0000")
      value_of("mix(#ff0000, #0000ff, 0%)").should eq("#0000ff")
    end

    it "inverts each channel" do
      value_of("invert(#336699)").should eq("#cc9966")
      value_of("invert(#000000)").should eq("#ffffff")
    end

    it "blends toward the original for a partial invert weight" do
      value_of("invert(#336699, 0%)").should eq("#336699")
    end
  end

  # ===========================================================================
  # Alpha
  # ===========================================================================
  describe "alpha channel" do
    it "sets alpha through the two-argument rgba() form" do
      value_of("rgba(#336699, 0.5)").should eq("rgba(51, 102, 153, 0.5)")
      value_of("rgba(red, 0.25)").should eq("rgba(255, 0, 0, 0.25)")
    end

    it "serializes an opaque result as hex, not rgba" do
      value_of("rgba(#336699, 1)").should eq("#336699")
    end

    it "adds and removes opacity" do
      value_of("opacify(rgba(#336699, 0.5), 0.3)").should eq("rgba(51, 102, 153, 0.8)")
      value_of("transparentize(rgba(#336699, 0.8), 0.3)").should eq("rgba(51, 102, 153, 0.5)")
      value_of("fade-in(rgba(#336699, 0.5), 0.3)").should eq("rgba(51, 102, 153, 0.8)")
      value_of("fade-out(rgba(#336699, 0.8), 0.3)").should eq("rgba(51, 102, 153, 0.5)")
    end

    it "clamps alpha to 0..1" do
      value_of("opacify(rgba(#336699, 0.5), 1)").should eq("#336699")
      value_of("transparentize(rgba(#336699, 0.5), 1)").should eq("rgba(51, 102, 153, 0)")
    end

    it "reads the alpha of a translucent color" do
      value_of("alpha(rgba(#336699, 0.5))").should eq("0.5")
      value_of("opacity(rgba(#336699, 0.5))").should eq("0.5")
      value_of("alpha(#336699)").should eq("1")
    end

    it "treats the transparent keyword as alpha 0" do
      value_of("alpha(transparent)").should eq("0")
    end
  end

  # ===========================================================================
  # Component inspection
  # ===========================================================================
  describe "component getters" do
    it "reads RGB channels" do
      value_of("red(#336699)").should eq("51")
      value_of("green(#336699)").should eq("102")
      value_of("blue(#336699)").should eq("153")
    end

    it "reads HSL components with their units" do
      value_of("hue(#336699)").should eq("210deg")
      value_of("saturation(#336699)").should eq("50%")
      value_of("lightness(#336699)").should eq("40%")
    end

    it "expands three-digit hex channels" do
      value_of("red(#f00)").should eq("255")
      value_of("blue(#00f)").should eq("255")
    end

    it "reads channels from a named color" do
      value_of("red(red)").should eq("255")
      value_of("green(lime)").should eq("255")
    end

    it "reads the alpha of an eight-digit hex" do
      value_of("alpha(#33669980)").should eq("0.5019607843")
    end
  end

  # ===========================================================================
  # adjust / scale / change
  # ===========================================================================
  describe "adjust-color / scale-color / change-color" do
    it "adds to RGB channels" do
      value_of("adjust-color(#336699, $red: 20)").should eq("#476699")
    end

    it "adds to HSL components" do
      value_of("adjust-color(#336699, $lightness: 10%)").should eq("#4080bf")
    end

    it "scales a component toward its limit without overshooting" do
      value_of("scale-color(#336699, $lightness: 20%)").should eq("#4785c2")
      value_of("scale-color(#336699, $lightness: 100%)").should eq("#ffffff")
      value_of("scale-color(#336699, $lightness: -100%)").should eq("#000000")
    end

    it "replaces a component outright" do
      value_of("change-color(#336699, $red: 20)").should eq("#146699")
      value_of("change-color(#336699, $alpha: 0.5)").should eq("rgba(51, 102, 153, 0.5)")
    end

    it "rejects mixing RGB and HSL arguments" do
      # dart-sass errors; the lenient value path keeps the call verbatim.
      value_of("adjust-color(#336699, $red: 10, $lightness: 10%)")
        .should contain("adjust-color(")
    end

    it "rejects an unknown keyword argument" do
      value_of("adjust-color(#336699, $lightnes: 10%)").should contain("adjust-color(")
    end
  end

  # ===========================================================================
  # sass:color module
  # ===========================================================================
  describe "sass:color module" do
    it "exposes the modern names" do
      css = compile(<<-SCSS)
        @use "sass:color";
        .a {
          b: color.adjust(#336699, $lightness: 10%);
          c: color.scale(#336699, $lightness: 20%);
          d: color.change(#336699, $red: 20);
          e: color.mix(#ff0000, #0000ff);
          f: color.complement(#336699);
          g: color.grayscale(#336699);
          h: color.invert(#336699);
          i: color.red(#336699);
        }
        SCSS
      css.should contain("b: #4080bf;")
      css.should contain("c: #4785c2;")
      css.should contain("d: #146699;")
      css.should contain("e: #800080;")
      css.should contain("f: #996633;")
      css.should contain("g: #666666;")
      css.should contain("h: #cc9966;")
      css.should contain("i: 51;")
    end
  end

  # ===========================================================================
  # Integration with the rest of the language
  # ===========================================================================
  describe "language integration" do
    it "reports colors from type-of" do
      value_of("type-of(#336699)").should eq("color")
      value_of("type-of(red)").should eq("color")
      # A quoted string that happens to spell a color is still a string.
      value_of(%(type-of("red"))).should eq("string")
    end

    it "compares computed colors by channel, not by spelling" do
      # Two functions that land on the same color agree even though one
      # went through HSL and the other through RGB.
      css = compile(<<-SCSS)
        .a { b: if(darken(#ff0000, 0%) == mix(#ff0000, #ff0000), yes, no); }
        SCSS
      css.should contain("b: yes;")
    end

    # Documented deviation: `==` between two *literals* is still the
    # generic text comparison, because colors are only parsed when a color
    # function asks for one. Teaching `==` to parse would flip `@if`
    # branches in stylesheets that compile today, which the plain-CSS
    # guarantee rules out. See docs/content/features/sass.md.
    it "compares two color literals as text" do
      css = compile(".a { b: if(#ffffff == #FFF, yes, no); }")
      css.should contain("b: no;")
    end

    it "works through variables and user functions" do
      css = compile(<<-SCSS)
        $brand: #336699;
        @function shade($c, $n) { @return darken($c, $n); }
        .a { color: shade($brand, 10%); }
        SCSS
      css.should contain("color: #264d73;")
    end

    it "works inside control flow and interpolation" do
      css = compile(<<-'SCSS')
        $brand: #336699;
        @each $step in 10, 20 {
          .s-#{$step} { color: darken($brand, $step * 1%); }
        }
        SCSS
      css.should contain("color: #264d73;")
      css.should contain("color: #1a334d;")
    end

    it "surfaces a color error in a strict context" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /color/) do
        compile(%(@function f() { @return darken("not a color", 10%); } .a { b: f(); }))
      end
    end

    it "keeps a non-color argument verbatim in a lenient context" do
      value_of("darken(12px, 10%)").should eq("darken(12px, 10%)")
    end

    it "round-trips a translucent color through a variable" do
      # Variables store `inspect_css` and re-coerce on use, so a computed
      # rgba() has to parse back into a color or the next function breaks.
      compile("$c: rgba(#336699, 0.5); .a { color: darken($c, 10%); }")
        .should contain("color: rgba(38, 77, 115, 0.5);")
    end

    it "accepts the dart-sass keyword argument names" do
      value_of("darken(#336699, $amount: 10%)").should eq("#264d73")
      value_of("lighten($color: #336699, $amount: 10%)").should eq("#4080bf")
      value_of("mix(#ff0000, #0000ff, $weight: 25%)").should eq("#4000bf")
      value_of("rgba($color: #336699, $alpha: 0.5)").should eq("rgba(51, 102, 153, 0.5)")
    end

    it "compares equal regardless of operand order" do
      css = compile(".a { b: if(darken(#ff0000, 0%) == #ff0000, yes, no); c: if(#ff0000 == darken(#ff0000, 0%), yes, no); }")
      css.should contain("b: yes;")
      css.should contain("c: yes;")
    end

    it "rejects an out-of-range amount instead of silently clamping" do
      # A no-op `lighten` or a surprise black is worse than a visible
      # fallback: the output would look perfectly valid either way.
      value_of("lighten(#336699, -10%)").should eq("lighten(#336699, -10%)")
      value_of("darken(#336699, 200%)").should eq("darken(#336699, 200%)")
    end

    it "survives a non-finite argument without crashing" do
      # `NaN.to_i` raises OverflowError, which nothing in the compiler
      # catches — it would escape as a bare arithmetic error.
      compile(%(@use "sass:math"; .a { color: darken(#336699, math.pow(-1, 0.5)); }))
        .should contain("darken(")
    end

    it "exposes fade-in / fade-out on the sass:color module" do
      compile(%(@use "sass:color"; .a { b: color.fade-in(rgba(#336699, 0.5), 0.2); c: color.fade-out(rgba(#336699, 0.5), 0.2); }))
        .should contain("b: rgba(51, 102, 153, 0.7);")
    end
  end
end
