require "../../../spec_helper"

# Regression coverage for ext/markd_thematic_break_fix.cr — upstream markd
# matched thematic breaks with nested quantifiers
# (`(?:\*[ \t]*){3,}|...`), so PCRE2 recursed once per marker character and
# blew its JIT stack past roughly 44_000 of them on one line:
# `Regex::Error: Regex match error: JIT stack limit reached`, raised out of
# `String#match` where nothing expects it, aborting the whole build. The block
# parser offers every line to this rule, so a long run of `-`, `*` or `_`
# anywhere in a document was enough — a machine-generated separator or a
# pasted log divider does it.
private def render(content : String) : String
  html, _ = Hwaro::Content::Processors::Markdown.new.render(content, highlight: false)
  html.strip
end

describe "markdown thematic breaks" do
  describe "very long marker runs" do
    it "renders a 200k-character rule instead of raising Regex::Error" do
      %w[- * _].each do |marker|
        render(marker * 200_000).should eq("<hr />")
      end
    end
  end

  describe "CommonMark semantics are unchanged" do
    it "accepts the three markers and interior spacing" do
      render("---").should eq("<hr />")
      render("***").should eq("<hr />")
      render("___").should eq("<hr />")
      render("- - -").should eq("<hr />")
      render("  ***  ").should eq("<hr />")
    end

    it "rejects fewer than three markers" do
      render("**").should eq("<p>**</p>")
    end

    it "rejects mixed markers" do
      render("-*-").should eq("<p>-*-</p>")
    end

    it "rejects a line with any other character" do
      render("---a").should eq("<p>---a</p>")
    end

    it "leaves an indented rule as a code block" do
      render("\t---").should contain("<code>")
    end
  end
end
