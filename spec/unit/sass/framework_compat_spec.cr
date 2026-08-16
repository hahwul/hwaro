# Regression specs for the framework-compatibility batch: every case here
# is minimized from a real Bootstrap 5.3 / Bulma 1.0 failure.

require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe "Sass framework compatibility" do
  # ===========================================================================
  # CSS-owned spans with dynamic pieces in strict contexts
  # ===========================================================================
  it "evaluates calc() with interpolation in @return (Bootstrap add())" do
    css = compile(<<-'SCSS')
      @function add($a, $b) { @return calc(#{$a} + #{$b}); }
      .x { height: add(1em, 2px); }
      SCSS
    css.should contain("height: calc(1em + 2px);")
  end

  it "evaluates url()-style spans with $var pieces in @return" do
    css = compile("@function f($a) { @return calc(100% - $a); }\n.x { w: f(10px); }")
    css.should contain("w: calc(100% - 10px);")
  end

  it "evaluates var() with interpolation in @return (Bulma getVar())" do
    css = compile("@function cv($n) { @return var(\#{$n}); }\n.x { c: cv(--foo); }")
    css.should contain("c: var(--foo);")
  end

  it "keeps plain var()/calc() values verbatim" do
    css = compile(".a { width: var( --x , 10px ); height: calc(100% -  10px); }")
    css.should contain("width: var( --x , 10px );")
    css.should contain("height: calc(100% - 10px);")
  end

  it "evaluates known function calls inside a var() fallback" do
    css = compile(<<-'SCSS')
      @function esc($s) { @return "<#{$s}>"; }
      .b { content: var(--divider, esc("/")); }
      SCSS
    css.should contain(%(content: var(--divider, "</>");))
  end

  it "lexes strings with consecutive interpolations in @return (Bulma buildVarName())" do
    css = compile(<<-'SCSS')
      @function n($a, $b) { @return "--x-#{$a}#{$b}"; }
      .x { c: n(p, q); }
      SCSS
    css.should contain("c: \"--x-pq\";")
  end

  it "converts an unlexable strict expression into a located error" do
    ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /invalid expression/) do
      compile("@function f() { @return ~~~; }\n.x { c: f(); }\n@if f() { .y { a: 1 } }", path: "l.scss")
    end
    ex.location.should_not be_nil
  end

  # ===========================================================================
  # Lazy if()
  # ===========================================================================
  it "evaluates only the taken branch of if() (Bootstrap shift-color())" do
    css = compile(<<-SCSS)
      @function shift($c, $w) { @return if($w > 0, mix(black, $c, $w), mix(white, $c, -$w)); }
      .a { color: shift(#0d6efd, -20%); }
      SCSS
    css.should contain("color: #3d8bfd;")
  end

  it "does not raise @error from the untaken if() branch" do
    css = compile(<<-SCSS)
      @function boom() { @error "untaken"; }
      .a { w: if(true, 1px, boom()); }
      SCSS
    css.should contain("w: 1px;")
  end

  # ===========================================================================
  # !important as a SassScript value (Bootstrap utilities API)
  # ===========================================================================
  it "supports !important through if() in values" do
    css = compile(<<-SCSS)
      $enable: true;
      .m-0 { margin: 0 if($enable, !important, null); }
      .m-1 { margin: 1px if(not $enable, !important, null); }
      SCSS
    css.should contain("margin: 0 !important;")
    css.should contain("margin: 1px;\n")
  end

  # ===========================================================================
  # & as a SassScript value (Bootstrap form-validation-state-selector)
  # ===========================================================================
  it "evaluates & as null at the root and the selector list inside a rule" do
    css = compile(<<-'SCSS')
      @mixin sel($s) { #{if(&, "&", "")}.is-#{$s} { color: red; } }
      .form { @include sel(bad); }
      @include sel(ok);
      SCSS
    css.should contain(".form.is-bad {")
    css.should contain("\n.is-ok {")
  end

  # ===========================================================================
  # meta host functions
  # ===========================================================================
  it "answers the *-exists meta functions" do
    css = compile(<<-SCSS)
      $x: 1;
      @mixin m {}
      @function f() { @return 1; }
      .a {
        a: variable-exists(x);
        b: variable-exists(nope);
        c: mixin-exists(m);
        d: function-exists(f);
        e: function-exists(map-get);
        f: function-exists(zzz);
      }
      SCSS
    css.should contain("a: true;")
    css.should contain("b: false;")
    css.should contain("c: true;")
    css.should contain("d: true;")
    css.should contain("e: true;")
    css.should contain("f: false;")
  end

  it "supports variable-exists inside a value guard (Bootstrap grid mixin)" do
    css = compile(<<-SCSS)
      $box: true;
      .col { box-sizing: if(variable-exists(box) and $box, border-box, null); }
      .col2 { box-sizing: if(variable-exists(nope), border-box, content-box); }
      SCSS
    css.should contain("box-sizing: border-box;")
    css.should contain("box-sizing: content-box;")
  end

  it "invokes functions through get-function and call (Bootstrap map-loop)" do
    css = compile(<<-SCSS)
      @use "sass:meta";
      @function double($x) { @return $x * 2; }
      $args: (5px,);
      .a {
        w: meta.call(meta.get-function("double"), 4px);
        x: call(get-function("double"), $args...);
        y: meta.call(meta.get-function("str-length"), "abc");
      }
      SCSS
    css.should contain("w: 8px;")
    css.should contain("x: 10px;")
    css.should contain("y: 3;")
  end

  # ===========================================================================
  # New builtins
  # ===========================================================================
  it "zips lists (Bootstrap utility values)" do
    css = compile(<<-'SCSS')
      $m: zip((a b c), (1 2 3));
      @each $k, $v in $m { .z-#{$k} { n: $v; } }
      SCSS
    css.should contain(".z-a {\n  n: 1;")
    css.should contain(".z-c {\n  n: 3;")
  end

  it "sets map keys with map.set, nested included (Bulma shades)" do
    css = compile(<<-SCSS)
      @use "sass:map";
      $m: (a: 1);
      $m: map.set($m, b, 2);
      $m: map.set($m, c, d, 3);
      .a { x: map.get($m, b); y: map.get($m, c, d); z: inspect($m); }
      SCSS
    css.should contain("x: 2;")
    css.should contain("y: 3;")
    css.should contain("z: (a: 1, b: 2, c: (d: 3));")
  end

  it "deep-merges maps" do
    css = compile(<<-SCSS)
      @use "sass:map";
      .a { m: inspect(map.deep-merge((a: (b: 1)), (a: (c: 2)))); }
      SCSS
    css.should contain("m: (a: (b: 1, c: 2));")
  end

  # ===========================================================================
  # Value-model fixes
  # ===========================================================================
  it "parses bracketed space lists element-wise" do
    css = compile("@use \"sass:list\";\n.a { n: list.length([1 2 3]); i: inspect([1 2]); }")
    css.should contain("n: 3;")
    css.should contain("i: [1 2];")
  end

  it "round-trips single-element comma lists" do
    css = compile("@use \"sass:list\";\n.a { i: inspect((1,)); s: list.separator((1,)); n: list.length((1,)); }")
    css.should contain("i: (1,);")
    css.should contain("s: comma;")
    css.should contain("n: 1;")
  end

  it "propagates null through bare-variable arguments (Bulma palette)" do
    css = compile(<<-SCSS)
      @mixin pal($light: null, $dark: null) {
        .pal { both: if($light and $dark, yes, no); }
      }
      $light: null;
      $dark: null;
      @include pal($light, $dark);
      SCSS
    css.should contain("both: no;")
  end

  it "lets !default overwrite a null value (Bootstrap dark-mode maps)" do
    css = compile(<<-'SCSS')
      $map: null !default;
      @if true { $map: (a: 1) !default; }
      @each $k, $v in $map { .e-#{$k} { n: $v; } }
      SCSS
    css.should contain(".e-a {\n  n: 1;")
  end

  it "renders nested-list variables without structural parens" do
    css = compile(<<-'SCSS')
      $shadow: inset 0 1px 0 rgba(#fff, 0.15), 0 1px 1px rgba(#000, 0.075);
      .btn { box-shadow: $shadow; --shadow: #{$shadow}; }
      SCSS
    css.should contain("box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.15), 0 1px 1px rgba(0, 0, 0, 0.075);")
    css.should_not contain("(inset")
  end

  it "always evaluates map literals so structure survives argument passing" do
    css = compile(<<-'SCSS')
      $family: "A B", "C D", serif;
      @mixin reg($vars) { @each $k, $v in $vars { .r-#{$k} { v: $v; } } }
      @include reg(("family": $family, "delta": -5%));
      SCSS
    css.should contain(%(v: "A B", "C D", serif;))
    css.should contain("v: -5%;")
  end

  it "compares raw function results with typed numbers (Bootstrap RFS)" do
    css = compile(<<-'SCSS')
      @function ident($x) { @return #{$x}; }
      .a { eq: if(ident(1rem) == 1rem, same, different); }
      SCSS
    css.should contain("eq: same;")
  end

  # ===========================================================================
  # Colors
  # ===========================================================================
  it "reads hsl()/hsla() literals as colors in color functions (Bulma)" do
    css = compile(".a { r: red(hsl(0, 100%, 50%)); d: darken(hsl(120deg, 50%, 50%), 10%); a: alpha(hsla(0, 0%, 0%, 0.5)); }")
    css.should contain("r: 255;")
    css.should contain("d: #339933;")
    css.should contain("a: 0.5;")
  end

  it "remembers declared hsl components through the RGB round trip" do
    css = compile(".a { h: hue(hsl(221, 14%, 100%)); s: saturation(hsl(221, 14%, 100%)); }")
    css.should contain("h: 221deg;")
    css.should contain("s: 14%;")
  end

  # ===========================================================================
  # Comment interpolation
  # ===========================================================================
  it "resolves interpolation inside loud comments (Bootstrap banner)" do
    css = compile("$v: \"5.3.3\";\n/*! Library v\#{$v} */\n.a { b: 1; }")
    css.should contain("/*! Library v5.3.3 */")
  end

  it "leaves comments without interpolation untouched" do
    css = compile("/*! plain $var \\ */\n.a { b: 1; }")
    css.should contain("/*! plain $var \\ */")
  end

  # ===========================================================================
  # Review-batch regressions
  # ===========================================================================
  it "does not scrub selectors with an escaped percent" do
    css = compile(".sale\\%-badge { color: red; }")
    css.should contain(".sale\\%-badge {\n  color: red;")
  end

  it "keeps commented-out Sass with unresolvable interpolation verbatim" do
    css = compile("/* was: color: \#{$old-brand} */\n.a { b: 1; }")
    css.should contain("/* was: color: \#{$old-brand} */")
  end

  it "renders single-element comma lists as their bare value in every output path" do
    css = compile(<<-'SCSS')
      $x: append((), 10px, comma);
      .a { margin: $x; pad: #{$x}; }
      @media (max-width: $x) { .b { c: 1; } }
      SCSS
    css.should contain("margin: 10px;")
    css.should contain("pad: 10px;")
    css.should contain("@media (max-width: 10px)")
    css.should_not contain("(10px,)")
  end

  it "re-resolves a function reference that round-tripped through a variable" do
    css = compile(<<-SCSS)
      $f: get-function("darken");
      .a { c: call($f, #336699, 10%); }
      SCSS
    css.should contain("c: #264d73;")
  end

  it "answers $module-scoped meta introspection" do
    css = compile(<<-SCSS)
      @use "sass:meta";
      @use "sass:color";
      .a { b: meta.function-exists("adjust", $module: "color"); c: meta.function-exists("nope", $module: "color"); }
      SCSS
    css.should contain("b: true;")
    css.should contain("c: false;")
  end

  it "extends targets inside :is()/:where() arguments" do
    css = compile(".x :is(.b) { q: 1; }\n.c { @extend .b; }")
    css.should contain(":is(.b, .c)")
  end

  it "keeps declared hsl components through alpha-only derivations" do
    css = compile(".a { h: hue(transparentize(hsl(221, 14%, 100%), 0.2)); }")
    css.should contain("h: 221deg;")
  end

  it "counts the meta host functions in function-exists and get-function" do
    css = compile(<<-SCSS)
      $g: get-function("variable-exists");
      .a { a: function-exists("get-function"); b: call($g, "g"); c: call($g, "nope"); }
      SCSS
    css.should contain("a: true;")
    css.should contain("b: true;")
    css.should contain("c: false;")
  end
end
