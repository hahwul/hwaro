require "../../../spec_helper"

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

  # Link destinations, link titles and fence info strings bypass the inline
  # scanner and are decoded wholesale by Markd::HTMLEntities::Decoder, which
  # had three defects of its own. See ext/markd_entity_fix.cr.
  describe "astral-plane numeric references" do
    it "decodes emoji rather than the replacement character" do
      # decode_codepoint range-checked against 0x10FFF instead of 0x10FFFF,
      # so every codepoint above U+10FFF came back as U+FFFD.
      render("&#x1F600; &#128512;").should eq("<p>😀 😀</p>")
    end

    it "decodes other planes above U+10FFF" do
      render("&#x1D54F; &#x20000; &#x10FFFF;").should eq("<p>𝕏 𠀀 \u{10FFFF}</p>")
    end

    it "still rejects genuinely out-of-range codepoints and surrogates" do
      render("&#x110000; &#xD800;").should eq("<p>\u{FFFD} \u{FFFD}</p>")
    end

    it "decodes astral references in link destinations, titles and fence info" do
      render("[t](/a?e=&#x1F600;)").should eq(%(<p><a href="/a?e=%F0%9F%98%80">t</a></p>))
      render(%([t](/a "smile &#x1F600;"))).should eq(%(<p><a href="/a" title="smile 😀">t</a></p>))
      render("```&#x1F600;\ncode\n```")
        .should eq(%(<pre><code class="language-😀">code\n</code></pre>))
    end
  end

  describe "oversized numeric references outside body text" do
    # The decoder's pattern put no bound on the digit run and then called
    # .to_i on it, so these raised ArgumentError and aborted the build.
    it "does not crash in a link destination" do
      render("[t](/a?x=&#99999999999999999999;)")
        .should eq(%(<p><a href="/a?x=&amp;#99999999999999999999;">t</a></p>))
    end

    it "does not crash in a link title" do
      render(%([t](/a "&#99999999999999999999;")))
        .should eq(%(<p><a href="/a" title="&amp;#99999999999999999999;">t</a></p>))
    end

    it "does not crash in a fence info string" do
      render("```&#99999999999999999999;\ncode\n```")
        .should eq(%(<pre><code class="language-&amp;#99999999999999999999;">code\n</code></pre>))
    end
  end

  describe "semicolon-less numeric references outside body text" do
    # The decoder stripped the first AND last character unconditionally, so a
    # reference with no `;` lost its final digit and decoded the wrong
    # codepoint — `&#38` became U+0003, `&#100` became a newline.
    it "leaves them literal in a link destination" do
      render("[t](/a?x=1&#38y=2)").should eq(%(<p><a href="/a?x=1&amp;#38y=2">t</a></p>))
      render("[t](/a?x=1&#100y=2)").should eq(%(<p><a href="/a?x=1&amp;#100y=2">t</a></p>))
    end

    it "leaves them literal in a link title" do
      render(%([t](/a "q &#38 r"))).should eq(%(<p><a href="/a" title="q &amp;#38 r">t</a></p>))
    end

    it "leaves them literal in a fence info string" do
      render("```rb&#38\ncode\n```")
        .should eq(%(<pre><code class="language-rb&amp;#38">code\n</code></pre>))
    end
  end

  describe "well-formed references outside body text still decode" do
    it "decodes named and numeric references in destinations and titles" do
      render("[t](/a?x=&#38;y=2)").should eq(%(<p><a href="/a?x=&amp;y=2">t</a></p>))
      render("[t](/a?x=&amp;y=2)").should eq(%(<p><a href="/a?x=&amp;y=2">t</a></p>))
      render(%([t](/a "q &amp; r"))).should eq(%(<p><a href="/a" title="q &amp; r">t</a></p>))
    end

    it "decodes references in a fence info string" do
      render("```C&#43;&#43;\ncode\n```")
        .should eq(%(<pre><code class="language-C++">code\n</code></pre>))
    end
  end
end
