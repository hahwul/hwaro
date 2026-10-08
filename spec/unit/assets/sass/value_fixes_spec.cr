# Value semantics: live module variables, `&` as a value, plain-CSS function
# arguments, calculation fallbacks, string quoting/escapes, fuzzy numbers
# and map spreads in function calls.

require "../../../spec_helper"
require "file_utils"

private def compile_source(source : String) : String
  Hwaro::Assets::Sass.compile(source, "values.scss")
end

private def with_sass_tree(files : Hash(String, String), &)
  dir = File.tempname("hwaro-sass-values")
  Dir.mkdir_p(dir)
  begin
    files.each do |rel, body|
      path = File.join(dir, rel)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
    end
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "Sass value fixes" do
  describe "module variables are live bindings" do
    it "reads a !global counter bumped by a module function and mixin" do
      with_sass_tree({
        "_vars2.scss" => "$count: 0;\n@function inc() { $count: $count + 1 !global; @return $count }\n" \
                         "@mixin bump { $count: $count + 1 !global; }\n",
        "t.scss" => "@use \"vars2\";\n.u1 { a: vars2.inc(); b: vars2.inc(); c: vars2.$count }\n" \
                    "@include vars2.bump;\n.u2 { c: vars2.$count }\n",
      }) do |dir|
        css = Hwaro::Assets::Sass.compile(File.read(File.join(dir, "t.scss")),
          path: File.join(dir, "t.scss"), root: dir)
        css.should contain("a: 1;")
        css.should contain("b: 2;")
        css.should contain("c: 2;")
        css.should contain("c: 3;")
      end
    end

    it "keeps private members hidden" do
      with_sass_tree({
        "_p.scss" => "$-secret: 1;\n$open: 2;\n",
        "t.scss"  => "@use \"p\";\n.a { b: p.$open }\n",
      }) do |dir|
        css = Hwaro::Assets::Sass.compile(File.read(File.join(dir, "t.scss")),
          path: File.join(dir, "t.scss"), root: dir)
        css.should contain("b: 2;")
      end
    end
  end

  describe "& as a value" do
    it "evaluates a bare & and an interpolated & in declaration values" do
      css = compile_source(".a, .b > c {\n  content: \"\#{&}\";\n  x: \#{&};\n  z: &;\n  $p: &;\n  v: $p;\n  q: \"x \#{&} y\";\n}")
      css.should contain(%(content: ".a, .b > c";))
      css.should contain("x: .a, .b > c;")
      css.should contain("z: .a, .b > c;")
      css.should contain("v: .a, .b > c;")
      css.should contain(%(q: "x .a, .b > c y";))
    end

    it "interpolates the parent selector inside an attribute string" do
      css = compile_source(".a { [data-x=\"\#{&}\"] { c: d } }")
      css.should contain(%(.a [data-x=".a"] {))
    end

    it "keeps an interpolated & in a selector as the verbatim parent reference" do
      compile_source(".a, .b { .e\#{&} { k: l } }").should contain(".e.a, .e.b {")
      compile_source(".a { @at-root \#{&}-s { m: n } }").should contain(".a-s {")
    end
  end

  describe "plain-CSS function arguments in forcing contexts" do
    it "keeps the alpha of rgb()/hsl()/oklch() stored in variables" do
      css = compile_source("$b: rgb(0 128 255 / .5);\n$g: rgba(0 0 0 / 0.25);\n$c: hsl(120 100% 50% / .5);\n" \
                           "$i: oklch(50% 0.2 120 / 0.5);\n.a { b: $b; g: $g; c: $c; i: $i; }")
      css.should contain("b: rgb(0 128 255 / .5);")
      css.should contain("g: rgba(0 0 0 / 0.25);")
      css.should contain("c: hsl(120 100% 50% / .5);")
      css.should contain("i: oklch(50% 0.2 120 / 0.5);")
    end

    it "keeps it through @return, mixin arguments and interpolation" do
      css = compile_source("@function ov() { @return rgb(0 0 0 / 0.5); }\n@mixin m($c) { m: $c }\n" \
                           ".a { r: ov(); @include m(rgb(0 0 0 / 0.5)); s: \#{rgb(0 0 0 / 0.5)}; }")
      css.scan("rgb(0 0 0 / 0.5)").size.should eq(3)
    end

    it "still divides a variable operand and the calc-like math functions" do
      css = compile_source("$v: 4;\n$w: foo($v/2);\n$m: max(10px/2, 1px);\n.a { w: $w; m: $m; }")
      css.should contain("w: foo(2);")
      css.should contain("m: 5px;")
    end
  end

  describe "min()/max()/clamp() with incompatible units" do
    it "stays an opaque calculation inside a map" do
      css = compile_source("@use \"sass:map\";\n$fluid: (h1: clamp(2rem, 1rem + 3vw, 4rem), body: 1rem);\n" \
                           "@each $name, $size in $fluid { .text-\#{$name} { font-size: $size; } }\n" \
                           ".x { font-size: map.get($fluid, h1); }")
      css.should contain(".text-h1 {\n  font-size: clamp(2rem, 1rem + 3vw, 4rem);")
      css.should contain(".text-body {\n  font-size: 1rem;")
      css.should contain(".x {\n  font-size: clamp(2rem, 1rem + 3vw, 4rem);")
    end

    it "can be returned from a function and passed to one" do
      css = compile_source("@function f1() { @return clamp(1rem, 2vw + 1rem, 2rem); }\n" \
                           "@function f2() { @return min(100% - 10px, 20rem); }\n" \
                           "@function f3() { @return max(1vw, 10px); }\n" \
                           "@function pass($v) { @return $v }\n" \
                           ".a { a: f1(); b: f2(); c: f3(); d: pass(min(1px, 2vw)); }")
      css.should contain("a: clamp(1rem, 2vw + 1rem, 2rem);")
      css.should contain("b: min(100% - 10px, 20rem);")
      css.should contain("c: max(1vw, 10px);")
      css.should contain("d: min(1px, 2vw);")
    end

    it "counts as one list item and is truthy in @if" do
      css = compile_source("@use \"sass:list\";\n$l: clamp(2rem, 1rem + 3vw, 4rem) 1;\n" \
                           ".a { n: list.length($l); }\n@if min(100% - 10px, 20rem) { .z { ok: yes } }")
      css.should contain("n: 2;")
      css.should contain(".z {")
    end

    it "still folds compatible units and keeps raising for math.min" do
      compile_source(".a { x: min(1px, 2px); }").should contain("x: 1px;")
      expect_raises(Hwaro::Assets::Sass::SyntaxError) do
        compile_source("@use \"sass:math\";\n@function f() { @return math.max(1vw, 10px); }\n.a { x: f(); }")
      end
    end
  end

  describe "quoted strings holding their own quote" do
    it "re-quotes interpolated text" do
      compile_source("$msg: \"Don't\";\n.a { content: '\#{$msg}'; }").should contain(%(content: "Don't";))
      compile_source("@mixin tip($t) { &::after { content: '\#{$t}'; } }\n.b { @include tip(\"Can't\"); }")
        .should contain(%(content: "Can't";))
    end

    it "re-quotes concatenation and string.quote" do
      css = compile_source("@use \"sass:string\";\n$msg: \"Don't\"; $q: 'a\"b';\n" \
                           ".a { c: 'x' + $msg; d: \"x\" + $q; e: \"\#{$q}\"; q: string.quote($q); }")
      css.should contain(%(c: "xDon't";))
      css.should contain(%(d: 'xa"b';))
      css.should contain(%(e: 'a"b';))
      css.should contain(%(q: 'a"b';))
    end

    it "escapes the quote when the text holds both" do
      compile_source(".a { f: \"a'b\" + 'c\"d'; }").should contain(%(f: "a'bc\\"d";))
    end

    it "leaves valid strings untouched" do
      css = compile_source(".a { g: \"ok\"; h: 'ok2'; i: \"esc\\\"aped\"; j: 'it\\'s'; }")
      css.should contain(%(g: "ok";))
      css.should contain(%(h: 'ok2';))
      css.should contain(%(i: "esc\\"aped";))
      css.should contain(%(j: 'it\\'s';))
    end
  end

  describe "fuzzy numbers" do
    it "compares within 1e-11" do
      css = compile_source(".a { i: 0.1 * 3 == 0.3; j: 0.1 * 3 > 0.3; k: 0.1 * 3 <= 0.3; l: 1 < 1.0000001; }")
      css.should contain("i: true;")
      css.should contain("j: false;")
      css.should contain("k: true;")
      css.should contain("l: true;")
    end
  end

  describe "map spread in a function call" do
    it "binds as keyword arguments for user functions" do
      css = compile_source("@function k($a: 0, $b: 0) { @return $a - $b; }\n$kw: (a: 10, b: 3);\n.x { a: k($kw...); b: k(5, $b: 2); }")
      css.should contain("a: 7;")
      css.should contain("b: 3;")
    end

    it "reaches meta.keywords and built-ins" do
      css = compile_source("@use \"sass:meta\"; @use \"sass:list\"; @use \"sass:color\";\n" \
                           "@function g($args...) { @return list.length($args) meta.inspect(meta.keywords($args)); }\n" \
                           "$kw: (a: 10, b: 3); $ca: (\"red\": 10, \"green\": 20);\n.y { b: g($kw...); c: color.adjust(#000, $ca...); }")
      css.should contain("b: 0 (a: 10, b: 3);")
      css.should contain("c: #0a1400;")
    end
  end

  describe "escapes in string functions" do
    it "counts, slices, searches and compares decoded code points" do
      css = compile_source("@use \"sass:string\";\n$q: \"a\\\"b\"; $i: \"\\e900\"; $n: \"x\\\\y\";\n" \
                           ".a { l1: string.length($q); l2: string.length($i); l3: string.length($n); " \
                           "s2: string.slice($i, 1, 1); e1: $i == \"\\E900\"; i1: string.index($q, \"b\"); " \
                           "u2: string.length(string.unquote($i)); }")
      css.should contain("l1: 3;")
      css.should contain("l2: 1;")
      css.should contain("l3: 3;")
      css.should contain(%(s2: "\\e900";))
      css.should contain("e1: true;")
      css.should contain("i1: 3;")
      css.should contain("u2: 1;")
    end

    it "never cuts an escape in half" do
      compile_source("@use \"sass:string\";\n.a { s: string.slice(\"a\\\"b\", 2, 2); t: string.slice(\"a\\\\b\", 2, 2); }")
        .should contain(%(s: '"';))
    end

    it "keeps a concatenated hex escape from absorbing the next digit" do
      css = compile_source(".a { c1: \"\\f101\" + \"a\"; c2: \"\\f101\" + \"z\"; c3: \"ab\" + \"cd\"; }")
      css.should contain(%(c1: "\\f101 a";))
      css.should contain(%(c2: "\\f101z";))
      css.should contain(%(c3: "abcd";))
    end
  end
end
