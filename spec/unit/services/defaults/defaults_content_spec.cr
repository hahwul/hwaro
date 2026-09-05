require "../../../spec_helper"
require "../../../../src/services/defaults/content"

describe Hwaro::Services::Defaults::ContentSamples do
  describe ".index_content" do
    it "returns non-empty content" do
      Hwaro::Services::Defaults::ContentSamples.index_content.should_not be_empty
    end

    it "contains TOML frontmatter" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content
      content.should start_with("+++")
      content.should contain("title")
    end

    it "contains Hwaro branding" do
      Hwaro::Services::Defaults::ContentSamples.index_content.should contain("Hwaro")
    end

    it "includes tags" do
      Hwaro::Services::Defaults::ContentSamples.index_content.should contain("tags")
    end
  end

  describe ".about_content" do
    it "returns non-empty content" do
      Hwaro::Services::Defaults::ContentSamples.about_content.should_not be_empty
    end

    it "has About title" do
      Hwaro::Services::Defaults::ContentSamples.about_content.should contain("About")
    end

    it "includes tags and categories" do
      content = Hwaro::Services::Defaults::ContentSamples.about_content
      content.should contain("tags")
      content.should contain("categories")
    end
  end

  describe ".blog_index_content" do
    it "returns non-empty content" do
      Hwaro::Services::Defaults::ContentSamples.blog_index_content.should_not be_empty
    end

    it "has Blog title" do
      Hwaro::Services::Defaults::ContentSamples.blog_index_content.should contain("Blog")
    end
  end

  describe ".blog_post_content" do
    it "returns non-empty content" do
      Hwaro::Services::Defaults::ContentSamples.blog_post_content.should_not be_empty
    end

    it "has a date field" do
      Hwaro::Services::Defaults::ContentSamples.blog_post_content.should contain("date")
    end

    it "includes tags and categories" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_post_content
      content.should contain("tags")
      content.should contain("categories")
    end

    it "includes authors" do
      Hwaro::Services::Defaults::ContentSamples.blog_post_content.should contain("authors")
    end
  end

  describe ".index_content_simple" do
    it "returns non-empty content" do
      Hwaro::Services::Defaults::ContentSamples.index_content_simple.should_not be_empty
    end

    it "does not contain tags" do
      Hwaro::Services::Defaults::ContentSamples.index_content_simple.should_not contain("tags =")
    end

    it "contains TOML frontmatter" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_simple
      content.should start_with("+++")
    end
  end

  describe ".about_content_simple" do
    it "returns non-empty content" do
      Hwaro::Services::Defaults::ContentSamples.about_content_simple.should_not be_empty
    end

    it "does not contain tags" do
      Hwaro::Services::Defaults::ContentSamples.about_content_simple.should_not contain("tags =")
    end

    it "does not contain categories" do
      Hwaro::Services::Defaults::ContentSamples.about_content_simple.should_not contain("categories =")
    end
  end

  describe ".index_content_multilingual" do
    it "generates English content by default" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("en", true)
      content.should contain("Welcome to Hwaro")
      content.should contain("Hello, Hwaro!")
    end

    it "generates Korean content" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("ko", false)
      content.should contain("Hwaro에 오신 것을 환영합니다")
      content.should contain("안녕하세요")
    end

    it "generates Japanese content" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("ja", false)
      content.should contain("Hwaroへようこそ")
    end

    it "includes tags when skip_taxonomies is false" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("en", true, skip_taxonomies: false)
      content.should contain("tags")
    end

    it "excludes tags when skip_taxonomies is true" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("en", true, skip_taxonomies: true)
      content.should_not contain("tags =")
    end

    it "uses content path for non-default language" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("ko", false)
      content.should contain("content/ko")
    end

    it "uses content path without language prefix for default language" do
      content = Hwaro::Services::Defaults::ContentSamples.index_content_multilingual("en", true)
      content.should contain("content/index.md")
    end
  end

  describe ".about_content_multilingual" do
    it "generates English content by default" do
      content = Hwaro::Services::Defaults::ContentSamples.about_content_multilingual("en")
      content.should contain("About")
    end

    it "generates Korean content" do
      content = Hwaro::Services::Defaults::ContentSamples.about_content_multilingual("ko")
      content.should contain("소개")
    end

    it "includes taxonomy metadata when not skipped" do
      content = Hwaro::Services::Defaults::ContentSamples.about_content_multilingual("en", skip_taxonomies: false)
      content.should contain("tags")
      content.should contain("categories")
    end

    it "excludes taxonomy metadata when skipped" do
      content = Hwaro::Services::Defaults::ContentSamples.about_content_multilingual("en", skip_taxonomies: true)
      content.should_not contain("tags =")
      content.should_not contain("categories =")
    end
  end

  describe ".blog_index_content_multilingual" do
    it "generates English content" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_index_content_multilingual("en")
      content.should contain("Blog")
    end

    it "generates Korean content" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_index_content_multilingual("ko")
      content.should contain("블로그")
    end

    it "generates Japanese content" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_index_content_multilingual("ja")
      content.should contain("ブログ")
    end
  end

  describe ".blog_post_content_multilingual" do
    it "generates English content" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_post_content_multilingual("en")
      content.should contain("Hello World")
    end

    it "generates Korean content" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_post_content_multilingual("ko")
      content.should contain("안녕 세상")
    end

    it "always includes date" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_post_content_multilingual("en")
      content.should contain("date")
    end

    it "includes taxonomy metadata when not skipped" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_post_content_multilingual("en", skip_taxonomies: false)
      content.should contain("tags")
      content.should contain("categories")
      content.should contain("authors")
    end

    it "excludes taxonomy metadata when skipped" do
      content = Hwaro::Services::Defaults::ContentSamples.blog_post_content_multilingual("en", skip_taxonomies: true)
      content.should_not contain("tags =")
      content.should_not contain("categories =")
      content.should_not contain("authors =")
    end
  end

  describe "all content methods" do
    it "return valid TOML frontmatter format" do
      contents = [
        Hwaro::Services::Defaults::ContentSamples.index_content,
        Hwaro::Services::Defaults::ContentSamples.about_content,
        Hwaro::Services::Defaults::ContentSamples.blog_index_content,
        Hwaro::Services::Defaults::ContentSamples.blog_post_content,
        Hwaro::Services::Defaults::ContentSamples.index_content_simple,
        Hwaro::Services::Defaults::ContentSamples.about_content_simple,
      ]

      contents.each do |content|
        content.should start_with("+++")
        content.count("+++").should be >= 2
      end
    end
  end
end
