# Regression specs for the 2026-08 dart-sass differential audit.
#
# Each group pins one fixed defect cluster against the behavior verified
# with dart-sass 1.103. Expected values here come from actual dart-sass
# output, not from reading our own implementation.

require "../../spec_helper"

private def compile(source : String) : String
  Hwaro::Assets::Sass.compile(source)
end

describe "Sass division (classic slash rule)" do
  it "divides when an operand is a variable" do
    compile("$a: 10;\no { q: $a/2; }").should contain("q: 5;")
  end

  it "divides when an operand is a function call" do
    compile("@function r() { @return 20; }\no { q: r()/2; }").should contain("q: 10;")
  end

  it "divides inside parentheses" do
    compile("o { q: (1/4); }").should contain("q: 0.25;")
  end

  it "divides when adjacent to other arithmetic" do
    css = compile("o { a: 1/2 + 1/2; b: 12 / 4 * 3; }")
    css.should contain("a: 1;")
    css.should contain("b: 9;")
  end

  it "divides inside Sass function arguments" do
    compile("o { q: percentage(1/4); }").should contain("q: 25%;")
  end

  it "divides in variable declarations, so the stored value is the quotient" do
    compile("$x: 1/2;\no { v: $x; }").should contain("v: 0.5;")
  end

  it "divides in interpolation" do
    compile("o { v: \#{1/2}; }").should contain("v: 0.5;")
  end

  it "keeps a literal slash between plain literals" do
    css = compile("o { font: 12px/30px serif; grid-area: 1 / 2 / 3 / 4; }")
    css.should contain("font: 12px/30px serif;")
    css.should contain("grid-area: 1 / 2 / 3 / 4;")
  end

  it "keeps a literal slash in unknown function arguments" do
    compile("o { q: foo(1/2) 1px; }").should contain("q: foo(1/2) 1px;")
  end

  it "keeps a literal slash under a lone unary minus" do
    compile("o { q: -1/2 1px; }").should contain("q: -1/2 1px;")
  end

  it "binds the slash tighter than a space list" do
    compile("$a: 10;\no { q: $a /2 em; }").should contain("q: 5 em;")
  end

  it "cancels convertible units" do
    compile("o { q: (1in / 96px); }").should contain("q: 1;")
  end
end

describe "Sass unit conversion" do
  it "adds and subtracts across convertible units, left unit winning" do
    css = compile("o { a: 1in + 72pt; b: 1cm + 10mm; c: 100ms + 1s; d: 90deg + 0.5turn; }")
    css.should contain("a: 2in;")
    css.should contain("b: 2cm;")
    css.should contain("c: 1100ms;")
    css.should contain("d: 270deg;")
  end

  it "compares across convertible units" do
    css = compile("o { a: 1in == 96px; b: 2cm > 19mm; }")
    css.should contain("a: true;")
    css.should contain("b: true;")
  end

  it "rejects maps whose keys collide after unit conversion" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /Duplicate key/) do
      compile(%(@use "sass:map"; $m: (1in: a, 96px: b); o { x: map.get($m, 96px); }))
    end
  end

  it "reports convertible units as compatible" do
    compile(%(@use "sass:math";\no { c: math.compatible(1px, 1in); })).should contain("c: true;")
  end

  it "converts in math.div and min/max" do
    css = compile(%(@use "sass:math";\no { a: math.div(1in, 96px); b: math.min(1in, 50px); c: math.max(1s, 500ms); }))
    css.should contain("a: 1;")
    css.should contain("b: 50px;")
    css.should contain("c: 1s;")
  end

  it "still refuses unconvertible unit pairs" do
    compile("o { q: 1px + 1s; }").should contain("q: 1px + 1s;") # verbatim fallback
  end
end

describe "Sass math module additions" do
  it "computes log, hypot and trigonometry" do
    css = compile(<<-SCSS)
      @use "sass:math";
      o {
        a: math.log(math.$e);
        b: math.log(8, 2);
        c: math.hypot(3, 4);
        d: math.cos(0);
        e: math.atan2(1, 1);
        f: math.asin(1);
      }
      SCSS
    css.should contain("a: 1;")
    css.should contain("b: 3;")
    css.should contain("c: 5;")
    css.should contain("d: 1;")
    css.should contain("e: 45deg;")
    css.should contain("f: 90deg;")
  end

  it "keeps units in hypot and converts angle units in sin" do
    css = compile(%(@use "sass:math";\no { a: math.hypot(3px, 4px); b: math.sin(90deg); }))
    css.should contain("a: 5px;")
    css.should contain("b: 1;")
  end
end

describe "Sass string/list function additions" do
  it "inserts with positive, zero, and negative indices" do
    css = compile(<<-SCSS)
      @use "sass:string";
      o {
        a: string.insert("abc", "X", -1);
        b: string.insert("abc", "X", -2);
        c: string.insert("abc", "X", 0);
        d: string.insert("abc", "X", 2);
      }
      SCSS
    css.should contain(%(a: "abcX";))
    css.should contain(%(b: "abXc";))
    css.should contain(%(c: "Xabc";))
    css.should contain(%(d: "aXbc";))
  end

  it "splits strings into a bracketed comma list" do
    css = compile(%(@use "sass:string";\no { a: inspect(string.split("a,b,c", ",")); }))
    css.should contain(%(a: ["a", "b", "c"];))
  end

  it "supports set-nth, list.slash and list.is-bracketed" do
    css = compile(<<-SCSS)
      @use "sass:list";
      o {
        a: set-nth(1 2 3, 2, X);
        b: inspect(list.slash(1, 2, 3));
        c: list.is-bracketed([1 2]);
        d: list.nth(list.slash(1, 2, 3), 2);
      }
      SCSS
    css.should contain("a: 1 X 3;")
    css.should contain("b: 1 / 2 / 3;")
    css.should contain("c: true;")
    css.should contain("d: 2;")
  end

  it "round-trips a slash list through a variable" do
    css = compile(<<-SCSS)
      @use "sass:list";
      $l: list.slash(4, 5, 6);
      a { n: list.length($l); s: list.separator($l); b: list.nth($l, 2); }
      SCSS
    css.should contain("n: 3;")
    css.should contain("s: slash;")
    css.should contain("b: 5;")
  end
end

describe "Sass color additions" do
  it "reads channels via color.channel" do
    css = compile(<<-SCSS)
      @use "sass:color";
      o {
        r: color.channel(rgba(10, 20, 30, 0.5), "red");
        h: color.channel(#f00, "hue", $space: hsl);
        l: color.channel(#f00, "lightness", $space: hsl);
      }
      SCSS
    css.should contain("r: 10;")
    css.should contain("h: 0deg;")
    css.should contain("l: 50%;")
  end

  it "formats ie-hex-str" do
    css = compile("o { a: ie-hex-str(#abcdef); b: ie-hex-str(rgba(255, 0, 0, 0.5)); }")
    css.should contain("a: #FFABCDEF;")
    css.should contain("b: #80FF0000;")
  end

  it "builds colors from hwb channels" do
    # hwb(0, 0%, 0%) is pure red.
    compile(%(@use "sass:color";\no { c: color.hwb(0 0% 0%); })).should contain("c: red;")
  end

  it "compares colors by value across spellings" do
    css = compile("o { a: red == #f00; b: rgb(255, 0, 0) == #ff0000; }")
    css.should contain("a: true;")
    css.should contain("b: true;")
  end
end

describe "Sass selector module" do
  it "unifies compound selectors with elements first" do
    css = compile(%(@use "sass:selector";\no { a: selector.unify(".wrapper .field", "input"); b: selector.unify(".a.b", ".b.c"); c: if(selector.unify("a.x", "b") == null, none, some); }))
    css.should contain("a: .wrapper input.field;")
    css.should contain("b: .a.b.c;")
    css.should contain("c: none;")
  end

  it "nests and appends selector lists" do
    css = compile(%(@use "sass:selector";\no { a: selector.nest(".a, .b", ".c", ".d &"); b: selector.append(".a", "__b", "-c"); }))
    css.should contain("a: .d .a .c, .d .b .c;")
    css.should contain("b: .a__b-c;")
  end

  it "answers is-superselector" do
    css = compile(%(@use "sass:selector";\no { a: selector.is-superselector(".a", ".a.b"); b: selector.is-superselector(".a", ".b"); }))
    css.should contain("a: true;")
    css.should contain("b: false;")
  end

  it "keeps whitespace inside attribute selectors and :is() when appending/nesting" do
    css = compile(<<-SCSS)
      @use "sass:selector";
      o {
        a: selector.append('[title="a b"]', ".x");
        b: selector.nest(":is(a > b)", ".c");
      }
      SCSS
    css.should contain(%(a: [title="a b"].x;))
    css.should contain("b: :is(a > b) .c;")
  end

  it "works with & through interpolation in @at-root" do
    css = compile(<<-'SCSS')
      @use "sass:selector";
      @mixin unify-parent($child) {
        @at-root #{selector.unify(&, $child)} { @content; }
      }
      .wrapper .field { @include unify-parent("input") { color: red; } }
      SCSS
    css.should contain(".wrapper input.field {\n  color: red;")
    css.should_not contain(".wrapper .field .wrapper")
  end
end

describe "Sass variadic keyword arguments" do
  it "collects extra keyword arguments into meta.keywords" do
    css = compile(<<-SCSS)
      @use "sass:meta";
      @mixin m($args...) { x: inspect(meta.keywords($args)); n: length($args); }
      a { @include m(1, $a: 2, $b: c); }
      SCSS
    css.should contain("x: (a: 2, b: c);")
    css.should contain("n: 1;")
  end

  it "warns when namespaced meta.keywords is not given an argument list" do
    log = with_captured_log do
      compile(%(@use "sass:meta"; $x: 1; .a { x: meta.keywords($x); }))
    end
    log.should match(/not an argument list/)
  end

  it "forwards keywords through a spread" do
    css = compile(<<-SCSS)
      @use "sass:meta";
      @mixin m($args...) { x: inspect(meta.keywords($args)); }
      @mixin fwd($args...) { @include m($args...); }
      b { @include fwd(9, $z: 8); }
      SCSS
    css.should contain("x: (z: 8);")
  end

  it "errors on a misspelled keyword even when the mixin is variadic" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /no parameter named \$colour/) do
      compile(<<-SCSS)
        @mixin theme($color: red, $args...) { color: $color; }
        a { @include theme($colour: blue); }
        SCSS
    end
  end

  it "accepts extra keywords when meta.keywords reads them" do
    css = compile(<<-SCSS)
      @use "sass:meta";
      @mixin theme($color: red, $args...) { x: inspect(meta.keywords($args)); }
      a { @include theme($colour: blue); }
      SCSS
    css.should contain("x: (colour: blue);")
  end

  it "preserves the spread list's separator in the rest arglist" do
    css = compile(<<-SCSS)
      @mixin n($a, $rest...) { w: $rest; s: list-separator($rest); }
      $lst: 4 5 6;
      b { @include n($lst...); }
      c { @include n(1, 2, 3); }
      SCSS
    css.should contain("w: 5 6;")
    css.should contain("s: space;")
    css.should contain("w: 2, 3;")
    css.should contain("s: comma;")
  end
end

describe "Sass output structure" do
  it "resolves selector lists parent-major" do
    css = compile("a, b { c, d { x: 1; } }")
    css.should contain("a c, a d, b c, b d {")
  end

  it "keeps mixed parent-referencing parts in parent-major order" do
    css = compile("a, b { c, &:hover, d { x: 1; } }")
    css.should contain("a c, a:hover, a d, b c, b:hover, b d {")
  end

  it "reopens a rule for declarations that follow a nested rule" do
    css = compile("a { color: red; b { x: 1; } margin: 0; }")
    css.index!("color: red").should be < css.index!("x: 1")
    css.index!("x: 1").should be < css.index!("margin: 0")
    css.scan(/^a \{$/m).size.should eq(2)
  end

  it "does not reopen when declarations precede nested rules" do
    css = compile("a { color: red; margin: 0; b { x: 1; } }")
    css.scan(/^a \{$/m).size.should eq(1)
  end

  it "merges nested @media through style rules and reopens the outer block" do
    css = compile("@media screen { c { x: 1; @media (min-width: 200px) { y: 2; } z: 3; } d { w: 4; } }")
    css.should contain("@media screen and (min-width: 200px) {\n  c {\n    y: 2;")
    # z stays with x (the c rule was still last in the outer block) …
    css.should contain("x: 1;\n    z: 3;")
    # … while d reopens a fresh `@media screen` after the merged block.
    merged = css.index!("@media screen and")
    css.index!("w: 4").should be > merged
  end

  it "cross-multiplies comma-separated media queries outer-major, dropping type conflicts" do
    css = compile("@media (min-width: 10px), print { a { @media (max-width: 20px), screen { x: 1; } } }")
    css.should contain("@media (min-width: 10px) and (max-width: 20px), screen and (min-width: 10px), print and (max-width: 20px) {")
  end

  it "does not duplicate ancestor conditions in triple-nested @media" do
    css = compile("@media (min-width: 1px) { @media (min-width: 2px) { @media (min-width: 3px) { a { x: 1 } } } }")
    css.should contain("@media (min-width: 1px) and (min-width: 2px) and (min-width: 3px) {")
    css.should_not contain("(min-width: 1px) and (min-width: 1px)")
  end

  it "keeps nested form for uppercase NOT media queries the same as lowercase" do
    lower = compile("@media not print, screen { .a { @media (min-width: 10px) { x: 1; } } }")
    upper = compile("@media Not print, screen { .a { @media (min-width: 10px) { x: 1; } } }")
    lower.should contain("@media not print, screen")
    lower.should contain("@media (min-width: 10px)")
    upper.should contain("@media Not print, screen")
    upper.should contain("@media (min-width: 10px)")
    upper.should_not contain("@media screen and (min-width: 10px)")
  end

  it "resolves @at-root \#{&} without re-nesting" do
    css = compile(".block { @at-root \#{&}__direct { color: blue; } }")
    css.should contain(".block__direct {\n  color: blue;")
    css.should_not contain(".block .block__direct")
  end

  it "prepends @charset when the output contains non-ASCII" do
    compile(%(a { content: "한글"; })).should start_with(%(@charset "UTF-8";\n))
  end

  it "does not double a source @charset" do
    css = compile(%(@charset "UTF-8";\na { content: "한글"; }))
    css.scan("@charset").size.should eq(1)
  end

  it "leaves ASCII-only output without @charset" do
    compile("a { color: red; }").should_not contain("@charset")
  end
end

describe "Sass expression polish" do
  it "evaluates unary plus" do
    compile("$a: 5;\no { y: +$a; }").should contain("y: 5;")
  end

  it "quotes number + quoted-string concatenation" do
    css = compile(%(o { a: 1 + "a"; b: "a" + 1; c: a + "b"; }))
    css.should contain(%(a: "1a";))
    css.should contain(%(b: "a1";))
    css.should contain("c: ab;")
  end
end
