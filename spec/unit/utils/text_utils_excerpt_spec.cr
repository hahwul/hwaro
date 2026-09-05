require "../../spec_helper"

# =============================================================================
# Automatic-summary text helpers (Utils::TextUtils.excerpt_text /
# truncate_excerpt). The page-level precedence and the build-level wiring
# are covered by spec/unit/auto_summary_spec.cr and
# spec/functional/auto_summary_spec.cr; this file pins the text rules.
# =============================================================================

private ELLIPSIS = "…"

describe Hwaro::Utils::TextUtils do
  describe ".excerpt_text" do
    it "strips tags, decodes entities and collapses whitespace" do
      html = "<p>Hello &amp; <em>world</em>,\n\n  it&#39;s   <strong>fine</strong>.</p>"
      Hwaro::Utils::TextUtils.excerpt_text(html).should eq("Hello & world, it's fine.")
    end

    it "drops code, pre, script, style, figure, img and heading content" do
      html = <<-HTML
        <h1 id="t">Title Heading</h1>
        <p>Lead paragraph.</p>
        <pre><code class="language-crystal">puts "CODE BLOCK"</code></pre>
        <p>Inline <code>INLINE_CODE</code> here.</p>
        <figure><img src="/a.png" alt="ALT TEXT"><figcaption>CAPTION</figcaption></figure>
        <img src="/b.png" alt="LONE ALT">
        <script>var SCRIPT = 1;</script>
        <style>.STYLE {}</style>
        <h2>Second Heading</h2>
        <p>Tail paragraph.</p>
        HTML
      text = Hwaro::Utils::TextUtils.excerpt_text(html)
      text.should eq("Lead paragraph. Inline here. Tail paragraph.")
      %w[Title Heading CODE INLINE_CODE ALT CAPTION LONE SCRIPT STYLE Second].each do |leak|
        text.should_not contain(leak)
      end
    end

    it "drops math source, footnote markers and the footnotes section" do
      html = <<-HTML
        <p>Euler<sup class="footnote-ref"><a href="#fn-1" id="fnref-1">[1]</a></sup> wrote <span class="math math-inline">(e^{ipi})</span> first.</p>
        <div class="math math-display">[x^2]</div>
        <section class="footnotes">
        <hr>
        <ol><li id="fn-1">FOOTNOTE BODY</li></ol>
        </section>
        HTML
      Hwaro::Utils::TextUtils.excerpt_text(html).should eq("Euler wrote first.")
    end

    it "never reads a decoded entity as markup" do
      # `&lt;script&gt;` is literal text in the rendered HTML; decoding
      # happens after stripping so it survives as characters.
      Hwaro::Utils::TextUtils.excerpt_text("<p>use &lt;b&gt; sparingly</p>").should eq("use <b> sparingly")
    end
  end

  describe ".cjk_dominant?" do
    it "is true for Korean, Japanese and Chinese prose" do
      Hwaro::Utils::TextUtils.cjk_dominant?("정적 사이트 생성기 hwaro").should be_true
      Hwaro::Utils::TextUtils.cjk_dominant?("静的サイトジェネレーター").should be_true
      Hwaro::Utils::TextUtils.cjk_dominant?("静态网站生成器").should be_true
    end

    it "is false for Latin prose with a few CJK characters" do
      Hwaro::Utils::TextUtils.cjk_dominant?("The word 火 means fire in Chinese.").should be_false
      Hwaro::Utils::TextUtils.cjk_dominant?("").should be_false
    end
  end

  describe ".truncate_excerpt" do
    it "returns the text untouched when it fits" do
      text, cut = Hwaro::Utils::TextUtils.truncate_excerpt("one two three", 3, ELLIPSIS)
      text.should eq("one two three")
      cut.should be_false
    end

    it "cuts space-delimited text at a word boundary and appends the ellipsis" do
      text, cut = Hwaro::Utils::TextUtils.truncate_excerpt("one two three four five", 3, ELLIPSIS)
      text.should eq("one two three…")
      cut.should be_true
    end

    it "uses the configured ellipsis verbatim" do
      text, _ = Hwaro::Utils::TextUtils.truncate_excerpt("a b c d", 2, " [more]")
      text.should eq("a b [more]")
    end

    it "trims trailing punctuation before the ellipsis" do
      text, _ = Hwaro::Utils::TextUtils.truncate_excerpt("First clause, second clause; third.", 2, ELLIPSIS)
      text.should eq("First clause…")
      text, _ = Hwaro::Utils::TextUtils.truncate_excerpt("Alpha beta - gamma", 3, ELLIPSIS)
      text.should eq("Alpha beta…")
    end

    it "keeps sentence-ending punctuation" do
      text, _ = Hwaro::Utils::TextUtils.truncate_excerpt("Done. Next words here", 1, ELLIPSIS)
      text.should eq("Done.…")
    end

    it "counts CJK-dominant text in characters at twice the word setting" do
      korean = "하나둘셋넷다섯여섯일곱여덟아홉열" # 16 chars, no spaces
      text, cut = Hwaro::Utils::TextUtils.truncate_excerpt(korean, 5, ELLIPSIS)
      text.should eq("하나둘셋넷다섯여섯일#{ELLIPSIS}")
      text.chars.size.should eq(11)
      cut.should be_true

      fits, cut2 = Hwaro::Utils::TextUtils.truncate_excerpt(korean, 8, ELLIPSIS)
      fits.should eq(korean)
      cut2.should be_false
    end

    it "does not split a Latin word embedded in CJK text" do
      # 10 CJK chars, then "hwaro" starting at index 10; limit 6 words → 12 chars
      text, _ = Hwaro::Utils::TextUtils.truncate_excerpt("정적사이트생성기입니다hwaro입니다", 6, ELLIPSIS)
      text.should eq("정적사이트생성기입니다…")
    end

    it "never splits a multibyte sequence or a decoded entity" do
      emoji = "😀 " * 5 + "tail"
      text, _ = Hwaro::Utils::TextUtils.truncate_excerpt(emoji, 3, ELLIPSIS)
      text.should eq("😀 😀 😀…")
      text.valid_encoding?.should be_true

      amp, _ = Hwaro::Utils::TextUtils.truncate_excerpt("fish & chips & peas & beans", 4, ELLIPSIS)
      amp.should eq("fish & chips…")
    end

    it "treats a non-positive length as no limit" do
      text, cut = Hwaro::Utils::TextUtils.truncate_excerpt("a b c", 0, ELLIPSIS)
      text.should eq("a b c")
      cut.should be_false
    end
  end
end
