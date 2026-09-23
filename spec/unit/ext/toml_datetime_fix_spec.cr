require "../../spec_helper"

# ext/toml_datetime_fix.cr — the vendored toml lexer's date/time handling.
describe "TOML datetime lexing (ext/toml_datetime_fix)" do
  # Regression: fractional seconds had to be exactly six digits, so the
  # common millisecond form (`.123`) was a parse error and aborted the build.
  it "accepts fractional seconds of any precision" do
    TOML.parse("a = 2024-03-05T10:20:30.5Z")["a"].raw.as(Time).nanosecond.should eq(500_000_000)
    TOML.parse("a = 2024-03-05T10:20:30.123Z")["a"].raw.as(Time).nanosecond.should eq(123_000_000)
    TOML.parse("a = 2024-03-05T10:20:30.123456Z")["a"].raw.as(Time).nanosecond.should eq(123_456_000)
    TOML.parse("a = 2024-03-05T10:20:30.123456789Z")["a"].raw.as(Time).nanosecond.should eq(123_456_789)
    # Digits past nanoseconds are truncated, as the TOML spec allows.
    TOML.parse("a = 2024-03-05T10:20:30.1234567891Z")["a"].raw.as(Time).nanosecond.should eq(123_456_789)
    TOML.parse("a = 2024-03-05T10:20:30.25")["a"].raw.as(Time).nanosecond.should eq(250_000_000)
  end

  it "still rejects a dot with no fraction digits" do
    expect_raises(TOML::ParseException) { TOML.parse("a = 2024-03-05T10:20:30.Z") }
  end
end
