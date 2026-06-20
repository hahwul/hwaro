require "../spec_helper"
require "../../src/utils/redirect_html"
require "../../src/utils/text_utils"

describe Hwaro::Utils::RedirectHtml do
  describe ".full_redirect" do
    it "generates a valid HTML redirect page" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("/blog/new-post/")
      result.should contain("<!DOCTYPE html>")
      result.should contain("<meta http-equiv=\"refresh\" content=\"0; url=/blog/new-post/\">")
      result.should contain("<link rel=\"canonical\" href=\"/blog/new-post/\">")
      result.should contain("window.location.href")
    end

    it "includes JavaScript fallback" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("/about/")
      result.should contain("<script>")
      result.should contain("window.location.href")
    end

    it "escapes HTML special characters in URL" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("/search?q=a&b=c")
      result.should contain("&amp;")
    end

    it "escapes JavaScript special characters" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("/path/</script>")
      result.should contain("<\\/script>")
    end

    it "includes redirect message with link" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("/target/")
      result.should contain("Redirecting to")
      result.should contain("<a href=")
    end

    it "refuses a javascript: redirect (no live href, refresh, or navigation)" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("javascript:alert(document.cookie)")
      result.should_not contain("href=\"javascript:")
      result.should_not contain("http-equiv=\"refresh\"")
      result.should_not contain("window.location.href")
      result.should contain("blocked")
    end

    it "refuses a javascript: redirect even with obfuscated whitespace/case" do
      result = Hwaro::Utils::RedirectHtml.full_redirect("JaVaScRiPt:alert(1)")
      result.should_not contain("window.location.href")
      result.should contain("blocked")
    end

    it "still allows ordinary http(s) and relative redirects" do
      Hwaro::Utils::RedirectHtml.full_redirect("https://example.com/").should contain("window.location.href")
      Hwaro::Utils::RedirectHtml.full_redirect("/blog/post/").should contain("window.location.href")
    end

    it "escapes U+2028/U+2029 line terminators in the JS string literal" do
      # A bare U+2028/U+2029 would terminate the JS string on pre-ES2019 engines,
      # breaking the redirect. They must be \u-escaped in the <script> context.
      r1 = Hwaro::Utils::RedirectHtml.full_redirect("/path\u{2028}x")
      r1.should contain("\\u2028")
      r1.should contain("window.location.href") # treated as safe relative URL
      r2 = Hwaro::Utils::RedirectHtml.full_redirect("/path\u{2029}x")
      r2.should contain("\\u2029")
      r2.should contain("window.location.href")
    end

    it "escapes newline and carriage return in the JS string literal" do
      r1 = Hwaro::Utils::RedirectHtml.full_redirect("/a\nb")
      r1.should contain("window.location.href = \"/a\\nb\";") # JS literal escaped, no raw newline
      r2 = Hwaro::Utils::RedirectHtml.full_redirect("/a\rb")
      r2.should contain("\\r")
      r2.should contain("window.location.href")
    end
  end

  describe ".simple_redirect" do
    it "generates a simple HTML redirect page" do
      result = Hwaro::Utils::RedirectHtml.simple_redirect("/blog/new-post/")
      result.should contain("<!DOCTYPE html>")
      result.should contain("meta http-equiv=\"refresh\"")
      result.should contain("/blog/new-post/")
    end

    it "does not include JavaScript" do
      result = Hwaro::Utils::RedirectHtml.simple_redirect("/about/")
      result.should_not contain("<script>")
    end

    it "escapes HTML special characters" do
      result = Hwaro::Utils::RedirectHtml.simple_redirect("/search?q=a&b=c")
      result.should contain("&amp;")
    end

    it "includes a clickable link" do
      result = Hwaro::Utils::RedirectHtml.simple_redirect("/target/")
      result.should contain("<a href=")
      result.should contain("Redirecting to")
    end

    it "includes title with redirect info" do
      result = Hwaro::Utils::RedirectHtml.simple_redirect("/target/")
      result.should contain("<title>")
      result.should contain("Redirecting")
    end
  end
end
