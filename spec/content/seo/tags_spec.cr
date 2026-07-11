require "../../spec_helper"
require "../../../src/content/seo/tags"
require "../../../src/models/config"
require "../../../src/models/page"

describe Hwaro::Content::Seo::Tags do
  describe ".canonical_tag" do
    it "generates canonical tag from base_url and page url" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"

      tag = Hwaro::Content::Seo::Tags.canonical_tag(page, config)
      tag.should eq %(<link rel="canonical" href="https://example.com/test/">)
    end

    it "uses permalink if available" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      page.permalink = "https://custom.com/foo/"

      tag = Hwaro::Content::Seo::Tags.canonical_tag(page, config)
      tag.should eq %(<link rel="canonical" href="https://custom.com/foo/">)
    end

    it "handles base_url with trailing slash correctly" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/"

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"

      tag = Hwaro::Content::Seo::Tags.canonical_tag(page, config)
      tag.should eq %(<link rel="canonical" href="https://example.com/test/">)
    end

    it "handles page url without leading slash correctly" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("test.md")
      page.url = "test/"

      tag = Hwaro::Content::Seo::Tags.canonical_tag(page, config)
      tag.should eq %(<link rel="canonical" href="https://example.com/test/">)
    end

    it "percent-encodes non-ASCII paths like feeds/sitemap do" do
      # A Unicode taxonomy term (`/tags/日本語タグ/`) must canonicalize to the
      # exact same RFC 3986 URL its RSS/sitemap entries advertise — raw UTF-8
      # here and percent-encoded there is two different URLs to a crawler.
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("tags/_index.md")
      page.url = "/tags/日本語タグ/"

      tag = Hwaro::Content::Seo::Tags.canonical_tag(page, config)
      tag.should contain("https://example.com/tags/%E6%97%A5%E6%9C%AC%E8%AA%9E%E3%82%BF%E3%82%B0/")
      tag.should_not contain("日本語タグ")
    end

    it "does not double-encode an already percent-encoded URL" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("test.md")
      page.url = "/tags/%E6%97%A5%E6%9C%AC/"

      tag = Hwaro::Content::Seo::Tags.canonical_tag(page, config)
      tag.should contain("/tags/%E6%97%A5%E6%9C%AC/")
      tag.should_not contain("%25")
    end
  end

  describe ".hreflang_tags" do
    it "returns empty string if not multilingual" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      page = Hwaro::Models::Page.new("test.md")

      tags = Hwaro::Content::Seo::Tags.hreflang_tags(page, config)
      tags.should be_empty
    end

    it "returns empty string if no translations" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      page = Hwaro::Models::Page.new("test.md")

      tags = Hwaro::Content::Seo::Tags.hreflang_tags(page, config)
      tags.should be_empty
    end

    it "generates hreflang tags for translations" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      page = Hwaro::Models::Page.new("test.md")
      page.language = "en"
      page.url = "/test/"

      # Add translation link
      translation = Hwaro::Models::TranslationLink.new(
        code: "ko",
        url: "/ko/test/",
        title: "Test (KO)",
        is_current: false
      )
      page.translations << translation

      tags = Hwaro::Content::Seo::Tags.hreflang_tags(page, config)

      expected_tags = [
        %(<link rel="alternate" hreflang="en" href="https://example.com/test/">),
        %(<link rel="alternate" hreflang="ko" href="https://example.com/ko/test/">),
      ]

      tags.should eq expected_tags.sort.join("\n")
    end

    it "handles absolute translation URLs" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      page = Hwaro::Models::Page.new("test.md")
      page.language = "en"
      page.url = "/test/"

      # Add translation link with absolute URL
      translation = Hwaro::Models::TranslationLink.new(
        code: "ko",
        url: "https://example.com/ko/test/",
        title: "Test (KO)",
        is_current: false
      )
      page.translations << translation

      tags = Hwaro::Content::Seo::Tags.hreflang_tags(page, config)

      expected_tags = [
        %(<link rel="alternate" hreflang="en" href="https://example.com/test/">),
        %(<link rel="alternate" hreflang="ko" href="https://example.com/ko/test/">),
      ]

      tags.should eq expected_tags.sort.join("\n")
    end
  end
end
