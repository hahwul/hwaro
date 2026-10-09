require "../../spec_helper"

# ext/toml_syntax_fix.cr — `\u` is exactly four hex digits, `\U` exactly eight.
describe "TOML \\u escape lexing (ext/toml_syntax_fix)" do
  it "does not swallow a hex digit that follows \\uXXXX" do
    TOML.parse(%(a = "\\u000Bb"))["a"].as_s.should eq("\u000Bb")
    TOML.parse(%(a = "\\u0041B"))["a"].as_s.should eq("AB")
  end

  it "reads \\UXXXXXXXX as an 8-digit scalar" do
    TOML.parse(%(a = "\\U0001F600x"))["a"].as_s.should eq("\u{1F600}x")
  end

  it "rejects a short escape" do
    expect_raises(TOML::ParseException) { TOML.parse(%(a = "\\u00")) }
  end

  it "round-trips every control char followed by every hex digit" do
    controls = (0x00..0x1F).map(&.chr) + ['\u007F']
    "0123456789abcdefABCDEF".each_char do |hex|
      controls.each do |c|
        value = "t#{c}#{hex}z"
        toml = %(a = "#{Hwaro::Utils::FrontmatterWriter.escape_toml_string(value)}")
        TOML.parse(toml)["a"].as_s.should eq(value)
      end
    end
  end
end

describe "TOML unicode escapes (ext/toml_syntax_fix)" do
  it "reads exactly four digits for \\u" do
    TOML.parse(%(k = "\\u00e9e"))["k"].as_s.should eq("ée")
    TOML.parse(%(k = "\\u0041cafe"))["k"].as_s.should eq("Acafe")
    TOML.parse(%(k = "\\u0041g"))["k"].as_s.should eq("Ag")
    TOML.parse(%(k = "\\u00e9"))["k"].as_s.should eq("é")
  end

  it "reads exactly eight digits for \\U" do
    TOML.parse(%(k = "\\U0001F600"))["k"].as_s.should eq("\u{1F600}")
    TOML.parse(%(k = "\\U0001F600abc"))["k"].as_s.should eq("\u{1F600}abc")
  end

  it "works in multi-line strings too" do
    TOML.parse(%(k = """\\u00e9e\\nx"""))["k"].as_s.should eq("ée\nx")
  end

  it "rejects short, surrogate and out-of-range escapes as TOML errors" do
    expect_raises(TOML::ParseException) { TOML.parse(%(k = "\\u00e")) }
    expect_raises(TOML::ParseException) { TOML.parse(%(k = "\\uD800")) }
    expect_raises(TOML::ParseException) { TOML.parse(%(k = "\\U00110000")) }
    expect_raises(TOML::ParseException) { TOML.parse(%(k = "\\U0001F60")) }
  end

  it "round-trips FrontmatterWriter output with a control char before a hex digit" do
    ["\u00019", "\ebee", "a\u0000f", "\u007Fc", "x\u0001\u0002ab"].each do |s|
      doc = %(k = "#{Hwaro::Utils::FrontmatterWriter.escape_toml_string(s)}")
      TOML.parse(doc)["k"].as_s.should eq(s)
    end
  end
end
