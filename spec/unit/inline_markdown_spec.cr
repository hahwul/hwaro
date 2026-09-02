require "../spec_helper"

# `safe_url?` percent-decodes before scheme matching, so any `%XX` in a link,
# image, or `redirect_to` value can hand PCRE2 an invalid-UTF-8 subject. These
# examples pin the scrub guard that keeps such a URL from aborting the build.
describe Hwaro::Content::Processors::InlineMarkdown do
  describe ".safe_url?" do
    it "accepts a legacy latin-1 percent escape without raising" do
      # `%E9` is `é` in latin-1 — what an old CMS or an importer emits. Decoding
      # it yields a lone 0xE9 byte, which is not valid UTF-8.
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("/caf%E9.html").should be_true
    end

    it "accepts a bare invalid percent escape without raising" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("%FF").should be_true
    end

    it "accepts a percent-encoded overlong sequence without raising" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("/a/%C0%AE%C0%AE/b").should be_true
    end

    it "keeps blocking unsafe schemes that also carry invalid escapes" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("javascript:alert(1)%FF").should be_false
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("java%09script:alert(1)%E9").should be_false
    end

    it "leaves ordinary URLs unchanged" do
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("https://example.com/a%20b").should be_true
      Hwaro::Content::Processors::InlineMarkdown.safe_url?("/relative/path").should be_true
    end
  end

  describe ".render" do
    it "renders a link whose URL carries an invalid percent escape" do
      # This is the table-cell / footnote-body / definition-list path: the same
      # link in an ordinary paragraph never reaches `safe_url?`.
      out = Hwaro::Content::Processors::InlineMarkdown.render("see [x](/caf%E9.html) here")
      out.should contain(%(<a href="/caf%E9.html">x</a>))
    end

    it "renders an image whose URL carries an invalid percent escape" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("![a](/caf%E9.png)")
      out.should contain(%(<img src="/caf%E9.png" alt="a">))
    end
  end

  # Code spans in this renderer used to be single-backtick-only, so a
  # multi-backtick span (the CommonMark way to show a literal backtick) had
  # its INNER backticks matched instead — shredding the span into stray
  # <code> tags and leaving the real delimiters as visible text.
  describe ".render code spans" do
    it "renders a double-backtick span containing single backticks" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("x `` `tick` `` y")
      out.should eq("x <code>`tick`</code> y")
    end

    it "renders a double-backtick span with an interior backtick" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("``a`b``")
      out.should eq("<code>a`b</code>")
    end

    it "renders a triple-backtick span" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("```x``y```")
      out.should eq("<code>x``y</code>")
    end

    it "still renders plain single-backtick spans unchanged" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("a `b` c `d` e")
      out.should eq("a <code>b</code> c <code>d</code> e")
    end

    it "keeps an all-space code span padded" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("`` ``")
      out.should eq("<code> </code>")
    end

    it "leaves an unpaired backtick run alone" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("x `` y")
      out.should eq("x `` y")
    end

    # The opener must be a WHOLE backtick run. Without the opener lookbehind
    # the scan restarted on the second backtick of the unmatched `` and paired
    # it with the later single backtick: `` `<code> </code>a` ``.
    it "keeps an unmatched longer run literal and pairs the later whole runs" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("`` `a`")
      out.should eq("`` <code>a</code>")
    end

    it "does not start a span in the middle of a run" do
      out = Hwaro::Content::Processors::InlineMarkdown.render("``` `` x ``")
      out.should eq("``` <code>x</code>")
    end

    # Every backtick of an unclosed run used to be a fresh start position that
    # possessively re-consumed the rest of the run — O(N²); a 200 KB run did
    # not finish. The bound is generous on purpose: the quadratic form takes
    # minutes here, the linear form about a millisecond.
    it "renders a long unclosed backtick run in linear time" do
      input = "`" * 100_000
      started = Time.monotonic
      out = Hwaro::Content::Processors::InlineMarkdown.render(input)
      (Time.monotonic - started).should be < 5.seconds
      out.should eq(input)
    end

    # The placeholder restore ran one whole-string `gsub` per code span, so a
    # cell with N spans was O(N²) even after the scan itself became linear:
    # 20k spans took ~10 s. One pass per token kind now.
    it "restores many code spans in linear time" do
      input = Array.new(20_000) { |i| "`c#{i}`" }.join(" ")
      started = Time.monotonic
      out = Hwaro::Content::Processors::InlineMarkdown.render(input)
      (Time.monotonic - started).should be < 3.seconds
      out.should start_with("<code>c0</code> <code>c1</code>")
      out.should end_with("<code>c19999</code>")
      out.should_not contain("\x00")
    end
  end
end

# `redirect_to` front matter reaches `safe_url?` verbatim, with no markdown
# link involved — an independent entry point for the same crash. (The main
# RedirectHtml suite lives in redirect_html_spec.cr.)
describe "RedirectHtml via InlineMarkdown.safe_url?" do
  it "emits a redirect page for a URL with an invalid percent escape" do
    html = Hwaro::Utils::RedirectHtml.full_redirect("/caf%E9.html")
    html.should contain(%(content="0; url=/caf%E9.html"))
  end
end
