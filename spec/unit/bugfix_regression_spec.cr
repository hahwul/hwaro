require "../spec_helper"
require "../../src/content/processors/inline_markdown"
require "../../src/content/processors/table_parser"
require "../../src/content/processors/template"
require "../../src/utils/text_utils"
require "../../src/utils/js_minifier"
require "../../src/utils/html_minifier"

# Regression coverage for latent bugs fixed during the source-code audit.
# Each block names the class of defect it guards against.

private def render_filter(template_str : String, vars : Hash(String, Crinja::Value) = {} of String => Crinja::Value) : String
  Hwaro::Content::Processors::TemplateEngine.new.render(template_str, vars)
end

describe "bugfix regressions" do
  describe "InlineMarkdown.safe_url? (XSS)" do
    it "blocks control-character-obfuscated script schemes" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("java%09script:alert(1)").should be_false
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("java%0Ascript:alert(1)").should be_false
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("java%0Dscript:alert(1)").should be_false
    end

    it "still allows ordinary links" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("https://example.com/a%20b").should be_true
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("/relative/path").should be_true
    end

    it "still blocks plain javascript: links" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("javascript:alert(1)").should be_false
    end
  end

  describe "InlineMarkdown.render (double escaping)" do
    it "does not double-escape ampersands in link URLs" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("[x](https://e.com/?a=1&b=2)")
      out.should contain("href=\"https://e.com/?a=1&amp;b=2\"")
      out.should_not contain("&amp;amp;")
    end
  end

  describe "TableParser fenced code blocks" do
    it "does not convert a pipe table inside a fenced code block" do
      md = "```\n| H1 | H2 |\n|----|----|\n| a  | b  |\n```"
      out = Hwaro::Content::Processors::TableParser.process(md)
      out.should_not contain("<table")
      out.should contain("| H1 | H2 |")
    end

    it "still converts a real table outside a fence" do
      md = "| H1 | H2 |\n|----|----|\n| a  | b  |"
      Hwaro::Content::Processors::TableParser.process(md).should contain("<table")
    end
  end

  describe "TextUtils.safe_slugify (collisions)" do
    it "never returns an empty slug" do
      Hwaro::Utils::TextUtils.safe_slugify("!!!").empty?.should be_false
      Hwaro::Utils::TextUtils.safe_slugify("🎉").empty?.should be_false
    end

    it "keeps distinct all-symbol terms distinct and stable" do
      a = Hwaro::Utils::TextUtils.safe_slugify("!!!")
      b = Hwaro::Utils::TextUtils.safe_slugify("???")
      a.should_not eq(b)
      a.should eq(Hwaro::Utils::TextUtils.safe_slugify("!!!"))
    end

    it "matches slugify for normal input" do
      Hwaro::Utils::TextUtils.safe_slugify("Hello World").should eq("hello-world")
    end
  end

  describe "TextUtils.escape_xml (illegal control chars)" do
    it "drops XML-1.0-illegal control characters" do
      Hwaro::Utils::TextUtils.escape_xml("abc").should eq("abc")
    end

    it "preserves tab, LF and CR" do
      Hwaro::Utils::TextUtils.escape_xml("a\tb\nc\rd").should eq("a\tb\nc\rd")
    end

    it "preserves DEL (0x7F, a legal XML char) on both fast and slow paths" do
      Hwaro::Utils::TextUtils.escape_xml("ab").should eq("ab")      # fast path
      Hwaro::Utils::TextUtils.escape_xml("a<b").should eq("a&lt;b") # slow path agrees
    end

    it "still escapes the five XML special characters" do
      Hwaro::Utils::TextUtils.escape_xml("a & b < c > \"d\" 'e'").should eq("a &amp; b &lt; c &gt; &quot;d&quot; &apos;e&apos;")
    end
  end

  describe "JsMinifier template literals" do
    it "preserves blank lines inside a template literal" do
      Hwaro::Utils::JsMinifier.minify("const t = `line1\n\nline2`; var a=1;").should contain("line1\n\nline2")
    end

    it "preserves significant trailing whitespace inside a template literal" do
      Hwaro::Utils::JsMinifier.minify("const css = `body {\n  color: red;   \n}`;").should contain("color: red;   ")
    end

    it "still collapses blank lines in plain code" do
      Hwaro::Utils::JsMinifier.minify("var a=1;\n\n\nvar b=2;").includes?("\n\n").should be_false
    end
  end

  describe "HtmlMinifier nested protected blocks" do
    it "restores nested placeholders without leaking sentinels" do
      out = Hwaro::Utils::HtmlMinifier.minify(%(<div> <script>var x = "<style>body{}</style>";</script> </div>))
      out.includes?(String.new(Bytes[0])).should be_false
      out.should_not contain("HW_HTML_")
      out.should contain("<style>body{}</style>")
    end
  end

  describe "jsonify filter" do
    it "serializes arrays/numbers/hashes as real JSON" do
      render_filter(%({{ [1, 2, 3] | jsonify }})).should eq("[1,2,3]")
      render_filter(%({{ 42 | jsonify }})).should eq("42")
    end
  end

  describe "sort_by filter (numeric)" do
    it "sorts numeric attributes numerically, not lexicographically" do
      arr = [2, 10, 1, 20, 100].map do |w|
        h = {} of Crinja::Value => Crinja::Value
        h[Crinja::Value.new("w")] = Crinja::Value.new(w)
        Crinja::Value.new(h)
      end
      vars = {"items" => Crinja::Value.new(arr)}
      result = render_filter("{% for item in items | sort_by(attribute='w') %}{{ item.w }},{% endfor %}", vars)
      result.should eq("1,2,10,20,100,")
    end
  end

  describe "get_taxonomy_url (slug consistency)" do
    it "uses safe_slugify so symbol-only terms don't yield dead // links" do
      vars = {"base_url" => Crinja::Value.new("https://e.com")}
      url = render_filter(%({{ get_taxonomy_url(kind="tags", term="🎉") }}), vars)
      url.should_not contain("tags//")
      url.should contain("/tags/term-")
    end
  end
end
