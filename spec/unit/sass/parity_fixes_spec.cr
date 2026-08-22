# Regression specs for the 2026-08 dart-sass parity audit: interpolation
# of null/lists, url($var), calc() folding, keyword arguments on
# builtins, named-color serialization, math constants, selector.replace/
# simple-selectors, and dart-sass output formatting (blank-line groups,
# selector-list line structure).

require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(source : String) : String
  Hwaro::Assets::Sass.compile(source, "parity.scss")
end

private def value_of(expr : String) : String
  css = compile(".probe { v: #{expr}; }")
  match = css.match(/v: (.*);/)
  match ? match[1] : css
end

describe "Sass dart parity fixes" do
  # =========================================================================
  # Interpolation
  # =========================================================================
  describe "interpolation" do
    it "interpolates a literal null as nothing" do
      value_of("\"\#{null}\"").should eq(%(""))
      value_of("pre\#{null}post").should eq("prepost")
    end

    it "interpolates a parenthesized comma list without its parens" do
      value_of("\#{(1, 2, 3)}").should eq("1, 2, 3")
      value_of("\"\#{(1, 2, 3)}\"").should eq(%("1, 2, 3"))
    end
  end

  # =========================================================================
  # url()
  # =========================================================================
  describe "url() variables" do
    it "substitutes $var inside an unquoted url" do
      compile("$v: 5px;\n.a { b: url($v); }").should contain("b: url(5px);")
      compile("$y: img;\n.a { b: url(x-$y.png); }").should contain("b: url(x-img.png);")
    end

    it "keeps $ literal inside a quoted url" do
      compile("$y: img;\n.a { b: url(\"lit$y\"); }").should contain(%(b: url("lit$y");))
    end

    it "keeps $var literal in a custom property" do
      compile("$v: 5px;\n.a { --u: url($v); }").should contain("--u: url($v);")
    end
  end

  # =========================================================================
  # calc() folding
  # =========================================================================
  describe "calc() folding" do
    it "folds static arithmetic" do
      value_of("calc(1px + 2px)").should eq("3px")
      value_of("calc(10px + 5px * 2)").should eq("20px")
      value_of("calc(9 / 21 * 100%)").should eq("42.8571428571%")
      value_of("calc((2 + 3) * 1px)").should eq("5px")
      value_of("calc(1in + 6px)").should eq("1.0625in")
      value_of("calc(10px / 2px)").should eq("5")
    end

    it "folds nested calc and min/max/clamp" do
      value_of("calc(calc(1px + 2px) * 3)").should eq("9px")
      value_of("calc(min(1px, 0.5px) + 1px)").should eq("1.5px")
      value_of("min(calc(1px + 2px), 5px)").should eq("3px")
    end

    it "keeps unfoldable calc verbatim" do
      value_of("calc(100% - 20px)").should eq("calc(100% - 20px)")
      value_of("calc(1px + 1em)").should eq("calc(1px + 1em)")
      value_of("calc(var(--x) + 2px)").should eq("calc(var(--x) + 2px)")
      # CSS calc rejects unitless + united; dart-sass errors, we pass through.
      value_of("calc(10px + 5)").should eq("calc(10px + 5)")
    end

    it "keeps interpolated calc verbatim" do
      compile("$w: 10px;\n.a { b: calc(\#{$w} * 2); }")
        .should contain("b: calc(10px * 2);")
    end

    it "folds calc reached through a variable" do
      compile("$c: calc(1px + 2px);\n.a { b: $c; }").should contain("b: 3px;")
    end
  end

  # =========================================================================
  # Undivided slash pairs in numeric contexts
  # =========================================================================
  it "divides a lazy slash pair when a numeric context coerces it" do
    value_of("min(10 / 2, 8)").should eq("5")
    value_of("percentage(1/4)").should eq("25%")
  end

  # =========================================================================
  # Named colors
  # =========================================================================
  describe "named-color output" do
    it "serializes computed colors by name when one matches" do
      value_of("mix(#ff0000, #0000ff)").should eq("purple")
      value_of("darken(white, 100%)").should eq("black")
      value_of("lighten(#fff, 10%)").should eq("white")
    end

    it "uses dart-sass's spelling for aliased names" do
      value_of("darken(cyan, 0%)").should eq("aqua")
      value_of("darken(grey, 0%)").should eq("gray")
      value_of("darken(magenta, 0%)").should eq("fuchsia")
    end

    it "keeps literal colors byte-identical" do
      css = compile(".a { c: #ffffff;\n  d: #f00; }")
      css.should contain("c: #ffffff;")
      css.should contain("d: #f00;")
    end

    it "falls back to hex for unnamed colors" do
      value_of("mix(#204060, #204060)").should eq("#204060")
    end
  end

  # =========================================================================
  # math module constants
  # =========================================================================
  it "exposes the sass:math constants" do
    css = compile(<<-SCSS)
      @use "sass:math";
      .a {
        a: math.$pi;
        b: math.$max-safe-integer;
        c: math.is-unitless(math.$epsilon);
        d: if(math.$epsilon > 0, yes, no);
      }
      SCSS
    css.should contain("a: 3.1415926536;")
    css.should contain("b: 9007199254740991;")
    css.should contain("c: true;")
    css.should contain("d: yes;")
  end

  # =========================================================================
  # Keyword arguments on builtins
  # =========================================================================
  describe "builtin keyword arguments" do
    it "binds documented keyword names positionally" do
      css = compile(<<-SCSS)
        @use "sass:list";
        @use "sass:map";
        @use "sass:string";
        @use "sass:math";
        .a {
          a: list.append(1 2, 3, $separator: comma);
          b: map.get($map: (x: 9), $key: x);
          c: string.slice($string: "abcdef", $start-at: 2, $end-at: 4);
          d: math.div($number1: 10, $number2: 4);
          e: math.clamp($min: 1px, $number: 9px, $max: 5px);
          f: list.nth($list: 4 5 6, $n: 2);
        }
        SCSS
      css.should contain("a: 1, 2, 3;")
      css.should contain("b: 9;")
      css.should contain(%(c: "bcd";))
      css.should contain("d: 2.5;")
      css.should contain("e: 5px;")
      css.should contain("f: 5;")
    end

    it "supports list.join's $bracketed argument" do
      css = compile(<<-SCSS)
        @use "sass:list";
        .a {
          a: list.join([1 2], 3 4, $bracketed: false);
          b: list.join(1 2, 3 4, $separator: comma, $bracketed: true);
        }
        SCSS
      css.should contain("a: 1 2 3 4;")
      css.should contain("b: [1, 2, 3, 4];")
    end

    it "rejects an unknown keyword name" do
      # Lenient value context: the call reconstructs verbatim.
      value_of("str-slice(\"abc\", $nope: 1)").should contain("str-slice(")
    end
  end

  # =========================================================================
  # sass:selector additions
  # =========================================================================
  describe "selector.replace / simple-selectors" do
    it "replaces a compound within a complex selector" do
      css = compile(<<-SCSS)
        @use "sass:selector";
        .a {
          r: selector.replace(".a .b", ".b", ".new");
          s: inspect(selector.simple-selectors(".a.b:hover"));
        }
        SCSS
      css.should contain("r: .a .new;")
      css.should contain("s: .a, .b, :hover;")
    end

    it "keeps a selector without the target unchanged" do
      css = compile(%(@use "sass:selector";\n.a { r: selector.replace(".x", ".nope", ".y"); }))
      css.should contain("r: .x;")
    end
  end

  # =========================================================================
  # inspect() nested-list parens
  # =========================================================================
  describe "inspect parenthesization" do
    it "leaves space lists bare inside comma lists" do
      value_of("inspect(selector-parse(\".a .b, .c\"))").should eq(".a .b, .c")
    end

    it "parenthesizes comma lists inside comma lists" do
      value_of("inspect(((1, 2), 3))").should eq("(1, 2), 3")
    end

    it "parenthesizes nested space lists" do
      value_of("inspect((1 2) (3 4))").should eq("(1 2) (3 4)")
    end
  end

  # =========================================================================
  # Output formatting (dart-sass parity)
  # =========================================================================
  describe "output formatting" do
    it "separates top-level rule groups with one blank line" do
      compile(".x { a: 1; }\n.y { b: 2; }")
        .should eq(".x {\n  a: 1;\n}\n\n.y {\n  b: 2;\n}\n")
    end

    it "joins rules split from one source rule without blank lines" do
      compile(".x { a: 1; .n { b: 2; } }\n.y { c: 3; }")
        .should eq(".x {\n  a: 1;\n}\n.x .n {\n  b: 2;\n}\n\n.y {\n  c: 3;\n}\n")
    end

    it "adds no blank lines after at-rule statements" do
      css = compile("@media screen { .a { x: 1; } }\n@media print { .b { x: 1; } }")
      css.should eq("@media screen {\n  .a {\n    x: 1;\n  }\n}\n@media print {\n  .b {\n    x: 1;\n  }\n}\n")
    end

    it "adds no blank lines between rules nested in an at-rule" do
      compile("@media screen { .a { x: 1; } .b { x: 2; } }")
        .should contain("}\n  .b {")
    end

    it "keeps a one-line selector list on one line" do
      compile(".a, .b { x: 1; }").should contain(".a, .b {")
    end

    it "preserves the author's selector line breaks" do
      compile(".c,\n.d { x: 1; }").should contain(".c,\n.d {")
    end

    it "keeps resolved nested selector lists on one line" do
      compile(".a { &:hover, &.on { x: 1; } }").should contain(".a:hover, .a.on {")
    end

    it "carries a parent's line break through resolution" do
      css = compile(".m1,\n.m2 { .n & { y: 2; } }")
      css.should contain(".n .m1,\n.n .m2 {")
    end

    it "ignores line breaks of &-carrying nested parts (dart parity)" do
      compile(".p1, .p2 { .q &,\n.r & { y: 1; } }")
        .should contain(".q .p1, .r .p1, .q .p2, .r .p2 {")
    end

    it "repeats a plain nested part's line break per parent (dart parity)" do
      compile(".p1, .p2 { .q,\n.r { y: 1; } }")
        .should contain(".p1 .q,\n.p1 .r, .p2 .q,\n.p2 .r {")
    end

    it "repeats a parent's line break on every combination (dart parity)" do
      compile(".p1,\n.p2 { .q, .r { y: 1; } }")
        .should contain(".p1 .q, .p1 .r,\n.p2 .q,\n.p2 .r {")
    end

    it "formats keyframe selectors without blank lines" do
      css = compile("@keyframes k { from { a: 1; } 50%, 75% { a: 2; } to { a: 3; } }")
      css.should contain("  }\n  50%, 75% {\n")
      css.should_not contain("\n\n")
    end

    it "joins keyframe selector lists onto one line regardless of source breaks" do
      compile("@keyframes k { 0%,\n100% { a: 1; } }").should contain("0%, 100% {")
    end

    it "carries the extender rule's line structure through @extend" do
      css = compile(".t { c: red; }\n.x,\n.y { @extend .t; }")
      css.should contain(".t, .x,\n.y {")
    end
  end

  # =========================================================================
  # Review-pass regressions (2026-08-22)
  # =========================================================================
  describe "review-pass regressions" do
    it "keeps a literal null out of composite interpolations" do
      compile("p { x: pre\#{null 1px}post; }").should contain("x: pre1pxpost;")
      # An all-null interpolation empties the value; the declaration and
      # its now-empty rule are dropped (dart-sass).
      compile("q { y: \#{null null}; }").should eq("")
    end

    it "does not divide a constructed slash list" do
      # dart-sass errors on math over list.slash; strict contexts do too.
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /comparison requires numbers/) do
        compile(%(@use "sass:list";\n$s: list.slash(4, 2);\n.a { @if $s < 3 { b: 1; } }))
      end
    end

    it "still round-trips a chained slash list intact" do
      css = compile(%(@use "sass:list";\n$sl: list.slash(1, 2, 3);\n.a { e: length($sl); f: inspect($sl); }))
      css.should contain("e: 3;")
      css.should contain("f: 1 / 2 / 3;")
    end

    it "replaces every occurrence in selector.replace" do
      compile(%(@use "sass:selector";\n.a { r: selector.replace(".b .b", ".b", ".c"); }))
        .should contain("r: .c .c;")
    end

    it "folds calc(min()) across unitless and united operands" do
      value_of("calc(min(5, 2px))").should eq("2px")
    end

    it "lets a lazy division by zero lose a min()" do
      value_of("min(10 / 0, 8)").should eq("8")
    end
  end
end
