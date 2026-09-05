require "../../../spec_helper"
require "../../../../src/services/defaults/config"
require "../../../../src/utils/permalink_resolver"

# Helper to load a Config from a TOML string via a temp file.
private def load_versions_config(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-versions", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

private def expect_versions_config_error(toml : String, & : String ->)
  err = expect_raises(Hwaro::HwaroError) { load_versions_config(toml) }
  err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
  yield err.message || ""
end

BASE = "title = \"T\"\nbase_url = \"http://localhost\"\n"

describe Hwaro::Models::VersionsConfig do
  describe "loading" do
    it "is disabled by default" do
      config = load_versions_config(BASE)
      config.versions.enabled?.should be_false
      config.versions.latest.should be_nil
      config.versions.for_path("docs/v1/a.md").should be_nil
    end

    it "loads [versions] switches + [[versions.list]] entries" do
      config = load_versions_config(BASE + <<-TOML)
        [versions]
        latest_at_root = false
        noindex_old = false
        search = "all"
        feeds = "ALL"
        taxonomies = "latest"

        [[versions.list]]
        name = "v2"
        label = "2.x (latest)"
        path = "docs/v2"
        latest = true

        [[versions.list]]
        name = "v1"
        TOML
      v = config.versions
      v.enabled?.should be_true
      v.latest_at_root.should be_false
      v.noindex_old.should be_false
      v.search.should eq("all")
      v.feeds.should eq("all")
      v.taxonomies.should eq("latest")
      v.list.map(&.name).should eq(["v2", "v1"])
      v.latest.try(&.name).should eq("v2")
      v.find("v1").try(&.label).should eq("v1")
      v.find("v1").try(&.path).should eq("v1") # path defaults to name
      v.for_path("docs/v2/install.md").try(&.name).should eq("v2")
      v.for_path("docs/v2").try(&.name).should eq("v2")
      v.for_path("docs/v20/install.md").should be_nil
      v.for_path("v1/x.md").try(&.name).should eq("v1")
    end

    it "accepts a bare [[versions]] array (entries only, default switches)" do
      config = load_versions_config(BASE + "[[versions]]\nname = \"v2\"\npath = \"docs/v2\"\n[[versions]]\nname = \"v1\"\npath = \"docs/v1\"\n")
      config.versions.enabled?.should be_true
      config.versions.latest_at_root.should be_true
      config.versions.search.should eq("latest")
      # No explicit latest → the first entry
      config.versions.latest.try(&.name).should eq("v2")
    end

    it "normalizes paths" do
      config = load_versions_config(BASE + "[[versions]]\nname = \"v1\"\npath = \"./docs/v1/\"\n")
      config.versions.list.first.path.should eq("docs/v1")
    end

    it "does not warn about the versions key as unknown" do
      config = load_versions_config(BASE + "[versions]\nlatest_at_root = true\n[[versions.list]]\nname = \"v1\"\n")
      Hwaro::Models::Config::KNOWN_TOP_LEVEL_KEYS.should contain("versions")
      config.versions.enabled?.should be_true
    end
  end

  describe "validation" do
    it "rejects several latest = true entries" do
      expect_versions_config_error(BASE + "[[versions]]\nname = \"a\"\nlatest = true\n[[versions]]\nname = \"b\"\nlatest = true\n") do |msg|
        msg.should contain("only one version can be `latest = true`")
        msg.should contain("a, b")
      end
    end

    it "rejects a missing name" do
      expect_versions_config_error(BASE + "[[versions]]\npath = \"docs/v1\"\n") { |msg| msg.should contain("missing `name`") }
    end

    it "rejects a non URL-safe name" do
      expect_versions_config_error(BASE + "[[versions]]\nname = \"v 1/x\"\n") { |msg| msg.should contain("not URL-safe") }
    end

    it "rejects duplicate names" do
      expect_versions_config_error(BASE + "[[versions]]\nname = \"v1\"\npath = \"a\"\n[[versions]]\nname = \"v1\"\npath = \"b\"\n") { |msg| msg.should contain("declared twice") }
    end

    it "rejects shared and nested paths" do
      expect_versions_config_error(BASE + "[[versions]]\nname = \"a\"\npath = \"docs\"\n[[versions]]\nname = \"b\"\npath = \"docs\"\n") { |msg| msg.should contain("share the content path") }
      expect_versions_config_error(BASE + "[[versions]]\nname = \"a\"\npath = \"docs\"\n[[versions]]\nname = \"b\"\npath = \"docs/b\"\n") { |msg| msg.should contain("must not nest") }
    end

    it "rejects invalid paths" do
      expect_versions_config_error(BASE + "[[versions]]\nname = \"a\"\npath = \"../x\"\n") { |msg| msg.should contain("invalid path") }
      expect_versions_config_error(BASE + "[[versions]]\nname = \"a\"\npath = \"/\"\n") { |msg| msg.should contain("invalid path") }
    end

    it "explains a config that mixes [versions] with [[versions]]" do
      expect_versions_config_error(BASE + "[versions]\nlatest_at_root = true\n\n[[versions]]\nname = \"v1\"\n") do |msg|
        msg.should contain("`[versions]` and `[[versions]]` cannot both be used")
      end
      # Reverse declaration order trips a different parser message; the hint must still fire.
      expect_versions_config_error(BASE + "[[versions]]\nname = \"v1\"\n\n[versions]\nlatest_at_root = true\n") do |msg|
        msg.should contain("cannot both be used")
      end
    end

    it "rejects unknown switch values" do
      expect_versions_config_error(BASE + "[versions]\nsearch = \"some\"\n[[versions.list]]\nname = \"a\"\n") { |msg| msg.should contain("must be \"latest\" or \"all\"") }
    end
  end

  describe "URL mapping" do
    it "maps version directories for both latest_at_root modes" do
      config = load_versions_config(BASE + "[[versions]]\nname = \"v2\"\npath = \"docs/v2\"\nlatest = true\n[[versions]]\nname = \"one\"\npath = \"docs/v1\"\n")
      v2 = config.versions.find("v2").not_nil!
      v1 = config.versions.find("one").not_nil!

      resolve = ->(path : String, version : Hwaro::Models::VersionConfig, lang : String?) do
        Hwaro::Utils::PermalinkResolver.resolve_url(path, config, slug: nil, custom_path: nil, language: lang, date: nil, title: "", version: version)
      end

      resolve.call("docs/v2/install.md", v2, nil).should eq("/docs/install/")
      resolve.call("docs/v2/_index.md", v2, nil).should eq("/docs/")
      resolve.call("docs/v2/guide/index.md", v2, nil).should eq("/docs/guide/")
      # name != directory basename → URL uses the NAME
      resolve.call("docs/v1/install.md", v1, nil).should eq("/docs/one/install/")
      resolve.call("docs/v1/_index.md", v1, nil).should eq("/docs/one/")
      config.versions.root_url(v2).should eq("/docs/")
      config.versions.root_url(v1, "/ko").should eq("/ko/docs/one/")

      config.versions.latest_at_root = false
      resolve.call("docs/v2/install.md", v2, nil).should eq("/docs/v2/install/")
      resolve.call("docs/v2/_index.md", v2, nil).should eq("/docs/v2/")
      config.versions.root_url(v2).should eq("/docs/v2/")
    end

    it "handles top-level version directories" do
      config = load_versions_config(BASE + "[[versions]]\nname = \"v2\"\nlatest = true\n[[versions]]\nname = \"v1\"\n")
      v2 = config.versions.find("v2").not_nil!
      v1 = config.versions.find("v1").not_nil!
      Hwaro::Utils::PermalinkResolver.resolve_url("v2/_index.md", config, slug: nil, custom_path: nil, language: nil, date: nil, title: "", version: v2).should eq("/")
      Hwaro::Utils::PermalinkResolver.resolve_url("v2/a.md", config, slug: nil, custom_path: nil, language: nil, date: nil, title: "", version: v2).should eq("/a/")
      Hwaro::Utils::PermalinkResolver.resolve_url("v1/a.md", config, slug: nil, custom_path: nil, language: nil, date: nil, title: "", version: v1).should eq("/v1/a/")
      config.versions.root_url(v2).should eq("/")
      config.versions.root_url(v1).should eq("/v1/")
    end

    it "leaves unversioned paths and explicit custom paths alone" do
      config = load_versions_config(BASE + "[[versions]]\nname = \"v1\"\npath = \"docs/v1\"\n")
      v1 = config.versions.find("v1").not_nil!
      Hwaro::Utils::PermalinkResolver.resolve_url("blog/a.md", config, slug: nil, custom_path: nil, language: nil, date: nil, title: "", version: nil).should eq("/blog/a/")
      Hwaro::Utils::PermalinkResolver.resolve_url("docs/v1/a.md", config, slug: nil, custom_path: "custom", language: nil, date: nil, title: "", version: v1).should eq("/custom/")
    end
  end
end
