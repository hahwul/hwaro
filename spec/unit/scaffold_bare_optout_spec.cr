require "../spec_helper"
require "../../src/services/scaffolds/registry"

# `Bare` overrode only `config_content`, which `hwaro init` reaches solely
# via `--full-config`. The DEFAULT path and `--minimal-config` both build on
# `minimal_config_content`, so the "no batteries" opt-out was dead code in
# the common case: the emitted config enabled taxonomies, search and
# highlight even though `bare` ships no taxonomy templates and no search UI.
private def bare_scaffold : Hwaro::Services::Scaffolds::Base
  Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Bare)
end

describe "bare scaffold feature opt-out" do
  describe "#minimal_config_content" do
    it "omits taxonomies, search and highlight" do
      config = bare_scaffold.minimal_config_content

      config.should_not contain("[[taxonomies]]")
      config.should_not contain("[search]")
      config.should_not contain("[highlight]")
    end

    it "still emits the sections bare does ship" do
      config = bare_scaffold.minimal_config_content

      config.should contain("title = ")
      config.should contain("base_url = ")
      config.should contain("[plugins]")
      config.should contain("[content.files]")
      config.should contain("[sitemap]")
      config.should contain("[feeds]")
    end

    it "keeps multilingual support" do
      config = bare_scaffold.minimal_config_content(multilingual_languages: ["en", "ko"])

      config.should contain("default_language = \"en\"")
      config.should contain("[languages]")
      config.should contain("[languages.ko]")
      # …without dragging the opted-out sections back in.
      config.should_not contain("[[taxonomies]]")
      config.should_not contain("[search]")
    end

    it "agrees with #config_content about which features are on" do
      minimal = bare_scaffold.minimal_config_content
      full = bare_scaffold.config_content

      {"[[taxonomies]]", "[search]", "[highlight]"}.each do |section|
        minimal.includes?(section).should eq(full.includes?(section))
      end
    end

    it "parses as valid TOML" do
      config = bare_scaffold.minimal_config_content(multilingual_languages: ["en", "ko"])
      parsed = TOML.parse(config)
      parsed["title"]?.should_not be_nil
      parsed["languages"]?.should_not be_nil
      parsed["search"]?.should be_nil
      parsed["taxonomies"]?.should be_nil
    end
  end

  describe "other scaffolds" do
    it "still enable taxonomies, search and highlight by default" do
      [
        Hwaro::Config::Options::ScaffoldType::Simple,
        Hwaro::Config::Options::ScaffoldType::Blog,
        Hwaro::Config::Options::ScaffoldType::Docs,
        Hwaro::Config::Options::ScaffoldType::Book,
      ].each do |type|
        config = Hwaro::Services::Scaffolds::Registry.get(type).minimal_config_content
        config.should contain("[[taxonomies]]")
        config.should contain("[search]")
        config.should contain("[highlight]")
      end
    end

    it "honours skip_taxonomies without dropping search or highlight" do
      config = Hwaro::Services::Scaffolds::Registry
        .get(Hwaro::Config::Options::ScaffoldType::Simple)
        .minimal_config_content(skip_taxonomies: true)

      config.should_not contain("[[taxonomies]]")
      config.should contain("[search]")
      config.should contain("[highlight]")
    end
  end
end
