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

describe "TOML offset date-times (ext/toml_datetime_fix)" do
  # Regression: the offset was converted away to UTC, so TOML front matter
  # printed a different calendar day than the same value written in YAML.
  it "keeps the author's offset, like YAML" do
    t = TOML.parse("a = 2024-03-05T08:20:30+09:00")["a"].raw.as(Time)
    t.offset.should eq(9 * 3600)
    t.day.should eq(5)
    t.hour.should eq(8)
    t.should eq(YAML.parse("a: 2024-03-05T08:20:30+09:00")["a"].raw.as(Time))

    neg = TOML.parse("a = 2024-03-05T08:20:30-05:30")["a"].raw.as(Time)
    neg.offset.should eq(-(5 * 3600 + 30 * 60))
    neg.to_utc.should eq(Time.utc(2024, 3, 5, 13, 50, 30))

    TOML.parse("a = 2024-03-05T08:20:30Z")["a"].raw.as(Time).utc?.should be_true
  end

  # An out-of-range offset reached Time::Location.fixed, whose
  # InvalidTimezoneOffsetError no caller rescues as a parse failure, and
  # `+23:99` was accepted as `+24:39`.
  it "rejects an out-of-range offset as a TOML parse error" do
    {"+25:00", "+99:00", "-24:00", "+23:99", "+05:60"}.each do |off|
      expect_raises(TOML::ParseException) { TOML.parse("a = 2024-03-05T08:20:30#{off}") }
    end
    TOML.parse("a = 2024-03-05T08:20:30+23:59")["a"].raw.as(Time).offset.should eq(23 * 3600 + 59 * 60)
  end
end

describe "TOML local times (ext/toml_datetime_fix)" do
  # Regression: a local time was pinned to the day the build ran, so the
  # value changed daily (and `tool convert` wrote today's date into it).
  it "reads a local time as the time-of-day string it spells" do
    TOML.parse("t = 07:32:00")["t"].raw.should eq("07:32:00")
    TOML.parse("t = 00:32:00.999999")["t"].raw.should eq("00:32:00.999999")
    TOML.parse("t = [07:32:00, 23:59:59.5]")["t"].raw.as(Array).map(&.raw).should eq(["07:32:00", "23:59:59.5"])
  end

  it "still rejects an impossible local time" do
    expect_raises(TOML::ParseException) { TOML.parse("t = 25:00:00") }
  end
end
