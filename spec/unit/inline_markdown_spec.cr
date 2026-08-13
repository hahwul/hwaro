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
