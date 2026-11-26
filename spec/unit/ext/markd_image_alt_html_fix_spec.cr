require "../../spec_helper"

# ext/markd_image_alt_html_fix.cr — raw inline HTML inside an image
# description was written into the alt attribute verbatim, so its quotes
# ended the attribute early.

describe "Markd inline HTML inside an image description" do
  it "keeps the alt attribute well-formed" do
    html = Markd.to_html(%(![a <span class="x">b</span> & c](/i.png)))
    html.should eq(%(<p><img src="/i.png" alt="a &lt;span class=&quot;x&quot;&gt;b&lt;/span&gt; &amp; c" /></p>\n))
  end

  it "leaves inline HTML outside images raw" do
    Markd.to_html(%(a <span class="x">b</span>)).should eq(%(<p>a <span class="x">b</span></p>\n))
  end

  it "escapes a shortcode placeholder in an alt attribute, in safe mode too" do
    # The placeholder later becomes the shortcode's HTML: raw in the alt,
    # its `class="…"` quotes broke the <img>.
    placeholder = "<!--HWARO-SHORTCODE-PLACEHOLDER-0-->"
    [false, true].each do |safe|
      html, _ = Hwaro::Processor::Markdown.render("![alt #{placeholder}](/i.png)", safe: safe)
      html.should eq(%(<p><img src="/i.png" alt="alt &lt;!--HWARO-SHORTCODE-PLACEHOLDER-0--&gt;" /></p>\n))
    end
  end
end
