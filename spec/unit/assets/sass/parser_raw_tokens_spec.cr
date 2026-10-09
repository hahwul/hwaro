# Raw-token passthrough in the Sass parser: unquoted `url(//…)` in
# `@import` preludes and `//` inside custom-property values are text,
# never silent comments.

require "../../../spec_helper"

private def compile_source(source : String) : String
  Hwaro::Assets::Sass.compile(source, "raw.scss")
end

describe "Sass raw token passthrough" do
  describe "unquoted url() in @import" do
    it "keeps a protocol-relative url and the rules after it" do
      css = compile_source("@import url(//fonts.googleapis.com/css?family=Lato);\n.a { x: y }")
      css.should contain("@import url(//fonts.googleapis.com/css?family=Lato);")
      css.should contain(".a {")
    end

    it "keeps an http url followed by a media query" do
      css = compile_source("@import url(http://fonts.googleapis.com/css?family=Open+Sans:400,700) screen;\n.a { x: y }")
      css.should contain("@import url(http://fonts.googleapis.com/css?family=Open+Sans:400,700) screen;")
      css.should contain("x: y;")
    end

    it "matches url( case-insensitively and does not substitute $vars" do
      css = compile_source("@import URL(//cdn/x.css);\n@import url($v);\n.a { x: y }")
      css.should contain("@import URL(//cdn/x.css);")
      css.should contain("@import url($v);")
    end

    it "does not treat a longer identifier as url(" do
      compile_source("@import myurl(//x) ;\n.a { x: y }").should contain("@import myurl(")
    end
  end

  describe "custom properties" do
    it "keeps // in a value" do
      css = compile_source(".a { --u: http://a.b/c; x: y }")
      css.should contain("--u: http://a.b/c;")
      css.should contain("x: y;")
    end

    it "keeps // when the terminating semicolon is on the next line" do
      css = compile_source(".a { --u: http://a.b/c\n;\n x: y }")
      css.should contain("--u: http://a.b/c;")
      css.should contain("x: y;")
    end

    it "still strips // comments from ordinary declarations" do
      compile_source(".a { x: y; // note\n z: w }").should_not contain("note")
    end
  end
end
