require "../spec_helper"
require "../../src/services/defaults/config"

describe Hwaro::Services::Defaults::ConfigSamples do
  describe ".config" do
    it "returns non-empty config string" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should_not be_empty
    end

    it "includes site title" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("title")
    end

    it "includes site description" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("description")
    end

    it "includes base_url" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("base_url")
    end

    it "includes localhost base_url by default" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("http://localhost:3000")
    end

    it "includes search configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[search]")
      config.should contain("enabled = true")
      config.should contain("format = \"fuse_json\"")
      config.should contain("filename = \"search.json\"")
    end

    it "includes sitemap configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[sitemap]")
      config.should contain("filename = \"sitemap.xml\"")
      config.should contain("changefreq")
      config.should contain("priority")
    end

    it "includes robots configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[robots]")
      config.should contain("filename = \"robots.txt\"")
      config.should contain("user_agent")
    end

    it "includes llms configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[llms]")
      config.should contain("filename = \"llms.txt\"")
      config.should contain("instructions")
    end

    it "includes feeds configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[feeds]")
      config.should contain("type = \"rss\"")
    end

    it "includes plugins configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[plugins]")
      config.should contain("processors")
      config.should contain("markdown")
    end

    it "includes taxonomy configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("[[taxonomies]]")
      config.should contain("name = \"tags\"")
      config.should contain("name = \"categories\"")
      config.should contain("name = \"authors\"")
    end

    it "includes build hooks as comments" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("Build Hooks")
    end

    it "includes deployment as comments" do
      config = Hwaro::Services::Defaults::ConfigSamples.config
      config.should contain("Deployment")
    end
  end

  describe ".config_without_taxonomies" do
    it "returns non-empty config string" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should_not be_empty
    end

    it "includes base_url" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("base_url")
    end

    it "includes search configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("[search]")
    end

    it "includes sitemap configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("[sitemap]")
    end

    it "includes robots configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("[robots]")
    end

    it "includes llms configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("[llms]")
    end

    it "includes feeds configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("[feeds]")
    end

    it "includes plugins configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should contain("[plugins]")
    end

    it "does not include taxonomy configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies
      config.should_not contain("[[taxonomies]]")
      config.should_not contain("name = \"tags\"")
      config.should_not contain("name = \"categories\"")
      config.should_not contain("name = \"authors\"")
    end

    it "has all the same sections as config except taxonomies" do
      with_tax = Hwaro::Services::Defaults::ConfigSamples.config
      without_tax = Hwaro::Services::Defaults::ConfigSamples.config_without_taxonomies

      # Both should have the same core sections
      ["[search]", "[sitemap]", "[robots]", "[llms]", "[feeds]", "[plugins]"].each do |section|
        with_tax.should contain(section)
        without_tax.should contain(section)
      end
    end
  end

  describe ".config_multilingual" do
    it "returns non-empty config string" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"])
      config.should_not be_empty
    end

    it "includes default_language" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"])
      config.should contain("default_language = \"en\"")
    end

    it "uses first language as default_language" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["ko", "en"])
      config.should contain("default_language = \"ko\"")
    end

    it "includes language configurations" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"])
      config.should contain("[languages.en]")
      config.should contain("[languages.ko]")
    end

    it "includes language display names" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko", "ja"])
      config.should contain("English")
      config.should contain("한국어")
      config.should contain("日本語")
    end

    it "includes language weight based on order" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko", "ja"])
      config.should contain("weight = 1")
      config.should contain("weight = 2")
      config.should contain("weight = 3")
    end

    it "includes generate_feed for each language" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"])
      config.should contain("generate_feed = true")
    end

    it "includes build_search_index for each language" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"])
      config.should contain("build_search_index = true")
    end

    it "includes taxonomies in language config by default" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"])
      config.should contain("taxonomies")
    end

    it "excludes taxonomies from language config when skipped" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en", "ko"], skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end

    it "includes root-level taxonomy config by default" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"])
      config.should contain("[[taxonomies]]")
      config.should contain("name = \"tags\"")
    end

    it "excludes root-level taxonomy config when skipped" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"], skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end

    it "includes search configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"])
      config.should contain("[search]")
    end

    it "includes sitemap configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"])
      config.should contain("[sitemap]")
    end

    it "includes feeds configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"])
      config.should contain("[feeds]")
    end

    it "handles unknown language codes with uppercase fallback" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["xx"])
      config.should contain("XX")
    end

    it "supports many languages" do
      langs = ["en", "ko", "ja", "zh", "es", "fr", "de"]
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(langs)
      config.should contain("English")
      config.should contain("한국어")
      config.should contain("日本語")
      config.should contain("中文")
      config.should contain("Español")
      config.should contain("Français")
      config.should contain("Deutsch")
    end

    it "handles additional language codes" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["pt", "ru", "it", "nl", "pl", "vi", "th", "ar", "hi"])
      config.should contain("Português")
      config.should contain("Русский")
      config.should contain("Italiano")
      config.should contain("Nederlands")
      config.should contain("Polski")
      config.should contain("Tiếng Việt")
      config.should contain("ไทย")
      config.should contain("العربية")
      config.should contain("हिन्दी")
    end

    it "handles empty language array gracefully" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual([] of String)
      config.should_not be_empty
      config.should contain("base_url")
    end

    it "defaults to en when language array is empty" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual([] of String)
      config.should contain("default_language = \"en\"")
    end

    it "includes plugins configuration" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"])
      config.should contain("[plugins]")
      config.should contain("markdown")
    end

    it "includes deployment comments" do
      config = Hwaro::Services::Defaults::ConfigSamples.config_multilingual(["en"])
      config.should contain("Deployment")
    end
  end
end
