require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe "Sass functions" do
  # ===========================================================================
  # @function / @return
  # ===========================================================================
  it "defines and calls a user function in a value" do
    css = compile(<<-SCSS)
      @function double($n) { @return $n * 2; }
      .a { width: double(21px); }
      SCSS
    css.should contain("width: 42px;")
  end

  it "supports defaults, keyword arguments, and control flow in bodies" do
    css = compile(<<-SCSS)
      @function spacing($step, $base: 4px) {
        @if $step == 0 { @return 0; }
        @return $base * $step;
      }
      .a { padding: spacing(3); margin: spacing($step: 0); gap: spacing(2, $base: 8px); }
      SCSS
    css.should contain("padding: 12px;")
    css.should contain("margin: 0;")
    css.should contain("gap: 16px;")
  end

  it "supports recursion" do
    css = compile(<<-SCSS)
      @function fib($n) {
        @if $n <= 2 { @return 1; }
        @return fib($n - 1) + fib($n - 2);
      }
      .a { order: fib(10); }
      SCSS
    css.should contain("order: 55;")
  end

  it "supports variadic parameters via list functions" do
    css = compile(<<-SCSS)
      @function sum($nums...) {
        $total: 0;
        @each $n in $nums { $total: $total + $n; }
        @return $total;
      }
      .a { width: sum(1px, 2px, 3px); }
      SCSS
    css.should contain("width: 6px;")
  end

  it "errors when a function body emits CSS" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /may only contain/) do
      compile("@function bad() { .x { color: red; } @return 1; }\n.a { width: bad(); }")
    end
  end

  it "errors when a function never returns" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /finished without @return/) do
      compile("@function nope() { $x: 1; }\n.a { @if nope() { color: red; } }")
    end
  end

  it "errors on @return outside a function" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /within a @function/) do
      compile("@return 1;")
    end
  end

  it "guards runaway recursion" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /too much recursion/) do
      compile("@function loop($n) { @return loop($n); }\n.a { @if loop(1) { color: red; } }")
    end
  end

  # ===========================================================================
  # sass:math
  # ===========================================================================
  it "provides math.div and friends via @use \"sass:math\"" do
    css = compile(<<-SCSS)
      @use "sass:math";
      .a {
        width: math.div(100px, 4);
        flex: math.div(6px, 3px);
        top: math.percentage(math.div(1, 3));
        z-index: math.max(3, 7, 5);
        order: math.floor(2.9);
      }
      SCSS
    css.should contain("width: 25px;")
    css.should contain("flex: 2;")
    css.should contain("top: 33.3333333333%;")
    css.should contain("z-index: 7;")
    css.should contain("order: 2;")
  end

  it "exposes math module variables" do
    css = compile("@use \"sass:math\";\n.a { line-height: math.$e; }")
    css.should contain("line-height: 2.7182818285;")
  end

  it "supports as-alias and as-* for built-in modules" do
    css = compile(<<-SCSS)
      @use "sass:math" as m;
      .a { width: m.div(10px, 2); }
      SCSS
    css.should contain("width: 5px;")

    css2 = compile(<<-SCSS)
      @use "sass:math" as *;
      .a { width: div(10px, 2); }
      SCSS
    css2.should contain("width: 5px;")
  end

  it "errors on math.div without @use in strict contexts but passes through in values" do
    css = compile(".a { width: math.div(10px, 2); }")
    css.should contain("width: math.div(10px, 2);") # no @use "sass:math"
  end

  it "rejects unknown built-in modules" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /unknown built-in module/) do
      compile(%q(@use "sass:color";))
    end
  end

  # ===========================================================================
  # Global built-ins
  # ===========================================================================
  it "provides if(), string, list, and map globals" do
    css = compile(<<-SCSS)
      $map: (primary: #336699, accent: #cc3333);
      $list: 4px 8px 16px;
      .a {
        color: map-get($map, primary);
        width: nth($list, 2);
        order: length($list);
        content: quote(hello);
        background: if(map-has-key($map, accent), map-get($map, accent), black);
      }
      SCSS
    css.should contain("color: #336699;")
    css.should contain("width: 8px;")
    css.should contain("order: 3;")
    css.should contain(%q(content: "hello";))
    css.should contain("background: #cc3333;")
  end

  it "provides string helpers" do
    css = compile(<<-SCSS)
      .a {
        content: to-upper-case("abc") + str-slice("hello", 2, 3);
        order: str-length("four");
      }
      SCSS
    css.should contain(%q(content: "ABCel";))
    css.should contain("order: 4;")
  end

  it "supports nth with negative indices and index()" do
    css = compile(<<-SCSS)
      $l: a, b, c;
      .x { order: index($l, b); grid-row: nth($l, -1); }
      SCSS
    css.should contain("order: 2;")
    css.should contain("grid-row: c;")
  end

  it "merges and removes map keys" do
    css = compile(<<-SCSS)
      $a: (x: 1, y: 2);
      $b: map-merge($a, (y: 3, z: 4));
      .m { order: map-get($b, y); flex: length(map-keys(map-remove($b, x))); }
      SCSS
    css.should contain("order: 3;")
    css.should contain("flex: 2;")
  end

  it "keeps CSS round()/min()/max() forms it can't evaluate" do
    css = compile(".a { width: round(up, 101px, 10px); height: min(5vw, 100px); }")
    css.should contain("width: round(up, 101px, 10px);")
    css.should contain("height: min(5vw, 100px);")
  end

  it "lets user functions shadow global built-ins" do
    css = compile(<<-SCSS)
      @function round($n) { @return 999; }
      .a { width: round(1.2); }
      SCSS
    css.should contain("width: 999;")
  end

  it "reports type-of and unit checks" do
    css = compile(<<-SCSS)
      .a { @if type-of(1px) == number and unitless(3) and unit(1rem) == "rem" { width: ok; } }
      SCSS
    css.should contain("width: ok;")
  end
end
