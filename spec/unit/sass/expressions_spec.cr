require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe "SassScript expressions in values" do
  # ===========================================================================
  # Arithmetic
  # ===========================================================================
  it "evaluates arithmetic on numbers with units" do
    css = compile(<<-SCSS)
      $base: 4px;
      .a { margin: $base * 2; padding: $base + 2px; top: 10px - $base; }
      SCSS
    css.should contain("margin: 8px;")
    css.should contain("padding: 6px;")
    css.should contain("top: 6px;")
  end

  it "evaluates arithmetic in variable declarations" do
    css = compile("$w: 100px;\n$half: $w * 0.5;\n.a { width: $half; }")
    css.should contain("width: 50px;")
  end

  it "formats computed floats like dart-sass" do
    css = compile(".a { width: 1px * 0.5; opacity: 0.1 + 0.2; }")
    css.should contain("width: 0.5px;")
    css.should contain("opacity: 0.3;")
  end

  it "supports modulo with spaces" do
    css = compile(".a { width: 7 % 3px; }")
    css.should contain("width: 1px;")
  end

  it "never treats / as division" do
    css = compile(".a { font: 12px/1.5 sans-serif; grid-area: 1 / 2 / 3 / 4; }")
    css.should contain("font: 12px/1.5 sans-serif;")
    css.should contain("grid-area: 1 / 2 / 3 / 4;")
  end

  it "concatenates strings with +" do
    css = compile(<<-SCSS)
      $name: "card";
      .a { content: $name + "-header"; }
      SCSS
    css.should contain(%q(content: "card-header";))
  end

  it "evaluates expressions in mixin arguments and parameter defaults" do
    css = compile(<<-SCSS)
      @mixin pad($x, $y: $x * 2) { padding: $y $x; }
      .a { @include pad(2px + 2px); }
      SCSS
    css.should contain("padding: 8px 4px;")
  end

  it "evaluates expressions inside interpolation" do
    css = compile(<<-'SCSS')
      $i: 3;
      .w-#{$i * 4} { width: #{$i * 4}px; }
      SCSS
    css.should contain(".w-12 {")
    css.should contain("width: 12px;")
  end

  it "omits declarations whose computed value is null" do
    css = compile(<<-SCSS)
      $on: false;
      .a { color: if($on, red, null); background: blue; }
      SCSS
    css.should_not contain("color")
    css.should contain("background: blue;")
  end

  # ===========================================================================
  # Lenient fallback — anything uncomputable keeps its verbatim text
  # ===========================================================================
  it "keeps unit-incompatible arithmetic verbatim instead of erroring" do
    css = compile("$a: 4px;\n.x { width: $a + 2em; }")
    css.should contain("width: 4px + 2em;")
  end

  it "passes through CSS math functions with viewport units" do
    css = compile(".a { width: min(100% - 10px, 20rem); height: max(10vh, 5em); }")
    css.should contain("width: min(100% - 10px, 20rem);")
    css.should contain("height: max(10vh, 5em);")
  end

  it "passes through calc/var/env/url spans untouched" do
    css = compile(<<-SCSS)
      .a {
        width: calc((100% - 10px) / 3);
        color: var(--x, #fff);
        padding: env(safe-area-inset-top);
        background: url(a+b.png);
      }
      SCSS
    css.should contain("width: calc((100% - 10px) / 3);")
    css.should contain("color: var(--x, #fff);")
    css.should contain("padding: env(safe-area-inset-top);")
    css.should contain("background: url(a+b.png);")
  end

  it "passes through unicode-range values" do
    css = compile("@font-face { font-family: X; src: url(x.woff2); unicode-range: U+0025-00FF; }")
    css.should contain("unicode-range: U+0025-00FF;")
  end

  it "passes through unknown functions while evaluating their arguments" do
    css = compile("$x: 20px;\n.a { transform: translate($x * 2, -50%); }")
    css.should contain("transform: translate(40px, -50%);")
  end

  it "does not evaluate and/or between plain idents" do
    css = compile(".a { font-family: Franklin and Marshall; }")
    css.should contain("font-family: Franklin and Marshall;")
  end

  it "keeps IE filter junk verbatim" do
    css = compile(".a { filter: progid:DXImageTransform.Microsoft.gradient(startColorstr='#aa000000'); }")
    css.should contain("progid:DXImageTransform.Microsoft.gradient(startColorstr='#aa000000')")
  end

  it "treats space-separated negatives as lists, spaced minus as subtraction" do
    css = compile("$x: 10px;\n.a { margin: $x -5px; top: $x - 5px; }")
    css.should contain("margin: 10px -5px;")
    css.should contain("top: 5px;")
  end

  # ===========================================================================
  # At-rule prelude feature values
  # ===========================================================================
  it "evaluates expressions in media-feature values" do
    css = compile(<<-SCSS)
      $bp: (md: 768px);
      $w: 700px;
      .a {
        @media (min-width: map-get($bp, md)) { color: red; }
        @media (max-width: $w - 1px) { color: blue; }
      }
      SCSS
    css.should contain("@media (min-width: 768px) {")
    css.should contain("@media (max-width: 699px) {")
  end

  it "keeps uncomputable prelude values verbatim" do
    css = compile("@media screen and (min-resolution: 2dppx), print { .a { color: red; } }")
    css.should contain("@media screen and (min-resolution: 2dppx), print {")
  end

  # ===========================================================================
  # Comparisons & equality feed @if (values stay strings elsewhere)
  # ===========================================================================
  it "compares quoted and unquoted strings as equal" do
    css = compile(<<-SCSS)
      $theme: "dark";
      .a { @if $theme == dark { color: white; } }
      SCSS
    css.should contain("color: white;")
  end

  it "compares numbers with compatible units" do
    css = compile(".a { @if 1px < 2px and 3 >= 3 { width: ok; } }")
    css.should contain("width: ok;")
  end

  it "errors on incompatible-unit comparison in strict contexts" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /incompatible units/) do
      compile(".a { @if 1px < 2em { width: no; } }")
    end
  end
end
