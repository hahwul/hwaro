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
