require "../spec_helper"

private def load_config(toml : String) : Hwaro::Models::Config
  Dir.mktmpdir do |dir|
    path = File.join(dir, "config.toml")
    File.write(path, toml)
    return Hwaro::Models::Config.load(path)
  end
  raise "unreachable"
end

describe Hwaro::Models::SassConfig do
  it "defaults to disabled with minify on" do
    config = Hwaro::Models::Config.new
    config.sass.enabled.should be_false
    config.sass.minify.should be_true
  end

  it "parses the [sass] section" do
    config = load_config(<<-TOML)
    title = "T"
    base_url = "https://example.com"

    [sass]
    enabled = true
    minify = false
    TOML
    config.sass.enabled.should be_true
    config.sass.minify.should be_false
  end

  describe "#sass_source?" do
    it "matches lowercase .scss paths only while enabled" do
      config = Hwaro::Models::Config.new
      config.sass_source?("css/style.scss").should be_false

      config.sass.enabled = true
      config.sass_source?("css/style.scss").should be_true
      # Other casings publish verbatim, matching the compiler's glob.
      config.sass_source?("css/STYLE.SCSS").should be_false
      config.sass_source?("css/style.css").should be_false
    end
  end
end
