require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose the private method for testing
module Hwaro::Core::Build
  class Builder
    def test_calculate_page_url(page : Models::Page)
      calculate_page_url(page)
    end

    def test_set_config(config : Models::Config)
      @config = config
    end
  end
end

describe Hwaro::Core::Build::Builder do
  describe "#calculate_page_url" do
    # -----------------------------------------------------------------------
    # Basic URL generation for regular pages
    # -----------------------------------------------------------------------
    describe "regular pages" do
      it "generates URL from filename for root-level page" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("about.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/about/")
      end

      it "generates URL for nested page" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("blog/my-post.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/my-post/")
      end

      it "generates URL for deeply nested page" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("docs/guide/advanced/topic.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/docs/guide/advanced/topic/")
      end

      it "always ends with trailing slash" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("contact.md")
        builder.test_calculate_page_url(page)

        page.url.ends_with?("/").should be_true
      end

      it "always starts with leading slash" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("page.md")
        builder.test_calculate_page_url(page)

        page.url.starts_with?("/").should be_true
      end
    end

    # -----------------------------------------------------------------------
    # Index (section) pages
    # -----------------------------------------------------------------------
    describe "index pages" do
      it "generates / for root index" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/")
      end

      it "generates /section/ for section index" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("blog/_index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/")
      end

      it "generates /nested/section/ for nested section index" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("docs/guide/_index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/docs/guide/")
      end
    end

    # -----------------------------------------------------------------------
    # Slug-based URLs
    # -----------------------------------------------------------------------
    describe "slug override" do
      it "uses slug instead of filename" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("blog/my-long-title-post.md")
        page.slug = "short"
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/short/")
      end

      it "uses slug for root-level page" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("original-name.md")
        page.slug = "new-name"
        builder.test_calculate_page_url(page)

        page.url.should eq("/new-name/")
      end

      it "ignores slug for index pages (uses directory path)" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("blog/_index.md")
        page.is_index = true
        page.slug = "custom-slug"
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/")
      end
    end

    # -----------------------------------------------------------------------
    # Custom path override
    # -----------------------------------------------------------------------
    describe "custom path" do
      it "uses custom_path as the URL" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("some/original.md")
        page.custom_path = "/archive/2024/my-post/"
        builder.test_calculate_page_url(page)

        page.url.should eq("/archive/2024/my-post/")
      end

      it "adds trailing slash to custom_path if missing" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("test.md")
        page.custom_path = "/custom/path"
        builder.test_calculate_page_url(page)

        page.url.ends_with?("/").should be_true
      end

      it "handles custom_path with leading slash" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("test.md")
        page.custom_path = "/my/custom/url/"
        builder.test_calculate_page_url(page)

        page.url.should eq("/my/custom/url/")
      end

      it "custom_path takes priority over slug" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("test.md")
        page.slug = "my-slug"
        page.custom_path = "/overridden/"
        builder.test_calculate_page_url(page)

        page.url.should eq("/overridden/")
      end
    end

    # -----------------------------------------------------------------------
    # Permalink remapping
    # -----------------------------------------------------------------------
    describe "permalinks" do
      it "remaps exact directory match" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"old/posts" => "posts"}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("old/posts/article.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/posts/article/")
      end

      it "remaps nested subdirectory under permalink source" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"old/posts" => "archive"}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("old/posts/2024/article.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/archive/2024/article/")
      end

      it "does not remap when directory does not match" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"old/posts" => "posts"}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("blog/article.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/article/")
      end

      it "remaps index pages as well" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"old" => "new"}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("old/_index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/new/")
      end

      it "handles multiple permalink rules (first match wins)" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {
          "2023/drafts" => "archive/2023",
          "old/posts"   => "posts",
        }
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("2023/drafts/wip.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/archive/2023/wip/")
      end

      it "maps a flat file under an empty-target source to root" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"pages" => ""}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("pages/about.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/about/")
      end

      it "maps a nested subdirectory under an empty-target source to root without doubling slashes" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"pages" => ""}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("pages/contact/info.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/contact/info/")
      end

      it "maps a nested section index under an empty-target source to root without doubling slashes" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {"pages" => ""}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("pages/contact/_index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/contact/")
      end
    end

    # -----------------------------------------------------------------------
    # Multilingual URL prefixing
    # -----------------------------------------------------------------------
    describe "multilingual URLs" do
      it "adds language prefix for non-default language" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("about/index.ko.md")
        page.language = "ko"
        builder.test_calculate_page_url(page)

        page.url.should start_with("/ko/")
      end

      it "does not add language prefix for default language" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("about.md")
        page.language = "en"
        builder.test_calculate_page_url(page)

        page.url.should_not start_with("/en/")
        page.url.should eq("/about/")
      end

      it "does not add prefix when language is nil" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("about.md")
        page.language = nil
        builder.test_calculate_page_url(page)

        page.url.should eq("/about/")
      end

      it "adds language prefix for non-default language index page" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("blog/_index.ko.md")
        page.language = "ko"
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/ko/blog/")
      end

      it "generates /lang/ for root index in non-default language" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("_index.ja.md")
        page.language = "ja"
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/ja/")
      end

      it "strips language suffix from regular page stem" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("about/hello.ko.md")
        page.language = "ko"
        builder.test_calculate_page_url(page)

        page.url.should eq("/ko/about/hello/")
        page.url.should_not contain(".ko")
      end

      it "combines language prefix with custom_path" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("test.ko.md")
        page.language = "ko"
        page.custom_path = "/custom/path/"
        builder.test_calculate_page_url(page)

        page.url.should eq("/ko/custom/path/")
      end

      it "combines language prefix with permalink remapping" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.default_language = "en"
        config.permalinks = {"old" => "new"}
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("old/post.ko.md")
        page.language = "ko"
        builder.test_calculate_page_url(page)

        page.url.should eq("/ko/new/post/")
      end
    end

    # -----------------------------------------------------------------------
    # Edge cases
    # -----------------------------------------------------------------------
    describe "edge cases" do
      it "handles page bundle index.md" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("blog/my-post/index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/my-post/")
      end

      it "handles page with hyphens and numbers" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("blog/2024-01-15-my-first-post.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/2024-01-15-my-first-post/")
      end

      it "handles page in root with no directory" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("standalone.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/standalone/")
      end

      it "handles _index.md at root as root index" do
        builder = Hwaro::Core::Build::Builder.new
        builder.test_set_config(Hwaro::Models::Config.new)

        page = Hwaro::Models::Page.new("_index.md")
        page.is_index = true
        builder.test_calculate_page_url(page)

        page.url.should eq("/")
      end

      it "empty permalinks hash does not change URL" do
        builder = Hwaro::Core::Build::Builder.new
        config = Hwaro::Models::Config.new
        config.permalinks = {} of String => String
        builder.test_set_config(config)

        page = Hwaro::Models::Page.new("blog/post.md")
        builder.test_calculate_page_url(page)

        page.url.should eq("/blog/post/")
      end
    end
  end
end
