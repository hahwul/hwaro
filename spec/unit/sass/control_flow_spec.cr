require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe "Sass control flow" do
  # ===========================================================================
  # @if / @else if / @else
  # ===========================================================================
  it "takes the @if branch when the condition is truthy" do
    css = compile(<<-SCSS)
      $dark: true;
      .a { @if $dark { color: white; } @else { color: black; } }
      SCSS
    css.should contain("color: white;")
    css.should_not contain("color: black;")
  end

  it "takes @else when the condition is false" do
    css = compile(".a { @if false { color: white; } @else { color: black; } }")
    css.should contain("color: black;")
  end

  it "walks an @else if chain in order" do
    css = compile(<<-SCSS)
      $size: medium;
      .a {
        @if $size == small { width: 1px; }
        @else if $size == medium { width: 2px; }
        @else { width: 3px; }
      }
      SCSS
    css.should contain("width: 2px;")
    css.should_not contain("width: 1px;")
    css.should_not contain("width: 3px;")
  end

  it "treats null and false as falsey, everything else as truthy" do
    css = compile(<<-SCSS)
      .a { @if null { color: red; } @else { color: green; } }
      .b { @if 0 { color: blue; } }
      .c { @if "" { color: teal; } }
      SCSS
    css.should contain("color: green;")
    css.should contain("color: blue;") # 0 is truthy in Sass
    css.should contain("color: teal;")
  end

  it "supports comparisons, and/or/not, and parens in conditions" do
    css = compile(<<-SCSS)
      $w: 500px;
      .a { @if $w > 300px and $w <= 500px { width: ok; } }
      .b { @if not ($w == 500px) { width: no; } @else { width: yes; } }
      SCSS
    css.should contain("width: ok;")
    css.should contain("width: yes;")
  end

  it "supports @if inside mixins with @content" do
    css = compile(<<-SCSS)
      @mixin respond($compact) {
        @if $compact { @media (max-width: 600px) { @content; } }
        @else { @content; }
      }
      .a { @include respond(true) { padding: 1rem; } }
      SCSS
    css.should contain("@media (max-width: 600px) {\n  .a {\n    padding: 1rem;")
  end

  it "errors on an unparseable condition with a location" do
    ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable/) do
      compile(".a { @if $missing { color: red; } }", path: "c.scss")
    end
    ex.path.should eq("c.scss")
  end

  it "does not leak variables declared inside a branch" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable: "\$inner"/) do
      compile("@if true { $inner: 1; }\n.a { width: $inner; }")
    end
  end

  it "assigns outer variables from inside a branch" do
    css = compile(<<-SCSS)
      $c: red;
      @if true { $c: blue; }
      .a { color: $c; }
      SCSS
    css.should contain("color: blue;")
  end

  # ===========================================================================
  # @each
  # ===========================================================================
  it "iterates a comma list and interpolates into selectors" do
    css = compile(<<-'SCSS')
      @each $name in success, warning, error {
        .alert-#{$name} { border-color: $name; }
      }
      SCSS
    css.should contain(".alert-success {")
    css.should contain(".alert-warning {")
    css.should contain("border-color: error;")
  end

  it "iterates a space list stored in a variable" do
    css = compile(<<-'SCSS')
      $sizes: 4px 8px;
      @each $s in $sizes { .p-#{$s} { padding: $s; } }
      SCSS
    css.should contain(".p-4px {\n  padding: 4px;")
    css.should contain(".p-8px {\n  padding: 8px;")
  end

  it "destructures map entries into key/value variables" do
    css = compile(<<-'SCSS')
      @each $name, $size in (small: 4px, large: 16px) {
        .m-#{$name} { margin: $size; }
      }
      SCSS
    css.should contain(".m-small {\n  margin: 4px;")
    css.should contain(".m-large {\n  margin: 16px;")
  end

  it "destructures nested lists and fills missing values with null" do
    css = compile(<<-'SCSS')
      @each $a, $b in (x 1, y) {
        .#{$a} { n: $b; }
      }
      SCSS
    css.should contain(".x {\n  n: 1;")
    # null value omits the declaration; the empty .y rule disappears.
    css.should_not contain(".y")
  end

  it "errors when iterating null" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /may not iterate over null/) do
      compile("@each $x in null { .a { width: $x; } }")
    end
  end

  # ===========================================================================
  # @for
  # ===========================================================================
  it "iterates from..through inclusively" do
    css = compile(<<-'SCSS')
      @for $i from 1 through 3 { .col-#{$i} { width: $i * 10px; } }
      SCSS
    css.should contain(".col-1 {\n  width: 10px;")
    css.should contain(".col-3 {\n  width: 30px;")
  end

  it "iterates from..to exclusively" do
    css = compile(<<-'SCSS')
      @for $i from 1 to 3 { .col-#{$i} { width: $i * 10px; } }
      SCSS
    css.should contain(".col-2 {")
    css.should_not contain(".col-3")
  end

  it "iterates downward when from > through" do
    css = compile(<<-'SCSS')
      @for $i from 3 through 1 { .z-#{$i} { z-index: $i; } }
      SCSS
    css.index!(".z-3").should be < css.index!(".z-1")
  end

  it "accepts computed bounds" do
    css = compile(<<-'SCSS')
      $n: 2;
      @for $i from 1 through $n + 1 { .c-#{$i} { order: $i; } }
      SCSS
    css.should contain(".c-3 {")
  end

  it "errors on non-integer bounds" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /must be an integer/) do
      compile("@for $i from 1 through 2.5 { .a { order: $i; } }")
    end
  end

  # ===========================================================================
  # @while
  # ===========================================================================
  it "loops while the condition holds" do
    css = compile(<<-'SCSS')
      $i: 1;
      @while $i <= 3 {
        .w-#{$i} { width: $i * 2px; }
        $i: $i + 1;
      }
      SCSS
    css.should contain(".w-1 {\n  width: 2px;")
    css.should contain(".w-3 {\n  width: 6px;")
    css.should_not contain(".w-4")
  end

  it "errors instead of hanging on an infinite loop" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /exceeded .* iterations/) do
      compile("$i: 1;\n@while $i > 0 { .a { width: 1px; } }")
    end
  end

  # ===========================================================================
  # @debug / @warn / @error
  # ===========================================================================
  it "fails the build with the @error message" do
    ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /unknown theme dark/) do
      compile(%q(@error "unknown theme dark";), path: "e.scss")
    end
    ex.path.should eq("e.scss")
  end

  it "interpolates values into @error messages" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /got 42/) do
      compile("$x: 42;\n@error \"got \" + $x;")
    end
  end

  it "continues compiling after @warn and @debug" do
    css = compile(<<-SCSS)
      @warn "heads up";
      @debug 1 + 1;
      .a { color: red; }
      SCSS
    css.should contain(".a {")
  end

  # ===========================================================================
  # @at-root
  # ===========================================================================
  it "escapes style-rule nesting" do
    css = compile(".parent { @at-root .child { color: red; } }")
    css.should contain(".child {\n  color: red;")
    css.should_not contain(".parent .child")
  end

  it "supports the bare block form" do
    css = compile(".parent { @at-root { .a { color: red; } .b { color: blue; } } }")
    css.should contain(".a {\n  color: red;")
    css.should_not contain(".parent .a")
  end

  it "stays inside a surrounding @media" do
    css = compile(".p { @media print { @at-root .q { color: red; } } }")
    css.should contain("@media print {\n  .q {\n    color: red;")
  end

  it "rejects with/without queries" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /queries are not supported/) do
      compile(".a { @at-root (without: media) { color: red; } }")
    end
  end
end
