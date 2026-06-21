require "../spec_helper"
require "../../src/content/i18n"
require "../../src/content/processors/filters/i18n_filter"

describe Hwaro::Content::I18n do
  describe ".load_translations" do
    it "loads TOML translation files" do
      Dir.mktmpdir do |dir|
        i18n_dir = File.join(dir, "i18n")
        FileUtils.mkdir_p(i18n_dir)

        File.write(File.join(i18n_dir, "en.toml"), <<-TOML)
          [nav]
          home = "Home"
          about = "About"
          TOML

        File.write(File.join(i18n_dir, "ko.toml"), <<-TOML)
          [nav]
          home = "홈"
          about = "소개"
          TOML

        config = Hwaro::Models::Config.new
        config.default_language = "en"
        config.languages = {"ko" => Hwaro::Models::LanguageConfig.new("ko")}

        translations = Hwaro::Content::I18n.load_translations(i18n_dir, config)

        translations.size.should eq(2)
        translations["en"]["nav.home"].should eq("Home")
        translations["en"]["nav.about"].should eq("About")
        translations["ko"]["nav.home"].should eq("홈")
        translations["ko"]["nav.about"].should eq("소개")
      end
    end

    it "returns empty hash when i18n directory does not exist" do
      config = Hwaro::Models::Config.new
      translations = Hwaro::Content::I18n.load_translations("/nonexistent/path", config)
      translations.should be_empty
    end

    it "flattens nested TOML keys with dot notation" do
      Dir.mktmpdir do |dir|
        i18n_dir = File.join(dir, "i18n")
        FileUtils.mkdir_p(i18n_dir)

        File.write(File.join(i18n_dir, "en.toml"), <<-TOML)
          [messages]
          [messages.errors]
          not_found = "Not Found"
          [messages.success]
          saved = "Saved"
          TOML

        config = Hwaro::Models::Config.new
        config.default_language = "en"

        translations = Hwaro::Content::I18n.load_translations(i18n_dir, config)

        translations["en"]["messages.errors.not_found"].should eq("Not Found")
        translations["en"]["messages.success.saved"].should eq("Saved")
      end
    end

    it "skips missing language files" do
      Dir.mktmpdir do |dir|
        i18n_dir = File.join(dir, "i18n")
        FileUtils.mkdir_p(i18n_dir)

        File.write(File.join(i18n_dir, "en.toml"), <<-TOML)
          greeting = "Hello"
          TOML

        config = Hwaro::Models::Config.new
        config.default_language = "en"
        config.languages = {"ja" => Hwaro::Models::LanguageConfig.new("ja")}

        translations = Hwaro::Content::I18n.load_translations(i18n_dir, config)

        translations.has_key?("en").should be_true
        translations.has_key?("ja").should be_false
      end
    end

    # Resilience: a single syntactically broken i18n file must NOT abort the
    # build. The rescue in load_translations logs a warning and continues with
    # the remaining languages, so a typo in one translation file degrades
    # gracefully (that language is skipped) instead of crashing the whole build.
    it "skips a malformed TOML file with a warning and keeps valid languages" do
      Dir.mktmpdir do |dir|
        i18n_dir = File.join(dir, "i18n")
        FileUtils.mkdir_p(i18n_dir)

        File.write(File.join(i18n_dir, "en.toml"), <<-TOML)
          greeting = "Hi"
          TOML

        File.write(File.join(i18n_dir, "ko.toml"), <<-TOML)
          this = = broken
          TOML

        config = Hwaro::Models::Config.new
        config.default_language = "en"
        config.languages = {"ko" => Hwaro::Models::LanguageConfig.new("ko")}

        translations = Hwaro::Content::I18n.load_translations(i18n_dir, config)

        log = with_captured_log do
          translations = Hwaro::Content::I18n.load_translations(i18n_dir, config)
        end

        log.should contain("Failed to parse i18n file")
        translations.has_key?("en").should be_true
        translations["en"]["greeting"].should eq("Hi")
        translations.has_key?("ko").should be_false
      end
    end

    # The Array branch of flatten_toml indexes list items as key.0, key.1, etc.
    # List-valued i18n keys (e.g. nav menus) are a plausible multilingual
    # pattern; a cast regression would silently drop them. Covers string items,
    # the non-string scalar to_s fallback, and the recursive table-in-array case.
    it "flattens TOML array values into indexed keys" do
      Dir.mktmpdir do |dir|
        i18n_dir = File.join(dir, "i18n")
        FileUtils.mkdir_p(i18n_dir)

        File.write(File.join(i18n_dir, "en.toml"), <<-TOML)
          items = ["Home", "About"]
          counts = [1, 2]
          [[menu]]
          label = "First"
          [[menu]]
          label = "Second"
          TOML

        config = Hwaro::Models::Config.new
        config.default_language = "en"

        translations = Hwaro::Content::I18n.load_translations(i18n_dir, config)

        translations["en"]["items.0"].should eq("Home")
        translations["en"]["items.1"].should eq("About")
        translations["en"]["counts.0"].should eq("1")
        translations["en"]["counts.1"].should eq("2")
        translations["en"]["menu.0.label"].should eq("First")
        translations["en"]["menu.1.label"].should eq("Second")
      end
    end
  end

  describe ".translate" do
    translations = {
      "en" => {"greeting" => "Hello", "farewell" => "Goodbye"},
      "ko" => {"greeting" => "안녕하세요"},
    }

    it "returns translation for the given language" do
      Hwaro::Content::I18n.translate("greeting", "ko", translations).should eq("안녕하세요")
    end

    it "falls back to default language when key not found in current" do
      Hwaro::Content::I18n.translate("farewell", "ko", translations).should eq("Goodbye")
    end

    it "returns the key itself when not found in any language" do
      Hwaro::Content::I18n.translate("missing_key", "ko", translations).should eq("missing_key")
    end

    it "returns translation for default language directly" do
      Hwaro::Content::I18n.translate("greeting", "en", translations).should eq("Hello")
    end
  end

  describe ".pluralize" do
    it "returns singular when count is 1" do
      Hwaro::Content::I18n.pluralize(1, "item", "items").should eq("item")
    end

    it "returns plural when count is not 1" do
      Hwaro::Content::I18n.pluralize(0, "item", "items").should eq("items")
      Hwaro::Content::I18n.pluralize(2, "item", "items").should eq("items")
      Hwaro::Content::I18n.pluralize(100, "item", "items").should eq("items")
    end
  end
end

describe "I18n Crinja filters" do
  describe "t filter" do
    it "translates a key using current page language" do
      env = Crinja.new
      Hwaro::Content::Processors::Filters::I18nFilters.register(env)

      i18n_data = {
        Crinja::Value.new("ko") => Crinja::Value.new({
          Crinja::Value.new("nav.home") => Crinja::Value.new("홈"),
        }),
        Crinja::Value.new("en") => Crinja::Value.new({
          Crinja::Value.new("nav.home") => Crinja::Value.new("Home"),
        }),
      }

      template = env.from_string(%({{ "nav.home" | t }}))
      result = template.render({
        "_i18n_translations"     => Crinja::Value.new(i18n_data),
        "_i18n_default_language" => Crinja::Value.new("en"),
        "page_language"          => Crinja::Value.new("ko"),
      })
      result.should eq("홈")
    end

    it "falls back to default language" do
      env = Crinja.new
      Hwaro::Content::Processors::Filters::I18nFilters.register(env)

      i18n_data = {
        Crinja::Value.new("en") => Crinja::Value.new({
          Crinja::Value.new("title") => Crinja::Value.new("My Site"),
        }),
      }

      template = env.from_string(%({{ "title" | t }}))
      result = template.render({
        "_i18n_translations"     => Crinja::Value.new(i18n_data),
        "_i18n_default_language" => Crinja::Value.new("en"),
        "page_language"          => Crinja::Value.new("ja"),
      })
      result.should eq("My Site")
    end

    it "returns key when no translations available" do
      env = Crinja.new
      Hwaro::Content::Processors::Filters::I18nFilters.register(env)

      template = env.from_string(%({{ "unknown.key" | t }}))
      result = template.render({
        "page_language" => Crinja::Value.new("en"),
      })
      result.should eq("unknown.key")
    end
  end

  describe "pluralize filter" do
    it "returns singular for 1" do
      env = Crinja.new
      Hwaro::Content::Processors::Filters::I18nFilters.register(env)

      template = env.from_string(%({{ 1 | pluralize(singular="item", plural="items") }}))
      result = template.render({} of String => Crinja::Value)
      result.should eq("item")
    end

    it "returns plural for other counts" do
      env = Crinja.new
      Hwaro::Content::Processors::Filters::I18nFilters.register(env)

      template = env.from_string(%({{ 5 | pluralize(singular="item", plural="items") }}))
      result = template.render({} of String => Crinja::Value)
      result.should eq("items")
    end
  end
end
