require "../spec_helper"

# Review findings 7, 8, 12, 14.
#
#  7. `strip_control` used `Char#control?`, which is true for the Cf format
#     category as well as Cc — so it deleted ZWNJ/ZWJ/RLM/SHY/BOM and changed
#     the meaning of real words. It was also applied in the MODEL layer, so
#     `tool validate --json` shipped the mangled text to machine consumers.
#  8. `WIDE_RANGES` missed several UAX #11 W blocks, and skin-tone modifiers /
#     ZWJ sequences were over-counted.
# 12. `ContentLister#truncate` capped by codepoints while the table padded by
#     columns.
# 14. A TAB measured 0 where `ljust` charged 1.
describe Hwaro::Utils::TextUtils do
  describe ".strip_control (finding 7)" do
    it "preserves zero-width format characters that carry meaning" do
      # U+200C ZWNJ: `می‌رود` and `میرود` are different words in Persian.
      Hwaro::Utils::TextUtils.strip_control("می\u{200C}رود").should eq("می\u{200C}رود")
      # U+200D ZWJ holds an emoji family together.
      Hwaro::Utils::TextUtils.strip_control("👨\u{200D}👩\u{200D}👧").should eq("👨\u{200D}👩\u{200D}👧")
      # U+200F RLM controls where punctuation lands in a Hebrew line.
      Hwaro::Utils::TextUtils.strip_control("שלום\u{200F}!").should eq("שלום\u{200F}!")
      # U+00AD soft hyphen, U+FEFF BOM, U+200E LRM.
      Hwaro::Utils::TextUtils.strip_control("soft\u{00AD}hyphen").should eq("soft\u{00AD}hyphen")
      Hwaro::Utils::TextUtils.strip_control("a\u{200E}b").should eq("a\u{200E}b")
    end

    it "still strips the escapes that can repaint a terminal" do
      Hwaro::Utils::TextUtils.strip_control("\e[31mred\e[0m").should eq("[31mred[0m")
      Hwaro::Utils::TextUtils.strip_control("bell\ahere").should eq("bellhere")
      Hwaro::Utils::TextUtils.strip_control("cr\rlf").should eq("crlf")
      Hwaro::Utils::TextUtils.strip_control("c1\u{0085}x").should eq("c1x")
    end

    it "strips the Unicode line and paragraph separators" do
      Hwaro::Utils::TextUtils.strip_control("a\u{2028}b").should eq("ab")
      Hwaro::Utils::TextUtils.strip_control("a\u{2029}b").should eq("ab")
    end
  end

  describe ".display_width (finding 8)" do
    it "counts the emoji blocks outside the pictograph range as wide" do
      {"⭐", "✅", "⌚", "⬛", "⭕", "❗", "✨", "☕"}.each do |s|
        Hwaro::Utils::TextUtils.display_width(s).should eq(2)
      end
    end

    it "counts the supplementary emoji blocks as wide" do
      {"🀄", "🈚", "🟠", "🩴", "🃏", "🆎"}.each do |s|
        Hwaro::Utils::TextUtils.display_width(s).should eq(2)
      end
    end

    it "counts Hangul Jamo extended-B as wide" do
      Hwaro::Utils::TextUtils.display_width("\u{D7B0}").should eq(2)
    end

    it "does not over-count skin-tone modifiers" do
      # `👍🏽` is thumbs-up + U+1F3FD and renders in two columns.
      Hwaro::Utils::TextUtils.display_width("👍🏽").should eq(2)
      Hwaro::Utils::TextUtils.display_width("👍").should eq(2)
    end

    it "does not over-count ZWJ sequences" do
      # Three wide emoji + two joiners render as one two-column glyph.
      Hwaro::Utils::TextUtils.display_width("👨\u{200D}👩\u{200D}👧").should eq(2)
      Hwaro::Utils::TextUtils.display_width("👩\u{200D}💻").should eq(2)
    end

    it "gives zero-width format characters no width even though they survive stripping" do
      Hwaro::Utils::TextUtils.display_width("می\u{200C}رود").should eq(5)
      Hwaro::Utils::TextUtils.display_width("a\u{200F}b").should eq(2)
    end

    it "charges a TAB one column, matching ljust (finding 14)" do
      Hwaro::Utils::TextUtils.display_width("\t").should eq(1)
      Hwaro::Utils::TextUtils.display_width("a\tb").should eq("a\tb".size)
    end

    it "measures printable ASCII (and TAB) exactly like String#size" do
      # The invariant that keeps ASCII tables byte-identical. Characters with
      # genuinely no column — NEWLINE, ESC — are excluded by design; no table
      # cell contains them, and `strip_control` removes them first anyway.
      ["a\tb", "plain", "[draft]", "2024-01-15", "content/posts/hello.md"].each do |s|
        Hwaro::Utils::TextUtils.display_width(s).should eq(s.size)
      end
      Hwaro::Utils::TextUtils.display_width("\e[0m").should eq(3)
    end
  end
end

describe Hwaro::Services::ContentLister do
  describe "#truncate (finding 12)" do
    it "caps a CJK title at the column budget, not the codepoint budget" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "a.md"), "+++\ntitle = \"#{"一" * 40}\"\n+++\nb")
        File.write(File.join(content_dir, "b.md"), "+++\ntitle = \"short\"\n+++\nb")

        output = with_captured_log do
          Hwaro::Services::ContentLister.new(content_dir).display(Hwaro::Services::ContentFilter::All)
        end

        # No rendered line may exceed the pre-fix blow-out (30 codepoints of
        # CJK == 60 columns). Every row must also align.
        rows = output.lines.select(&.includes?("[pub]"))
        rows.size.should eq(2)
        starts = rows.map { |line| Hwaro::Utils::TextUtils.display_width(line.rpartition("  ").first) }
        starts.uniq.size.should eq(1)
        starts.first.should be < 60
      end
    end
  end
end
