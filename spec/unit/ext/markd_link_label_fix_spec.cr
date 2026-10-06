require "../../spec_helper"

# ext/markd_link_label_fix.cr — a full reference link whose label is one
# character (`[text][1]`) fell through to a shortcut link on `[1]`.

describe "Markd full reference link labels" do
  it "resolves one-character labels for links and images" do
    html = Markd.to_html("See [Crystal][1] and ![Logo][1].\n\n[1]: https://crystal-lang.org\n")
    html.should eq(%(<p>See <a href="https://crystal-lang.org">Crystal</a> and <img src="https://crystal-lang.org" alt="Logo" />.</p>\n))
  end

  it "still resolves collapsed and multi-character labels" do
    html = Markd.to_html("[x][] and [ab][cd].\n\n[x]: /x\n[cd]: /cd\n")
    html.should eq(%(<p><a href="/x">x</a> and <a href="/cd">ab</a>.</p>\n))
  end
end
