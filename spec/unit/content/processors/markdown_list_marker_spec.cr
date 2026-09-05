require "../../../spec_helper"

# Regression coverage for ext/markd_list_fix.cr — upstream markd converted the
# leading digit run of a line to Int32 before checking whether it could be a
# list marker, so a sentence starting with a number above Int32::MAX
# ("12345678901.50 USD in revenue this year.") raised
# `ArgumentError: Invalid Int32` and aborted the whole build.
private def render(content : String) : String
  html, _ = Hwaro::Content::Processors::Markdown.new.render(content, highlight: false)
  html.strip
end

describe "markdown ordered-list marker scanning" do
  describe "prose starting with a number too large for a marker" do
    it "renders a decimal above Int32::MAX as a paragraph" do
      render("12345678901.50 USD in revenue this year.")
        .should eq("<p>12345678901.50 USD in revenue this year.</p>")
    end

    it "renders a 10-digit number followed by a period as a paragraph" do
      render("3000000000. first record")
        .should eq("<p>3000000000. first record</p>")
    end

    it "renders a number followed by a closing paren as a paragraph" do
      render("2147483648) requests were dropped")
        .should eq("<p>2147483648) requests were dropped</p>")
    end

    it "survives the same number inside a block quote" do
      html = render("> 9999999999. requests per second")
      html.should contain("<blockquote>")
      html.should contain("<p>9999999999. requests per second</p>")
    end
  end

  describe "real ordered lists are unchanged" do
    it "still parses a plain ordered list" do
      html = render("1. one\n2. two")
      html.should contain("<ol>")
      html.should contain("<li>one</li>")
      html.should contain("<li>two</li>")
    end

    it "still honours a start value at the 9-digit CommonMark limit" do
      # 999999999 is the largest marker CommonMark allows, and it fits in
      # Int32 — the fix must not turn it into a paragraph.
      html = render("999999999. last one")
      html.should contain(%(<ol start="999999999">))
      html.should contain("<li>last one</li>")
    end

    it "still parses paren-delimited markers" do
      html = render("1) one\n2) two")
      html.should contain("<ol>")
      html.should contain("<li>one</li>")
    end
  end
end
