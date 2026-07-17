require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe "Hwaro::Assets::Sass mixins" do
  it "expands a parameterless mixin" do
    css = compile(<<-'SCSS')
    @mixin reset { margin: 0; padding: 0; }
    .a { @include reset; }
    SCSS
    css.should contain(".a {\n  margin: 0;\n  padding: 0;")
  end

  it "binds positional arguments and defaults" do
    css = compile(<<-'SCSS')
    @mixin button($bg, $fg: white) { background: $bg; color: $fg; }
    .a { @include button(#333); }
    .b { @include button(#333, black); }
    SCSS
    css.should contain(".a {\n  background: #333;\n  color: white;")
    css.should contain(".b {\n  background: #333;\n  color: black;")
  end

  it "binds keyword arguments" do
    css = compile(<<-'SCSS')
    @mixin box($w: 1px, $h: 2px) { width: $w; height: $h; }
    .a { @include box($h: 9px); }
    SCSS
    css.should contain("width: 1px;")
    css.should contain("height: 9px;")
  end

  it "lets defaults reference earlier parameters" do
    css = compile(<<-'SCSS')
    @mixin square($w, $h: $w) { width: $w; height: $h; }
    .a { @include square(5px); }
    SCSS
    css.should contain("height: 5px;")
  end

  it "keeps comma-containing arguments intact inside parens" do
    css = compile(<<-'SCSS')
    @mixin shadow($v) { box-shadow: $v; }
    .a { @include shadow(rgba(0, 0, 0, 0.5) 0 1px); }
    SCSS
    css.should contain("box-shadow: rgba(0, 0, 0, 0.5) 0 1px;")
  end

  it "evaluates @content in the caller's scope" do
    css = compile(<<-'SCSS')
    $c: caller;
    @mixin respond($bp: 768px) {
      $c: mixin;
      @media (min-width: $bp) { @content; }
    }
    .a {
      @include respond(1024px) { content: "#{$c}"; }
    }
    SCSS
    css.should contain("@media (min-width: 1024px) {")
    css.should contain(%q{content: "caller";})
  end

  it "emits nothing for @content without a passed block" do
    css = compile(<<-'SCSS')
    @mixin maybe { @content; }
    .a { color: red; @include maybe; }
    SCSS
    css.should contain(".a {\n  color: red;\n}")
  end

  it "closes over the definition environment" do
    css = compile(<<-'SCSS')
    $theme: dark;
    @mixin themed { content: "#{$theme}"; }
    .a {
      $theme: local;
      @include themed;
    }
    SCSS
    # dart-sass resolves $theme against the innermost matching scope at
    # call time via lexical chain of the definition (root) — the local
    # shadow is invisible to the mixin body.
    css.should contain(%q{content: "dark";})
  end

  it "treats hyphens and underscores as equivalent in mixin and parameter names" do
    css = compile(<<-'SCSS')
    @mixin drop-shadow($shadow-size: 2px) { box-shadow: 0 $shadow-size; }
    .a { @include drop_shadow($shadow_size: 5px); }
    SCSS
    css.should contain("box-shadow: 0 5px;")
  end

  it "errors on undefined mixins" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined mixin: "nope"/) do
      compile(".a { @include nope; }")
    end
  end

  it "errors on unknown keyword arguments" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /no parameter named \$oops/) do
      compile("@mixin m($a: 1) { width: $a; }\n.x { @include m($oops: 2); }")
    end
  end

  it "errors on missing required arguments" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /missing argument \$bg/) do
      compile("@mixin m($bg) { background: $bg; }\n.x { @include m; }")
    end
  end

  it "errors on too many positional arguments" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /takes 1 argument\(s\) but 2 were passed/) do
      compile("@mixin m($a) { width: $a; }\n.x { @include m(1, 2); }")
    end
  end

  it "errors on runaway @include recursion" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /too much recursion/) do
      compile("@mixin loop { @include loop; }\n.x { @include loop; }")
    end
  end

  it "rejects variadic parameters" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /variadic parameters/) do
      compile("@mixin m($args...) { width: 0; }")
    end
  end

  it "rejects @include using clauses" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /using \(\.\.\.\) is not supported/) do
      compile("@mixin m { @content; }\n.x { @include m using ($a) { width: $a; } }")
    end
  end
end
