require "../spec_helper"

describe Hwaro::Content::Multilingual do
  describe ".multilingual?" do
    it "returns false when no languages are configured" do
      config = Hwaro::Models::Config.new
      Hwaro::Content::Multilingual.multilingual?(config).should be_false
    end

    it "returns true when languages are configured" do
      config = Hwaro::Models::Config.new
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      Hwaro::Content::Multilingual.multilingual?(config).should be_true
    end

    it "returns true when multiple languages are configured" do
      config = Hwaro::Models::Config.new
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")
      Hwaro::Content::Multilingual.multilingual?(config).should be_true
    end
  end

  describe ".language_code" do
    it "returns page language when set" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      page = Hwaro::Models::Page.new("test.ko.md")
      page.language = "ko"

      Hwaro::Content::Multilingual.language_code(page, config).should eq("ko")
    end

    it "falls back to default_language when page language is nil" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      page = Hwaro::Models::Page.new("test.md")
      page.language = nil

      Hwaro::Content::Multilingual.language_code(page, config).should eq("en")
    end

    it "returns custom default language when configured" do
      config = Hwaro::Models::Config.new
      config.default_language = "fr"

      page = Hwaro::Models::Page.new("test.md")
      page.language = nil

      Hwaro::Content::Multilingual.language_code(page, config).should eq("fr")
    end

    it "returns page language over default" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      page = Hwaro::Models::Page.new("test.ja.md")
      page.language = "ja"

      Hwaro::Content::Multilingual.language_code(page, config).should eq("ja")
    end
  end

  describe ".ordered_language_codes" do
    it "returns default language first" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      ko = Hwaro::Models::LanguageConfig.new("ko")
      ko.weight = 2
      config.languages["ko"] = ko

      codes = Hwaro::Content::Multilingual.ordered_language_codes(config)
      codes.first.should eq("en")
    end

    it "includes all configured language codes" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      ko = Hwaro::Models::LanguageConfig.new("ko")
      ko.weight = 2
      config.languages["ko"] = ko

      ja = Hwaro::Models::LanguageConfig.new("ja")
      ja.weight = 3
      config.languages["ja"] = ja

      codes = Hwaro::Content::Multilingual.ordered_language_codes(config)
      codes.should contain("en")
      codes.should contain("ko")
      codes.should contain("ja")
    end

    it "does not duplicate default language" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      en = Hwaro::Models::LanguageConfig.new("en")
      en.weight = 1
      config.languages["en"] = en

      ko = Hwaro::Models::LanguageConfig.new("ko")
      ko.weight = 2
      config.languages["ko"] = ko

      codes = Hwaro::Content::Multilingual.ordered_language_codes(config)
      codes.count("en").should eq(1)
    end

    it "returns only default language when no additional languages configured" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      codes = Hwaro::Content::Multilingual.ordered_language_codes(config)
      codes.should eq(["en"])
    end

    it "places default language at start even if not in languages hash" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      fr = Hwaro::Models::LanguageConfig.new("fr")
      fr.weight = 1
      config.languages["fr"] = fr

      codes = Hwaro::Content::Multilingual.ordered_language_codes(config)
      codes.first.should eq("en")
      codes.should contain("fr")
    end
  end

  describe ".translation_key" do
    it "returns the path unchanged for non-md files" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"

      key = Hwaro::Content::Multilingual.translation_key("about/image.png", config)
      key.should eq("about/image.png")
    end

    it "strips language code from filename" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      key = Hwaro::Content::Multilingual.translation_key("about/index.ko.md", config)
      key.should eq("about/index.md")
    end

    it "preserves default language files unchanged" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      key = Hwaro::Content::Multilingual.translation_key("about/index.md", config)
      key.should eq("about/index.md")
    end

    it "strips language code for multiple configured languages" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")

      key_ko = Hwaro::Content::Multilingual.translation_key("blog/post.ko.md", config)
      key_ja = Hwaro::Content::Multilingual.translation_key("blog/post.ja.md", config)
      key_en = Hwaro::Content::Multilingual.translation_key("blog/post.md", config)

      key_ko.should eq("blog/post.md")
      key_ja.should eq("blog/post.md")
      key_en.should eq("blog/post.md")
    end

    it "handles files in root directory (no subdirectory)" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      key = Hwaro::Content::Multilingual.translation_key("index.ko.md", config)
      key.should eq("index.md")
    end

    it "handles default language files in root directory" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      key = Hwaro::Content::Multilingual.translation_key("index.md", config)
      key.should eq("index.md")
    end

    it "handles deeply nested paths" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      key = Hwaro::Content::Multilingual.translation_key("docs/guide/advanced/setup.ko.md", config)
      key.should eq("docs/guide/advanced/setup.md")
    end

    it "does not strip non-language-code segments from filename" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      # "test" is not a configured language code, so it should remain
      key = Hwaro::Content::Multilingual.translation_key("blog/post.test.md", config)
      key.should eq("blog/post.test.md")
    end

    it "handles backslash paths by normalizing to forward slashes" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      key = Hwaro::Content::Multilingual.translation_key("blog\\post.ko.md", config)
      key.should eq("blog/post.md")
    end
  end

  describe ".link_translations!" do
    it "does nothing when not multilingual" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      # No additional languages configured

      page = Hwaro::Models::Page.new("about.md")
      page.url = "/about/"

      Hwaro::Content::Multilingual.link_translations!([page], config)
      page.translations.should be_empty
    end

    it "links two translation variants" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("about/index.md")
      en_page.title = "About"
      en_page.url = "/about/"
      en_page.language = nil # default language

      ko_page = Hwaro::Models::Page.new("about/index.ko.md")
      ko_page.title = "소개"
      ko_page.url = "/ko/about/"
      ko_page.language = "ko"

      Hwaro::Content::Multilingual.link_translations!([en_page, ko_page], config)

      en_page.translations.size.should eq(2)
      en_page.translations.map(&.code).should contain("en")
      en_page.translations.map(&.code).should contain("ko")

      ko_page.translations.size.should eq(2)
      ko_page.translations.map(&.code).should contain("en")
      ko_page.translations.map(&.code).should contain("ko")
    end

    it "marks the current page correctly" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("test.md")
      en_page.title = "Test"
      en_page.url = "/test/"

      ko_page = Hwaro::Models::Page.new("test.ko.md")
      ko_page.title = "테스트"
      ko_page.url = "/ko/test/"
      ko_page.language = "ko"

      Hwaro::Content::Multilingual.link_translations!([en_page, ko_page], config)

      en_current = en_page.translations.find(&.is_current)
      en_current.should_not be_nil
      en_current.not_nil!.code.should eq("en")

      ko_current = ko_page.translations.find(&.is_current)
      ko_current.should_not be_nil
      ko_current.not_nil!.code.should eq("ko")
    end

    it "links three language variants" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")

      en_page = Hwaro::Models::Page.new("about.md")
      en_page.title = "About"
      en_page.url = "/about/"

      ko_page = Hwaro::Models::Page.new("about.ko.md")
      ko_page.title = "소개"
      ko_page.url = "/ko/about/"
      ko_page.language = "ko"

      ja_page = Hwaro::Models::Page.new("about.ja.md")
      ja_page.title = "紹介"
      ja_page.url = "/ja/about/"
      ja_page.language = "ja"

      Hwaro::Content::Multilingual.link_translations!([en_page, ko_page, ja_page], config)

      en_page.translations.size.should eq(3)
      ko_page.translations.size.should eq(3)
      ja_page.translations.size.should eq(3)

      en_page.translations.map(&.code).should contain("en")
      en_page.translations.map(&.code).should contain("ko")
      en_page.translations.map(&.code).should contain("ja")
    end

    it "does not link unrelated pages" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      about_en = Hwaro::Models::Page.new("about.md")
      about_en.title = "About"
      about_en.url = "/about/"

      contact_en = Hwaro::Models::Page.new("contact.md")
      contact_en.title = "Contact"
      contact_en.url = "/contact/"

      about_ko = Hwaro::Models::Page.new("about.ko.md")
      about_ko.title = "소개"
      about_ko.url = "/ko/about/"
      about_ko.language = "ko"

      Hwaro::Content::Multilingual.link_translations!([about_en, contact_en, about_ko], config)

      # about pages should be linked together
      about_en.translations.size.should eq(2)
      about_ko.translations.size.should eq(2)

      # contact page should not have translations (only one variant)
      contact_en.translations.size.should eq(1)
      contact_en.translations.first.code.should eq("en")
    end

    it "sets is_default flag for default language translation" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("test.md")
      en_page.title = "Test"
      en_page.url = "/test/"

      ko_page = Hwaro::Models::Page.new("test.ko.md")
      ko_page.title = "테스트"
      ko_page.url = "/ko/test/"
      ko_page.language = "ko"

      Hwaro::Content::Multilingual.link_translations!([en_page, ko_page], config)

      en_default = en_page.translations.find(&.is_default)
      en_default.should_not be_nil
      en_default.not_nil!.code.should eq("en")

      ko_default = ko_page.translations.find(&.is_default)
      ko_default.should_not be_nil
      ko_default.not_nil!.code.should eq("en")
    end

    it "preserves translation URLs correctly" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("blog/post.md")
      en_page.title = "My Post"
      en_page.url = "/blog/post/"

      ko_page = Hwaro::Models::Page.new("blog/post.ko.md")
      ko_page.title = "내 글"
      ko_page.url = "/ko/blog/post/"
      ko_page.language = "ko"

      Hwaro::Content::Multilingual.link_translations!([en_page, ko_page], config)

      en_ko_link = en_page.translations.find { |t| t.code == "ko" }
      en_ko_link.should_not be_nil
      en_ko_link.not_nil!.url.should eq("/ko/blog/post/")

      ko_en_link = ko_page.translations.find { |t| t.code == "en" }
      ko_en_link.should_not be_nil
      ko_en_link.not_nil!.url.should eq("/blog/post/")
    end

    it "skips non-markdown files" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      html_page = Hwaro::Models::Page.new("about.html")
      html_page.title = "About"
      html_page.url = "/about/"

      Hwaro::Content::Multilingual.link_translations!([html_page], config)
      html_page.translations.should be_empty
    end
  end
end
