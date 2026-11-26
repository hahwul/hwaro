require "../../spec_helper"

# ext/toml_nul_byte_fix.cr — a raw NUL byte used to read as end of input, so
# the parser silently dropped everything after it.
describe "TOML NUL bytes (ext/toml_nul_byte_fix)" do
  it "rejects a NUL in a comment instead of truncating the table" do
    err = expect_raises(TOML::ParseException) { TOML.parse("a = 1\n# note\0\nb = 2\n") }
    err.message.to_s.should contain("NUL")
  end

  it "rejects a NUL between lines, as the first byte, and after a value" do
    expect_raises(TOML::ParseException) { TOML.parse("a = 1\n\0\nb = 2\n") }
    expect_raises(TOML::ParseException) { TOML.parse("\0a = 1\n") }
    expect_raises(TOML::ParseException) { TOML.parse("a = 1\0") }
    expect_raises(TOML::ParseException) { TOML.parse("a = 1\nb = 2024-05-01\0") }
  end

  it "rejects a NUL inside strings" do
    expect_raises(TOML::ParseException) { TOML.parse("a = \"x\0y\"\n") }
    expect_raises(TOML::ParseException) { TOML.parse("a = 'x\0y'\n") }
  end

  it "still parses the \\u0000 escape and ordinary input" do
    TOML.parse(%(a = "x\\u0000y"))["a"].as_s.should eq("x\0y")
    TOML.parse("a = 1\n# note\nb = 2\n").keys.should eq(["a", "b"])
    TOML.parse("").should be_empty
  end

  it "does not publish a draft whose draft flag follows a NUL in front matter" do
    raw = "+++\ntitle = \"Secret\"\n# note\0\ndraft = true\n+++\nbody\n"
    expect_raises(Hwaro::HwaroError) do
      Hwaro::Content::Processors::Markdown.new.parse(raw, "content/secret.md")
    end
  end

  it "fails config.toml loading instead of ignoring the settings after the NUL" do
    err = expect_config_error("title = \"Before\"\n\0\nbase_url = \"https://example.com\"\n")
    err.message.to_s.should contain("NUL")
  end
end
