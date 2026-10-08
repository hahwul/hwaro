require "../../spec_helper"

# ext/toml_unicode_escape_fix.cr — `\u` reads exactly four hex digits.
describe "TOML \\u escape lexing (ext/toml_unicode_escape_fix)" do
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
