require "../../spec_helper"

# ext/markd_closing_fence_fix.cr — a closing fence followed by a tab did not
# close the code block, so the rest of the page rendered as code.

describe "Markd closing code fence" do
  it "closes on a fence followed by tabs, like one followed by spaces" do
    ["```\t", "``` \t ", "~~~\t"].each do |closer|
      opener = closer[0].to_s * 3
      html = Markd.to_html("#{opener}\ncode\n#{closer}\n\nafter\n")
      html.should eq("<pre><code>code\n</code></pre>\n<p>after</p>\n")
    end
  end

  it "still treats a fence followed by other text as content" do
    Markd.to_html("```\ncode\n```\tx\n").should eq("<pre><code>code\n```\tx\n</code></pre>\n")
  end

  it "agrees with the rendered page" do
    html, _ = Hwaro::Content::Processors::Markdown.new.render("```\ncode\n```\t\n\n*after*\n", highlight: false)
    html.should contain("<p><em>after</em></p>")
  end
end
