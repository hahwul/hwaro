require "../../spec_helper"
require "../../../src/assets/sass"

private def compile_with(files : Hash(String, String), entry : String) : String
  loader = Hwaro::Assets::Sass::MemoryLoader.new(files)
  Hwaro::Assets::Sass.compile(files[entry], path: entry, loader: loader)
end

describe "Sass module system extensions" do
  # ===========================================================================
  # @use ... with (...)
  # ===========================================================================
  describe "@use with configuration" do
    it "overrides !default variables" do
      css = compile_with({
        "sass/_theme.scss" => "$primary: red !default;\n$radius: 2px !default;",
        "sass/main.scss"   => "@use \"theme\" with ($primary: blue);\n.a { color: theme.$primary; border-radius: theme.$radius; }",
      }, "sass/main.scss")
      css.should contain("color: blue;")
      css.should contain("border-radius: 2px;")
    end

    it "configures values the module builds on" do
      css = compile_with({
        "sass/_theme.scss" => "$base: 4px !default;\n$double: $base * 2;",
        "sass/main.scss"   => "@use \"theme\" with ($base: 10px);\n.a { padding: theme.$double; }",
      }, "sass/main.scss")
      css.should contain("padding: 20px;")
    end

    it "errors when configuring a variable not declared with !default" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /not declared with !default/) do
        compile_with({
          "sass/_theme.scss" => "$fixed: red;",
          "sass/main.scss"   => "@use \"theme\" with ($fixed: blue);",
        }, "sass/main.scss")
      end
    end

    it "errors when configuring an already-loaded module" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /already loaded/) do
        compile_with({
          "sass/_theme.scss" => "$p: red !default;",
          "sass/_mid.scss"   => "@use \"theme\";",
          "sass/main.scss"   => "@use \"mid\";\n@use \"theme\" with ($p: blue);",
        }, "sass/main.scss")
      end
    end
  end

  # ===========================================================================
  # @forward
  # ===========================================================================
  describe "@forward" do
    it "re-exports variables, mixins, and functions" do
      css = compile_with({
        "sass/_helpers.scss" => <<-SCSS,
          $gap: 8px;
          @mixin center { display: flex; justify-content: center; }
          @function double($n) { @return $n * 2; }
          SCSS
        "sass/_lib.scss" => "@forward \"helpers\";",
        "sass/main.scss" => <<-SCSS,
          @use "lib";
          .a { margin: lib.$gap; width: lib.double(4px); @include lib.center; }
          SCSS
      }, "sass/main.scss")
      css.should contain("margin: 8px;")
      css.should contain("width: 8px;")
      css.should contain("display: flex;")
    end

    it "does not bring forwarded members into the forwarding file's own scope" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable/) do
        compile_with({
          "sass/_helpers.scss" => "$gap: 8px;",
          "sass/_lib.scss"     => "@forward \"helpers\";\n.lib { margin: $gap; }",
          "sass/main.scss"     => "@use \"lib\";",
        }, "sass/main.scss")
      end
    end

    it "emits forwarded CSS once" do
      css = compile_with({
        "sass/_base.scss" => ".base { margin: 0; }",
        "sass/_lib.scss"  => "@forward \"base\";",
        "sass/main.scss"  => "@use \"lib\";\n@use \"base\";\n.a { color: red; }",
      }, "sass/main.scss")
      css.scan(/\.base \{/).size.should eq(1)
    end

    it "applies show filters" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable/) do
        compile_with({
          "sass/_helpers.scss" => "$shown: 1px;\n$hidden: 2px;",
          "sass/_lib.scss"     => "@forward \"helpers\" show $shown;",
          "sass/main.scss"     => "@use \"lib\";\n.a { width: lib.$hidden; }",
        }, "sass/main.scss")
      end
    end

    it "applies hide filters and as-prefixes" do
      css = compile_with({
        "sass/_helpers.scss" => "$gap: 8px;\n@function pad($n) { @return $n + 1px; }",
        "sass/_lib.scss"     => "@forward \"helpers\" as h-* hide pad;",
        "sass/main.scss"     => "@use \"lib\";\n.a { margin: lib.$h-gap; }",
      }, "sass/main.scss")
      css.should contain("margin: 8px;")

      expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined function/) do
        compile_with({
          "sass/_helpers.scss" => "@function pad($n) { @return $n + 1px; }",
          "sass/_lib.scss"     => "@forward \"helpers\" as h-* hide h-pad;",
          "sass/main.scss"     => "@use \"lib\";\n.a { @if lib.h-pad(1px) { width: 0; } }",
        }, "sass/main.scss")
      end
    end

    it "own members win over forwarded members" do
      css = compile_with({
        "sass/_helpers.scss" => "$gap: 8px;",
        "sass/_lib.scss"     => "@forward \"helpers\";\n$gap: 16px;",
        "sass/main.scss"     => "@use \"lib\";\n.a { margin: lib.$gap; }",
      }, "sass/main.scss")
      css.should contain("margin: 16px;")
    end

    it "detects @forward cycles" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /circular/) do
        compile_with({
          "sass/_a.scss"   => "@forward \"b\";",
          "sass/_b.scss"   => "@forward \"a\";",
          "sass/main.scss" => "@use \"a\";",
        }, "sass/main.scss")
      end
    end

    it "rejects show and hide together" do
      expect_raises(Hwaro::Assets::Sass::SyntaxError, /both show and hide/) do
        compile_with({
          "sass/_h.scss"   => "$x: 1;",
          "sass/main.scss" => "@forward \"h\" show $x hide $x;",
        }, "sass/main.scss")
      end
    end
  end
end
