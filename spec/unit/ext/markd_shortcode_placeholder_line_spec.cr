require "../../spec_helper"

# ext/markd_shortcode_placeholder_line.cr — a shortcode placeholder opening a
# line that goes on with text is inline HTML, not an HTML block.

private PH = "<!--HWARO-SHORTCODE-PLACEHOLDER-0-->"

describe "Markd shortcode placeholder lines" do
  it "reads a placeholder followed by text as paragraph text" do
    Markd.to_html("Intro\n#{PH} more *x*\n").should eq("<p>Intro\n#{PH} more <em>x</em></p>\n")
    Markd.to_html("#{PH} more *x*\n").should eq("<p>#{PH} more <em>x</em></p>\n")
    # Inline HTML after the placeholder is inline, as with the call mid-line.
    Markd.to_html("#{PH} <b>raw</b> *x*\n").should eq("<p>#{PH} <b>raw</b> <em>x</em></p>\n")
  end

  it "keeps placeholders alone on their line as an HTML block" do
    Markd.to_html("#{PH}\n").should eq("#{PH}\n")
    Markd.to_html("#{PH} #{PH}\n").should eq("#{PH} #{PH}\n")
    Markd.to_html("<!-- note --> text\n").should eq("<!-- note --> text\n")
  end
end
