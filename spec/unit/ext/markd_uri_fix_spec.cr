require "../../spec_helper"

# ext/markd_uri_fix.cr — Markd decoded every %XX in a link destination before
# re-encoding, turning %23 %3F %2F %26 %3D back into raw reserved characters
# and changing what the URL means.

describe "Markd link destination escapes" do
  it "keeps percent-escaped reserved characters in link, image, autolink and reference destinations" do
    md = <<-MD
      [e](https://e.com/s?q=a%26b%3Dc&next=https%3A%2F%2Fx.org%2F%3Fa%3D1) ![y](/a%231.png) [l](/b%3F.html) ![s](/s%2Fx.png) <https://e.com/a%23b> [r]

      [r]: /r%23x%3Fy
      MD
    html = Markd.to_html(md)
    html.should contain(%(href="https://e.com/s?q=a%26b%3Dc&amp;next=https%3A%2F%2Fx.org%2F%3Fa%3D1"))
    html.should contain(%(src="/a%231.png"))
    html.should contain(%(href="/b%3F.html"))
    html.should contain(%(src="/s%2Fx.png"))
    html.should contain(%(href="https://e.com/a%23b"))
    html.should contain(%(href="/r%23x%3Fy"))
  end

  it "uppercases the hex of preserved escapes" do
    Markd.to_html("[a](/a%2fb%3a)").should contain(%(href="/a%2Fb%3A"))
  end

  it "keeps the behavior that predates the fix for everything else" do
    Markd.to_html("[a](/a%20b)").should contain(%(href="/a%20b"))
    Markd.to_html("[a](/a%25b)").should contain(%(href="/a%25b"))
    Markd.to_html("[a](/100%)").should contain(%(href="/100%25"))
    Markd.to_html("[a](/%7Ea%41)").should contain(%(href="/~aA"))
    Markd.to_html("[a](/caf%c3%a9)").should contain(%(href="/caf%C3%A9"))
    Markd.to_html("[a](</한글>)").should contain(%(href="/%ED%95%9C%EA%B8%80"))
    Markd.to_html("[a](/a[b]?c=d#e)").should contain(%(href="/a%5Bb%5D?c=d#e"))
  end
end
