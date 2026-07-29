require "../spec_helper"

# Regression coverage for ext/markd_entity_fix.cr — a bare `&` used to be
# treated as the opening of a named entity, and the scanner then ran forward
# without a bound to the next `;`, swallowing every inline construct in
# between (hwaro#717). Both characters are ordinary English punctuation, so
# this silently broke prose on successful builds.
private def render(content : String) : String
  html, _ = Hwaro::Content::Processors::Markdown.new.render(content, highlight: false)
  html.strip
end

describe "markdown entity scanning" do
  describe "a bare ampersand is literal text" do
    it "keeps parsing emphasis before a later semicolon" do
      render("R & D **bold** here; done.")
        .should eq("<p>R &amp; D <strong>bold</strong> here; done.</p>")
    end

    it "keeps parsing code spans before a later semicolon" do
      render("R & D `code` here; done.")
        .should eq("<p>R &amp; D <code>code</code> here; done.</p>")
    end

    it "keeps parsing links before a later semicolon" do
      render("R & D [link](/) here; done.")
        .should eq(%(<p>R &amp; D <a href="/">link</a> here; done.</p>))
    end

    it "handles the ampersand-then-semicolon run spanning many words" do
      render("Preferences → **Network & Tabs** → **Network**. It is not a per-project lock; done.")
        .should eq("<p>Preferences → <strong>Network &amp; Tabs</strong> → " \
                   "<strong>Network</strong>. It is not a per-project lock; done.</p>")
    end

    it "keeps parsing when the ampersand and semicolon are on different lines" do
      # How the bug actually showed up in the wild: a soft line break sits
      # between the two characters, so the run crosses lines inside one block.
      render("**Cards & containers:** a soft-wrapped sentence\nwith an inset highlight; done.")
        .should eq("<p><strong>Cards &amp; containers:</strong> a soft-wrapped sentence\n" \
                   "with an inset highlight; done.</p>")
    end

    it "is unaffected by a semicolon that precedes the ampersand" do
      render("a; b & c **bold**.")
        .should eq("<p>a; b &amp; c <strong>bold</strong>.</p>")
    end

    it "handles an ampersand with no semicolon at all" do
      render("R & D **bold** here. done.")
        .should eq("<p>R &amp; D <strong>bold</strong> here. done.</p>")
    end
  end

  describe "well-formed references still decode" do
    it "decodes named references" do
      render("&amp; &copy; &nbsp; &frac34; &AMP;")
        .should eq("<p>&amp; © \u{00A0} ¾ &amp;</p>")
    end

    it "decodes the longest name in the HTML5 list" do
      render("&CounterClockwiseContourIntegral;").should eq("<p>∳</p>")
    end

    it "decodes decimal and hexadecimal references" do
      render("&#38; &#x26; &#8212;").should eq("<p>&amp; &amp; —</p>")
    end

    it "maps out-of-range codepoints to the replacement character" do
      render("&#0; &#xD800;").should eq("<p>\u{FFFD} \u{FFFD}</p>")
    end
  end

  describe "malformed references stay literal" do
    it "leaves an unknown name alone and keeps parsing after it" do
      render("&notanentity; **bold**")
        .should eq("<p>&amp;notanentity; <strong>bold</strong></p>")
    end

    it "leaves an over-long name alone" do
      render("&ThisNameIsWayTooLongToEverBeAnEntityName; **bold**")
        .should eq("<p>&amp;ThisNameIsWayTooLongToEverBeAnEntityName; <strong>bold</strong></p>")
    end

    it "leaves malformed numeric references alone" do
      render("&#xZZ; &#99999999; &#; **bold**")
        .should eq("<p>&amp;#xZZ; &amp;#99999999; &amp;#; <strong>bold</strong></p>")
    end

    it "does not crash on an empty entity name" do
      # Upstream indexed byte 0 of the empty name and raised IndexError,
      # aborting the whole build.
      render("&; **bold**").should eq("<p>&amp;; <strong>bold</strong></p>")
    end
  end

  describe "surrounding constructs are untouched" do
    it "leaves ampersands inside code spans and links escaped" do
      render("`a & b;` and [a & b](/x?y=1&z=2)")
        .should eq(%(<p><code>a &amp; b;</code> and <a href="/x?y=1&amp;z=2">a &amp; b</a></p>))
    end
  end
end
