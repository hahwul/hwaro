require "../../spec_helper"

private def versioned_page(config : Hwaro::Models::Config, path : String, url : String, language : String? = nil) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.url = url
  page.language = language
  page.version = config.versions.for_path(path)
  page
end

describe Hwaro::Content::Versions do
  describe ".link!" do
    it "matches a counterpart that spells out the default language suffix" do
      config = load_config(<<-TOML)
        title = "T"
        base_url = "https://example.com"
        default_language = "en"
        [languages.en]
        language_name = "English"
        [languages.ko]
        language_name = "Korean"
        [[versions.list]]
        name = "v2"
        path = "docs/v2"
        latest = true
        [[versions.list]]
        name = "v1"
        path = "docs/v1"
        TOML
      # ReadContent leaves default-language pages at `language = nil` whether
      # or not the file names the suffix.
      v1 = versioned_page(config, "docs/v1/install.md", "/docs/v1/install/")
      v2 = versioned_page(config, "docs/v2/install.en.md", "/docs/install/")
      v1_ko = versioned_page(config, "docs/v1/install.ko.md", "/ko/docs/v1/install/", "ko")

      Hwaro::Content::Versions.link!([v1, v2, v1_ko], config)

      v1.version_links.map { |l| {l.name, l.url, l.exists} }.should eq([{"v2", "/docs/install/", true}, {"v1", "/docs/v1/install/", true}])
      v2.version_links.map { |l| {l.name, l.url, l.exists} }.should eq([{"v2", "/docs/install/", true}, {"v1", "/docs/v1/install/", true}])
      # Still language-scoped: the Korean page has no v2 counterpart.
      v1_ko.version_links.find!(&.latest).exists.should be_false
    end

    it "keeps an undeclared suffix as part of the name on a single-language site" do
      config = load_config(<<-TOML)
        title = "T"
        base_url = "https://example.com"
        [[versions.list]]
        name = "v2"
        path = "docs/v2"
        latest = true
        [[versions.list]]
        name = "v1"
        path = "docs/v1"
        TOML
      # Not multilingual: `install.en.md` is a page published at /install.en/.
      v1 = versioned_page(config, "docs/v1/install.md", "/docs/v1/install/")
      v2 = versioned_page(config, "docs/v2/install.en.md", "/docs/install.en/")

      Hwaro::Content::Versions.link!([v1, v2], config)

      v1.version_links.find!(&.latest).exists.should be_false
    end
  end
end
