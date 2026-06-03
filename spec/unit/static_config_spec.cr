require "../spec_helper"

# Helper to load a Config from a TOML string via a temp file.
private def load_config(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-static-config", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe Hwaro::Models::StaticConfig do
  describe "#initialize" do
    it "defaults to an empty exclude list with default excludes enabled" do
      config = Hwaro::Models::StaticConfig.new
      config.exclude.should eq([] of String)
      config.use_default_excludes.should be_true
    end
  end

  describe "#excluded?" do
    it "does not exclude ordinary files" do
      config = Hwaro::Models::StaticConfig.new
      config.excluded?("robots.txt").should be_false
      config.excluded?("css/main.css").should be_false
    end

    it "never excludes legitimate dot-paths like .well-known" do
      config = Hwaro::Models::StaticConfig.new
      config.excluded?(".well-known/security.txt").should be_false
      config.excluded?(".well-known/humans.txt").should be_false
    end

    it "excludes OS/VCS cruft by default at any depth" do
      config = Hwaro::Models::StaticConfig.new
      config.excluded?(".DS_Store").should be_true
      config.excluded?("css/.DS_Store").should be_true
      config.excluded?("Thumbs.db").should be_true
      config.excluded?("assets/desktop.ini").should be_true
      config.excluded?(".git/config").should be_true
      config.excluded?("nested/.git/HEAD").should be_true
    end

    it "excludes transient editor files by suffix, including hidden variants" do
      config = Hwaro::Models::StaticConfig.new
      config.excluded?("notes.txt~").should be_true
      config.excluded?(".index.html.swp").should be_true
      config.excluded?("dir/file.swo").should be_true
    end

    it "honors use_default_excludes = false" do
      config = Hwaro::Models::StaticConfig.new
      config.use_default_excludes = false
      config.excluded?(".DS_Store").should be_false
      config.excluded?(".git/config").should be_false
    end

    it "applies custom glob excludes against the relative path" do
      config = Hwaro::Models::StaticConfig.new
      config.exclude = ["*.bak", "drafts/**"]
      config.excluded?("keep-me.bak").should be_true
      config.excluded?("drafts/wip.txt").should be_true
      config.excluded?("robots.txt").should be_false
    end

    it "matches a bare-name glob like *.bak at any depth" do
      config = Hwaro::Models::StaticConfig.new
      config.exclude = ["*.bak"]
      config.excluded?("nested/deep/secret.bak").should be_true
      config.excluded?("nested/keep.txt").should be_false
    end

    it "scopes a path glob like drafts/** to its subtree" do
      config = Hwaro::Models::StaticConfig.new
      config.exclude = ["drafts/**"]
      config.excluded?("drafts/a/b.txt").should be_true
      config.excluded?("published/note.txt").should be_false
    end

    it "keeps default excludes active alongside custom excludes" do
      config = Hwaro::Models::StaticConfig.new
      config.exclude = ["*.bak"]
      config.excluded?(".DS_Store").should be_true
      config.excluded?("note.bak").should be_true
    end
  end
end

describe "Config: [static] parsing" do
  it "defaults to an enabled denylist with no custom excludes" do
    config = load_config(<<-TOML)
      title = "T"
      base_url = "http://localhost"
      TOML
    config.static.use_default_excludes.should be_true
    config.static.exclude.should eq([] of String)
  end

  it "parses exclude as an array and use_default_excludes as a bool" do
    config = load_config(<<-TOML)
      title = "T"
      base_url = "http://localhost"

      [static]
      use_default_excludes = false
      exclude = ["*.bak", "drafts/**"]
      TOML
    config.static.use_default_excludes.should be_false
    config.static.exclude.should eq(["*.bak", "drafts/**"])
  end

  it "accepts a single string for exclude" do
    config = load_config(<<-TOML)
      title = "T"
      base_url = "http://localhost"

      [static]
      exclude = "*.tmp"
      TOML
    config.static.exclude.should eq(["*.tmp"])
  end
end
