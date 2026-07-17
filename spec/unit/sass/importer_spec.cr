require "../../spec_helper"
require "../../../src/assets/sass"

private def compile_with(files : Hash(String, String), entry : String) : String
  loader = Hwaro::Assets::Sass::MemoryLoader.new(files)
  Hwaro::Assets::Sass.compile(files[entry], path: entry, loader: loader)
end

describe "Hwaro::Assets::Sass imports" do
  describe "@import" do
    it "merges partials into the current scope" do
      css = compile_with({
        "sass/_vars.scss" => "$c: #123;",
        "sass/main.scss"  => "@import \"vars\";\n.a { color: $c; }",
      }, "sass/main.scss")
      css.should contain("color: #123;")
    end

    it "emits imported CSS at the import site and re-emits on repeat" do
      css = compile_with({
        "sass/_base.scss" => ".base { margin: 0; }",
        "sass/main.scss"  => "@import \"base\";\n@import \"base\";",
      }, "sass/main.scss")
      css.scan(/\.base \{/).size.should eq(2)
    end

    it "resolves relative to the importing file" do
      css = compile_with({
        "sass/nested/_deep.scss" => ".deep { color: red; }",
        "sass/_mid.scss"         => "@import \"nested/deep\";",
        "sass/main.scss"         => "@import \"mid\";",
      }, "sass/main.scss")
      css.should contain(".deep {")
    end

    it "probes _partial, plain, and index candidates" do
      css = compile_with({
        "sass/lib/_index.scss" => ".lib { color: red; }",
        "sass/main.scss"       => "@import \"lib\";",
      }, "sass/main.scss")
      css.should contain(".lib {")
    end

    it "errors on missing imports with the directive location" do
      ex = expect_raises(Hwaro::Assets::Sass::SyntaxError, /can't find stylesheet to import: "ghost"/) do
        compile_with({"sass/main.scss" => "@import \"ghost\";"}, "sass/main.scss")
      end
      ex.path.should eq("sass/main.scss")
    end

    it "errors when partial and non-partial are ambiguous" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /ambiguous import/) do
        compile_with({
          "sass/_dup.scss" => ".a { color: red; }",
          "sass/dup.scss"  => ".b { color: blue; }",
          "sass/main.scss" => "@import \"dup\";",
        }, "sass/main.scss")
      end
    end

    it "errors on circular imports with the chain" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /circular @use\/@import/) do
        compile_with({
          "sass/_a.scss"   => "@import \"b\";",
          "sass/_b.scss"   => "@import \"a\";",
          "sass/main.scss" => "@import \"a\";",
        }, "sass/main.scss")
      end
    end

    it "rejects imports escaping the project root" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /outside the project directory/) do
        compile_with({"sass/main.scss" => "@import \"../../../../etc/passwd.scss\";"}, "sass/main.scss")
      end
    end
  end

  describe "@use" do
    it "exposes members under the default namespace" do
      css = compile_with({
        "sass/_colors.scss" => "$primary: #123456;\n@mixin themed { border-color: $primary; }",
        "sass/main.scss"    => "@use \"colors\";\n.app { color: colors.$primary; @include colors.themed; }",
      }, "sass/main.scss")
      css.should contain("color: #123456;")
      css.should contain("border-color: #123456;")
    end

    it "supports namespace aliases" do
      css = compile_with({
        "sass/_colors.scss" => "$primary: red;",
        "sass/main.scss"    => "@use \"colors\" as c;\n.a { color: c.$primary; }",
      }, "sass/main.scss")
      css.should contain("color: red;")
    end

    it "merges into globals with as *" do
      css = compile_with({
        "sass/_colors.scss" => "$primary: red;",
        "sass/main.scss"    => "@use \"colors\" as *;\n.a { color: $primary; }",
      }, "sass/main.scss")
      css.should contain("color: red;")
    end

    it "emits module CSS once before the using file" do
      css = compile_with({
        "sass/_base.scss" => ".base { margin: 0; }",
        "sass/_one.scss"  => "@use \"base\";\n.one { color: red; }",
        "sass/_two.scss"  => "@use \"base\";\n.two { color: blue; }",
        "sass/main.scss"  => "@use \"one\";\n@use \"two\";\n.app { color: green; }",
      }, "sass/main.scss")
      css.scan(/\.base \{/).size.should eq(1)
      css.index(".base {").not_nil!.should be < css.index(".one {").not_nil!
      css.index(".one {").not_nil!.should be < css.index(".app {").not_nil!
    end

    it "errors on undefined namespace members" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable: "colors\.\$nope"/) do
        compile_with({
          "sass/_colors.scss" => "$primary: red;",
          "sass/main.scss"    => "@use \"colors\";\n.a { color: colors.$nope; }",
        }, "sass/main.scss")
      end
    end

    it "errors on unknown namespaces" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /no module namespace "ghost"/) do
        compile_with({"sass/main.scss" => ".a { color: ghost.$x; }"}, "sass/main.scss")
      end
    end

    it "errors on namespace collisions" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /namespace "c" is already taken/) do
        compile_with({
          "sass/_a.scss"   => "$x: 1;",
          "sass/_b.scss"   => "$x: 2;",
          "sass/main.scss" => "@use \"a\" as c;\n@use \"b\" as c;",
        }, "sass/main.scss")
      end
    end

    it "allows re-using the same module under the same namespace" do
      css = compile_with({
        "sass/_colors.scss" => "$primary: red;",
        "sass/_widget.scss" => "@use \"colors\";\n.widget { color: colors.$primary; }",
        "sass/main.scss"    => "@use \"colors\";\n@use \"widget\";\n.a { color: colors.$primary; }",
      }, "sass/main.scss")
      css.should contain(".widget {")
      css.should contain(".a {")
    end
  end
end
