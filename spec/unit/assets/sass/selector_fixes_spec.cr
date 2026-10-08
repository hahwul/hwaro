# Selector handling: `&` inside selector pseudos, backslash escapes in
# selectors, and pseudo-element ordering after @extend unification.

require "../../../spec_helper"

private def compile_source(source : String) : String
  Hwaro::Assets::Sass.compile(source, "selectors.scss")
end

describe "Sass selector fixes" do
  describe "& inside a selector pseudo's argument" do
    it "substitutes the whole parent list once" do
      css = compile_source(".a, .b { :not(&) { c: d } }")
      css.should contain(":not(.a, .b) {")
      css.should_not contain(":not(.a),")
    end

    it "interleaves the parent list with the other arguments (dart-sass order)" do
      compile_source(".a, .b { :is(&, .h) { c: d } }").should contain(":is(.a, .h, .b) {")
    end

    it "applies a suffix to every parent and keeps the compound prefix" do
      compile_source(".a, .b { .x:not(&-y) { c: e } }").should contain(".x:not(.a-y, .b-y) {")
    end

    it "keeps a top-level & as a per-parent slot" do
      compile_source(".a, .b { & :not(&) { c: f } }").should contain(".a :not(.a, .b), .b :not(.a, .b) {")
    end

    it "recurses into nested selector pseudos" do
      compile_source(".a, .b { :not(:is(&)) { c: g } }").should contain(":not(:is(.a, .b)) {")
    end

    it "leaves a single parent unchanged" do
      compile_source(".a { :not(&) { c: d } }").should contain(":not(.a) {")
    end

    it "resolves the same way under @at-root" do
      compile_source(".a, .b { @at-root :not(&) { c: d } }").should contain(":not(.a, .b) {")
    end
  end

  describe "backslash escapes" do
    it "lets @extend target an escaped class name" do
      css = compile_source(".sm\\:flex { display: flex }\n.h\\:i { @extend .sm\\:flex; }")
      css.should contain(".sm\\:flex, .h\\:i {")
    end

    it "does not read an escaped dot as a class when extending" do
      ex = expect_raises(Hwaro::Assets::Sass::SyntaxError) do
        compile_source(".q\\.r { x: 1 }\n.s { @extend .r }")
      end
      ex.message.to_s.should contain("was not found")
    end

    it "keeps an escaped & literal in a nested selector" do
      compile_source(".f { .g\\&h { x: 1 } }").should contain(".f .g\\&h {")
    end

    it "does not split a selector list on an escaped comma" do
      compile_source(".p { .c\\,d, .e { x: y } }").should contain(".p .c\\,d, .p .e {")
    end
  end

  describe "@extend unification" do
    it "puts pseudo-elements after pseudo-classes" do
      css = compile_source(".btn:hover { color: red }\n.icon::before { @extend .btn; content: \"x\" }")
      css.should contain(".btn:hover, .icon:hover::before {")
    end

    it "treats the legacy single-colon pseudo-elements the same way" do
      css = compile_source(".btn:hover { color: red }\n.i:after { @extend .btn; }")
      css.should contain(".i:hover:after")
    end
  end

  describe "@extend into selector pseudo arguments" do
    it "folds every extender into one rewritten selector (no factorial blow-up)" do
      extenders = (1..8).map { |n| ".e#{n} { @extend .a; }" }.join("\n")
      css = compile_source(".a { x: 1 }\n.k:not(.a) { u: 6 }\n:is(.a, .z) .q { v: 1 }\n#{extenders}")
      css.should contain(".k:not(.a), .k:not(.a, .e1, .e2, .e3, .e4, .e5, .e6, .e7, .e8) {")
      css.should contain(":is(.a, .z) .q, :is(.a, .z, .e1, .e2, .e3, .e4, .e5, .e6, .e7, .e8) .q {")
    end

    it "still resolves chained extends through a pseudo argument" do
      css = compile_source(".k:not(.a) { u: 6 }\n.a { x: 1 }\n.b { @extend .a }\n.c { @extend .b }")
      css.should contain(".k:not(.a), .k:not(.a, .b, .c) {")
    end

    it "extends every pseudo occurrence of the target in one selector" do
      extenders = (1..3).map { |n| ".e#{n} { @extend .a; }" }.join("\n")
      css = compile_source(".a { x: 1 }\n.w:not(.a):not(.a) { u: 6 }\n.v:not(.a):is(.a) { u: 7 }\n#{extenders}")
      css.should contain(".w:not(.a):not(.a), .w:not(.a, .e1, .e2, .e3):not(.a, .e1, .e2, .e3) {")
      css.should contain(".v:not(.a):is(.a), .v:not(.a, .e1, .e2, .e3):is(.a, .e1, .e2, .e3) {")
    end
  end
end
