require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe Hwaro::Assets::Sass do
  describe ".compile" do
    # =========================================================================
    # Variables & scoping
    # =========================================================================
    it "substitutes variables in values" do
      css = compile("$c: #336699;\n.a { color: $c; }")
      css.should contain("color: #336699;")
    end

    it "shadows outer variables in nested rules" do
      css = compile(<<-'SCSS')
      $c: red;
      .outer {
        $c: blue;
        color: $c;
        .inner { color: $c; }
      }
      .after { color: $c; }
      SCSS
      css.should contain(".outer {\n  color: blue;")
      css.should contain(".outer .inner {\n  color: blue;")
      css.should contain(".after {\n  color: red;")
    end

    it "honors !default only when unset" do
      css = compile("$a: 1px;\n$a: 2px !default;\n$b: 3px !default;\n.x { margin: $a; padding: $b; }")
      css.should contain("margin: 1px;")
      css.should contain("padding: 3px;")
    end

    it "writes root scope with !global" do
      css = compile(<<-'SCSS')
      $c: red;
      .a { $c: blue !global; }
      .b { color: $c; }
      SCSS
      css.should contain(".b {\n  color: blue;")
    end

    it "treats hyphens and underscores as equivalent in identifiers" do
      css = compile(<<-'SCSS')
      $brand-color: #123;
      .a { color: $brand_color; }
      .b { color: $brand-color; }
      SCSS
      css.should contain(".a {\n  color: #123;")
      css.should contain(".b {\n  color: #123;")
    end

    it "errors on undefined variables with a location" do
      ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable: "\$missing"/) do
        compile(".a { color: $missing; }", path: "y.scss")
      end
      ex.path.should eq("y.scss")
      ex.line.should eq(1)
    end

    # =========================================================================
    # Nesting & parent selector
    # =========================================================================
    it "flattens nested rules with descendant combinators" do
      css = compile(".a { .b { color: red; } }")
      css.should contain(".a .b {")
    end

    it "combines selector lists as a cartesian product" do
      css = compile(".a, .b { .c & { color: red; } }")
      css.should contain(".c .a,\n.c .b {")
    end

    it "substitutes & for pseudo-classes and BEM suffixes" do
      css = compile(".block { &:hover { color: red; } &__elem { color: blue; } }")
      css.should contain(".block:hover {")
      css.should contain(".block__elem {")
    end

    it "keeps & literal inside strings and attribute selectors" do
      css = compile(%q{.a { [data-x="&"] { color: red; } }})
      css.should contain(".a [data-x=\"&\"]")
    end

    it "errors on top-level &" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /top-level selectors may not contain "&"/) do
        compile("&:hover { color: red; }")
      end
    end

    it "errors on nested properties" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /nested properties are not supported/) do
        compile(".a { font: { family: serif; } }")
      end
    end

    # =========================================================================
    # Interpolation
    # =========================================================================
    it "interpolates in selectors, property names, and values" do
      css = compile(<<-'SCSS')
      $name: card;
      $side: left;
      .#{$name} {
        margin-#{$side}: 4px;
        content: "hello #{$name}";
      }
      SCSS
      css.should contain(".card {")
      css.should contain("margin-left: 4px;")
      css.should contain(%q{content: "hello card";})
    end

    it "interpolates in at-rule preludes and substitutes prelude variables" do
      css = compile("$bp: 600px;\n@media (min-width: #{"\#{$bp}"}) { .a { color: red; } }")
      css.should contain("@media (min-width: 600px) {")
      css2 = compile("$bp: 700px;\n@media (min-width: $bp) { .a { color: red; } }")
      css2.should contain("@media (min-width: 700px) {")
    end

    it "errors on unterminated interpolation" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /unterminated/) do
        compile(".a { color: #{"\#{$x"}; }")
      end
    end

    # =========================================================================
    # At-rule bubbling
    # =========================================================================
    it "bubbles @media out of nested rules" do
      css = compile(".a { color: red; @media (min-width: 600px) { color: blue; } }")
      css.should contain("@media (min-width: 600px) {\n  .a {\n    color: blue;")
    end

    it "keeps rules nested inside @media" do
      css = compile("@media print { .a { color: red; } }")
      css.should contain("@media print {\n  .a {\n    color: red;")
    end

    it "bubbles @supports" do
      css = compile(".a { @supports (display: grid) { display: grid; } }")
      css.should contain("@supports (display: grid) {\n  .a {\n    display: grid;")
    end

    it "nests @media inside @media literally" do
      css = compile("@media screen { @media (min-width: 5px) { .a { color: red; } } }")
      css.should contain("@media screen {\n  @media (min-width: 5px) {")
    end

    it "does not join @keyframes frame selectors with outer rules" do
      css = compile(".a { @keyframes spin { from { opacity: 0; } to { opacity: 1; } } }")
      css.should contain("@keyframes spin {")
      css.should contain("  from {")
      css.should_not contain(".a from")
    end

    it "omits empty rules and at-rules" do
      css = compile(".a { }\n@media print { .b { } }")
      css.should_not contain(".a")
      css.should_not contain("@media")
    end

    # =========================================================================
    # Plain-CSS passthrough
    # =========================================================================
    it "passes through @font-face, custom properties, and data URIs" do
      css = compile(<<-'SCSS')
      @charset "utf-8";
      :root { --brand: #f00; --gap:  4px   8px; }
      @font-face { font-family: "X"; src: url(x.woff2) format("woff2"); }
      .grid { background: url(data:image/png;base64,AAA/BBB==); }
      SCSS
      css.should contain(%q{@charset "utf-8";})
      css.should contain("--brand: #f00;")
      css.should contain("--gap: 4px   8px;")
      css.should contain(%q{src: url(x.woff2) format("woff2");})
      css.should contain("url(data:image/png;base64,AAA/BBB==)")
    end

    it "keeps $var literal in custom property values" do
      css = compile("$c: red;\n.a { --x: $c; color: $c; }")
      css.should contain("--x: $c;")
      css.should contain("color: red;")
    end

    it "passes through quoted braces, semicolons, and escapes" do
      css = compile(<<-'SCSS')
      a[href^="https://"]::after { content: " (ext, a{b;c})"; }
      .q { content: "quote \" and brace {"; }
      SCSS
      css.should contain("content: \" (ext, a{b;c})\";")
      css.should contain("content: \"quote \\\" and brace {\";")
    end

    it "preserves !important" do
      css = compile(".a { color: red !important; }")
      css.should contain("color: red !important;")
    end

    it "preserves loud comments and drops silent comments" do
      css = compile("/* keep */\n.a { color: red; // gone\n }")
      css.should contain("/* keep */")
      css.should_not contain("gone")
    end

    it "passes through unknown functions untouched" do
      css = compile(".a { width: calc(100% - 2px); color: rgba(0, 0, 0, 0.5); inset: clamp(1px, 2vw, 3px); }")
      css.should contain("width: calc(100% - 2px);")
      css.should contain("color: rgba(0, 0, 0, 0.5);")
      css.should contain("inset: clamp(1px, 2vw, 3px);")
    end

    it "passes through grid-template-areas string stacks" do
      css = compile(%q{.g { grid-template-areas: "a a" "b b"; }})
      css.should contain(%q{grid-template-areas: "a a" "b b";})
    end

    it "passes through plain-CSS @import forms" do
      css = compile(<<-'SCSS')
      @import url(theme.css);
      @import "https://example.com/x.css";
      @import "print.css" print;
      SCSS
      css.should contain("@import url(theme.css);")
      css.should contain(%q{@import "https://example.com/x.css";})
      css.should contain(%q{@import "print.css" print;})
    end

    it "does not mis-unquote non-string @import arguments" do
      # `"a" + "b"` has matching first/last quotes but is not one string —
      # it must pass through instead of becoming an ImportNode for `a" + "b`.
      css = compile(%q{@import "a" + "b";})
      css.should contain(%q{@import "a" + "b";})
    end

    it "does not wrap descriptor at-rules nested in rules with a selector" do
      css = compile(".a { @font-face { font-family: X; src: url(x.woff2); } }")
      css.should contain("@font-face {\n  font-family: X;")
      css.should_not contain("@font-face {\n  .a")
    end

    # =========================================================================
    # Unsupported directives fail loudly
    # =========================================================================
    %w[if each for while function extend forward at-root].each do |directive|
      it "rejects @#{directive} with a located error" do
        ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /@#{directive} is not supported/) do
          compile("@#{directive} x { color: red; }", path: "d.scss")
        end
        ex.location.should eq("d.scss:1:1")
      end
    end

    it "rejects @use with configuration" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /with \(\.\.\.\) configuration is not supported/) do
        compile(%q{@use "x" with ($a: 1);})
      end
    end

    # =========================================================================
    # Parse errors carry locations
    # =========================================================================
    it "reports unterminated blocks" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /unterminated block/) do
        compile(".a {\n  color: red;")
      end
    end

    it "reports unterminated strings" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /unterminated string/) do
        compile(%q{.a { content: "oops; }})
      end
    end

    it "reports unmatched closing braces" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /unmatched "}"/) do
        compile(".a { color: red; }\n}")
      end
    end

    it "reports a missing colon in a declaration" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /expected "{"/) do
        compile(".a { nonsense; }")
      end
    end
  end
end
