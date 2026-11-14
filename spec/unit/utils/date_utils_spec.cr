require "../../spec_helper"

describe Hwaro::Utils::DateUtils do
  describe ".parse_content_date" do
    # +05:30 so the result differs from the local reading in every zone but
    # the one 5.5 hours off UTC the machine happens to be in.
    instant = Time.utc(2024, 1, 15, 4, 30, 0)

    # Time.parse ignores trailing input, so a zone-less pattern used to match
    # these and silently drop the offset: the instant shifted by the build
    # machine's zone (15:00 UTC under America/New_York).
    it "honours a UTC offset written in a quoted date string" do
      [
        "2024-01-15 10:00:00 +0530",
        "2024-01-15 10:00:00 +05:30",
        "2024-01-15T10:00:00+0530",
        "2024-01-15T10:00:00+05:30",
      ].each do |str|
        parsed = Hwaro::Utils::DateUtils.parse_content_date(str)
        parsed.should_not be_nil
        parsed.not_nil!.to_utc.should eq(instant)
      end
    end

    it "honours a negative offset and a written UTC marker" do
      Hwaro::Utils::DateUtils.parse_content_date("2024-01-15 10:00:00 -0830").not_nil!.to_utc.should eq(Time.utc(2024, 1, 15, 18, 30, 0))
      Hwaro::Utils::DateUtils.parse_content_date("2024-01-15 10:00:00 Z").not_nil!.to_utc.should eq(Time.utc(2024, 1, 15, 10, 0, 0))
    end

    it "keeps reading zone-less values in the local zone" do
      Hwaro::Utils::DateUtils.parse_content_date("2024-01-15 10:00:00").should eq(Time.local(2024, 1, 15, 10, 0, 0))
      Hwaro::Utils::DateUtils.parse_content_date("2024-01-15T10:00:00").should eq(Time.local(2024, 1, 15, 10, 0, 0))
      Hwaro::Utils::DateUtils.parse_content_date("2024-01-15").should eq(Time.local(2024, 1, 15))
    end

    # `Time.parse` ignores trailing input, so an offset written in a form the
    # table did not list (`+05`, after a fraction, after `T … `) was dropped
    # and the value read as local time: a different instant on every machine.
    it "honours every written offset form, never reading it as local time" do
      {
        "2024-01-15T10:00:00+05"           => Time.utc(2024, 1, 15, 5, 0, 0),
        "2024-01-15 10:00:00 +05"          => Time.utc(2024, 1, 15, 5, 0, 0),
        "2024-01-15T10:00:00 +05:00"       => Time.utc(2024, 1, 15, 5, 0, 0),
        "2024-01-15 10:00:00.5 -03:00"     => Time.utc(2024, 1, 15, 13, 0, 0, nanosecond: 500_000_000),
        "2024-01-15t10:00:00z"             => Time.utc(2024, 1, 15, 10, 0, 0),
        "2024-01-15T10:00:00.123456789+05" => Time.utc(2024, 1, 15, 5, 0, 0, nanosecond: 123_456_789),
      }.each do |str, expected|
        parsed = Hwaro::Utils::DateUtils.parse_content_date(str)
        parsed.should_not be_nil
        parsed.not_nil!.to_utc.should eq(expected)
      end
    end

    it "rejects trailing text, offsets past 23:59 and short years instead of guessing" do
      [
        "2024-01-15T10:00:00Zjunk",
        "2024-01-15T10:00:00+09:00 junk",
        "2024-01-15T10:00:00+24:00",
        "2024-01-15T10:00:00+05:60",
        "24-01-05",
      ].each { |str| Hwaro::Utils::DateUtils.parse_content_date(str).should be_nil }
    end

    it "still returns nil for an unusable date" do
      Hwaro::Utils::DateUtils.parse_content_date("2024-13-45 10:00:00 +0900").should be_nil
      Hwaro::Utils::DateUtils.parse_content_date("not a date").should be_nil
    end
  end
end
