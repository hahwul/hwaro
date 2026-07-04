require "../spec_helper"

describe Hwaro::Content::Processors::MarkdownAttributes do
  describe ".parse" do
    it "parses a full valid block (#id .a .b k=v k2=\"v 2\")" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse(%(#id .a .b k=v k2="v 2")).not_nil!
      parsed.id.should eq("id")
      parsed.classes.should eq(["a", "b"])
      parsed.attrs.should eq([{"k", "v"}, {"k2", "v 2"}])
    end

    it "returns nil for an invalid id token (#1x)" do
      Hwaro::Content::Processors::MarkdownAttributes.parse("#1x").should be_nil
    end

    it "returns nil for an invalid class token (.9)" do
      Hwaro::Content::Processors::MarkdownAttributes.parse(".9").should be_nil
    end

    it "returns nil for an invalid kv value (k=<)" do
      Hwaro::Content::Processors::MarkdownAttributes.parse("k=<").should be_nil
    end

    it "returns nil for an empty block" do
      Hwaro::Content::Processors::MarkdownAttributes.parse("").should be_nil
    end

    it "returns nil for a block that is only whitespace" do
      Hwaro::Content::Processors::MarkdownAttributes.parse("   ").should be_nil
    end

    it "last id wins when multiple #id tokens are given" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("#a #b").not_nil!
      parsed.id.should eq("b")
    end

    it "dedupes classes, keeping the first occurrence's position" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse(".a .b .a").not_nil!
      parsed.classes.should eq(["a", "b"])
    end

    it "aliases id=value to the same field as #id" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("id=x").not_nil!
      parsed.id.should eq("x")
    end

    it "aliases class=value to the same field as .class" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("class=x").not_nil!
      parsed.classes.should eq(["x"])
    end

    it "last value wins for a duplicated key=value pair" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("k=1 k=2").not_nil!
      parsed.attrs.should eq([{"k", "2"}])
    end

    it "accepts a bare (unquoted) value" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("width=300").not_nil!
      parsed.attrs.should eq([{"width", "300"}])
    end

    it "accepts a quoted value containing spaces" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse(%(title="hello world")).not_nil!
      parsed.attrs.should eq([{"title", "hello world"}])
    end

    it "rejects a token with a malformed key=value (no closing quote)" do
      Hwaro::Content::Processors::MarkdownAttributes.parse(%(k="unterminated)).should be_nil
    end

    it "rejects unrelated garbage mixed with otherwise-valid tokens" do
      Hwaro::Content::Processors::MarkdownAttributes.parse("#id ,,, .c").should be_nil
    end
  end

  describe ".encode / .decode" do
    it "round-trips arbitrary text through hex" do
      original = %(#id .a k="v 2")
      encoded = Hwaro::Content::Processors::MarkdownAttributes.encode(original)
      encoded.should match(/\A[0-9a-f]*\z/)
      Hwaro::Content::Processors::MarkdownAttributes.decode(encoded).should eq(original)
    end

    it "round-trips text containing HTML-comment-hostile bytes (-->)" do
      original = %(title="a-->b")
      encoded = Hwaro::Content::Processors::MarkdownAttributes.encode(original)
      Hwaro::Content::Processors::MarkdownAttributes.decode(encoded).should eq(original)
    end

    it "returns nil for a payload with odd length" do
      Hwaro::Content::Processors::MarkdownAttributes.decode("abc").should be_nil
    end

    it "returns nil for a payload with non-hex characters" do
      Hwaro::Content::Processors::MarkdownAttributes.decode("zz").should be_nil
    end
  end

  describe ".apply_to_tag_attrs" do
    it "appends id/class/other attrs when the tag has none" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("#i .c k=v").not_nil!
      result = Hwaro::Content::Processors::MarkdownAttributes.apply_to_tag_attrs("", parsed)
      result.should eq(%( id="i" class="c" k="v"))
    end

    it "replaces an existing id attribute in place" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse("#new").not_nil!
      result = Hwaro::Content::Processors::MarkdownAttributes.apply_to_tag_attrs(%( id="old"), parsed)
      result.should eq(%( id="new"))
    end

    it "merges classes into an existing class attribute" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse(".b").not_nil!
      result = Hwaro::Content::Processors::MarkdownAttributes.apply_to_tag_attrs(%( class="a"), parsed)
      result.should eq(%( class="a b"))
    end

    it "HTML-escapes attribute values" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse(%(k="<script>")).not_nil!
      result = Hwaro::Content::Processors::MarkdownAttributes.apply_to_tag_attrs("", parsed)
      result.should contain("&lt;script&gt;")
      result.should_not contain("<script>")
    end
  end

  describe ".apply_to_img" do
    it "appends attrs onto an <img> opening tag" do
      parsed = Hwaro::Content::Processors::MarkdownAttributes.parse(".r width=300").not_nil!
      result = Hwaro::Content::Processors::MarkdownAttributes.apply_to_img(%(<img src="p.png" alt="a"), parsed)
      result.should eq(%(<img src="p.png" alt="a" class="r" width="300"))
    end
  end
end
