require "../../spec_helper"
require "../../../src/assets/sass"

private def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

describe "Sass @extend" do
  # ===========================================================================
  # Placeholder selectors
  # ===========================================================================
  it "never emits un-extended placeholder rules" do
    css = compile("%btn { color: red; }\n.a { b: 1; }")
    css.should_not contain("%btn")
    css.should_not contain("color: red")
    css.should contain(".a {")
  end

  it "drops placeholder members from selector lists but keeps the rest" do
    css = compile("%p, .real { color: red; }")
    css.should_not contain("%p")
    css.should contain(".real {\n  color: red;")
  end

  it "drops nested rules whose resolved selector contains a placeholder" do
    css = compile("%btn { color: red; &:hover { color: blue; } }")
    css.should_not contain("%btn")
    css.should_not contain(":hover")
  end

  it "does not treat keyframe percentages as placeholders" do
    css = compile("@keyframes spin { 50% { opacity: 0.5; } }")
    css.should contain("50% {")
  end

  # ===========================================================================
  # Basic extension
  # ===========================================================================
  it "extends a class selector" do
    css = compile(".error { border: red; }\n.fatal { @extend .error; font-weight: bold; }")
    css.should contain(".error,\n.fatal {\n  border: red;")
    css.should contain(".fatal {\n  font-weight: bold;")
  end

  it "extends a placeholder and scrubs it" do
    css = compile("%vh { position: absolute; }\n.sr-only { @extend %vh; }")
    css.should contain(".sr-only {\n  position: absolute;")
    css.should_not contain("%vh")
  end

  it "extends every rule containing the target, compounds included" do
    css = compile(<<-SCSS)
      .b.c { x: 1; }
      .b:hover { y: 2; }
      a.b { z: 3; }
      .a { @extend .b; }
      SCSS
    css.should contain(".a.c")
    css.should contain(".a:hover")
    css.should contain("a.a")
  end

  it "keeps the element selector first when unifying" do
    css = compile("a.b { z: 3; }\n.c { @extend .b; }")
    css.should contain("a.c")
    css.should_not contain(".ca")
  end

  it "skips unification when element selectors conflict" do
    css = compile("div.b { z: 3; }\nspan.x { @extend .b; }")
    css.should contain("div.b {")
    css.should_not contain("divspan")
    css.should_not contain("spandiv")
  end

  it "prepends the extender's ancestor compounds" do
    css = compile(".t { c: red; }\n.x .y { @extend .t; }")
    css.should contain(".t,\n.x .y {")
  end

  it "merges a shared leading prefix instead of duplicating it" do
    # The Bootstrap navbar shape: a placeholder nested under .navbar,
    # extended from `.navbar > .container`.
    css = compile(<<-SCSS)
      .navbar {
        %flex { display: flex; }
        > .container { @extend %flex; }
      }
      SCSS
    css.should contain(".navbar > .container {\n  display: flex;")
    css.should_not contain(".navbar .navbar")
  end

  it "extends rules inside at-rules" do
    css = compile("@media print { .b { x: 1; } }\n.a { @extend .b; }")
    css.should contain("@media print {\n  .b,\n  .a {")
  end

  it "supports comma-separated targets" do
    css = compile(".x { a: 1; }\n.y { b: 2; }\n.z { @extend .x, .y; }")
    css.should contain(".x,\n.z {")
    css.should contain(".y,\n.z {")
  end

  it "resolves chained extends through placeholders" do
    css = compile("%x { a: 1; }\n%y { @extend %x; b: 2; }\n.z { @extend %y; }")
    css.should contain(".z {\n  a: 1;")
    css.should contain(".z {\n  b: 2;")
    css.should_not contain("%")
  end

  it "applies extends recorded in @use'd modules" do
    loader = Hwaro::Assets::Sass::MemoryLoader.new({
      "_lib.scss" => "%base { margin: 0; }\n.card { @extend %base; }",
    })
    css = Hwaro::Assets::Sass.compile("@use \"lib\";", path: "main.scss", loader: loader)
    css.should contain(".card {\n  margin: 0;")
    css.should_not contain("%base")
  end

  # ===========================================================================
  # Errors & !optional
  # ===========================================================================
  it "errors on a missing target with a located message" do
    ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /@extend target ".nope" was not found/) do
      compile(".a { @extend .nope; }", path: "e.scss")
    end
    ex.location.should eq("e.scss:1:6")
  end

  it "tolerates a missing target with !optional" do
    css = compile(".a { @extend .nope !optional; b: 1; }")
    css.should contain(".a {\n  b: 1;")
  end

  it "rejects @extend outside a style rule" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /may only be used within style rules/) do
      compile("@extend .a;")
    end
  end

  it "rejects @extend inside @keyframes" do
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /may only be used within style rules/) do
      compile(".a { c: red; }\n@keyframes k { 50% { @extend .a; } }")
    end
  end

  it "supports interpolation in the target" do
    css = compile(".item-2 { c: red; }\n.a { @extend .item-\#{1 + 1}; }")
    css.should contain(".item-2,\n.a {")
  end
end
