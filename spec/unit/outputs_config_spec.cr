require "../spec_helper"

# Helper to load a Config from a TOML string via a temp file.
private def load_config(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-outputs-config", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe Hwaro::Models::OutputsConfig do
  describe "#initialize" do
    it "defaults every format list to empty" do
      config = Hwaro::Models::OutputsConfig.new
      config.page.should eq([] of String)
      config.section.should eq([] of String)
      config.sections.should eq([] of String)
    end
  end

  describe "#any?" do
    it "is false when page and section are both empty" do
      config = Hwaro::Models::OutputsConfig.new
      config.any?.should be_false
    end

    it "is true when page has a format" do
      config = Hwaro::Models::OutputsConfig.new
      config.page = ["json"]
      config.any?.should be_true
    end

    it "is true when section has a format" do
      config = Hwaro::Models::OutputsConfig.new
      config.section = ["json"]
      config.any?.should be_true
    end
  end

  describe "VALID_FORMATS" do
    it "lists exactly json/txt/xml/csv" do
      Hwaro::Models::OutputsConfig::VALID_FORMATS.should eq(%w[json txt xml csv])
    end
  end
end

describe "Hwaro::Models::Config [outputs] loading" do
  it "defaults to no configured outputs" do
    config = load_config(%(title = "Site"))
    config.outputs.page.should eq([] of String)
    config.outputs.section.should eq([] of String)
    config.outputs.sections.should eq([] of String)
    config.outputs.any?.should be_false
  end

  it "parses page and section format lists" do
    config = load_config(<<-TOML)
      [outputs]
      page = ["json"]
      section = ["json", "xml"]
      TOML
    config.outputs.page.should eq(["json"])
    config.outputs.section.should eq(["json", "xml"])
    config.outputs.any?.should be_true
  end

  it "parses the sections allowlist" do
    config = load_config(<<-TOML)
      [outputs]
      section = ["json"]
      sections = ["posts", "news"]
      TOML
    config.outputs.sections.should eq(["posts", "news"])
  end

  it "raises HwaroError(HWARO_E_CONFIG) for an unknown page format" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, <<-TOML)
        [outputs]
        page = ["yaml"]
        TOML
      err = expect_raises(Hwaro::HwaroError) do
        Hwaro::Models::Config.load(path)
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      err.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
      (err.message || "").should contain("yaml")
    end
  end

  it "raises HwaroError(HWARO_E_CONFIG) for an unknown section format" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, <<-TOML)
        [outputs]
        section = ["json", "bogus"]
        TOML
      err = expect_raises(Hwaro::HwaroError) do
        Hwaro::Models::Config.load(path)
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("bogus")
    end
  end

  it "accepts every valid format" do
    config = load_config(<<-TOML)
      [outputs]
      page = ["json", "txt", "xml", "csv"]
      TOML
    config.outputs.page.should eq(["json", "txt", "xml", "csv"])
  end
end
