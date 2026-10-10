require "../../spec_helper"

# ext/markd_unsafe_image_fix.cr — under safe mode an image with an unsafe
# destination closed its alt attribute early, so the alt text became
# attributes (`![x onerror=alert(1)//](javascript:x)` => a live onerror).

describe "Markd safe-mode image with an unsafe destination" do
  it "keeps the alt text inside the alt attribute" do
    html = Markd.to_html("![x onerror=alert(1)//](javascript:x)", Markd::Options.new(safe: true))
    html.should eq(%(<p><img src="" alt="x onerror=alert(1)//" /></p>\n))
  end

  it "leaves safe destinations unchanged" do
    html = Markd.to_html(%(![a](/a.png "t")), Markd::Options.new(safe: true))
    html.should eq(%(<p><img src="/a.png" alt="a" title="t" /></p>\n))
  end
end
