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

    it "still returns nil for an unusable date" do
      Hwaro::Utils::DateUtils.parse_content_date("2024-13-45 10:00:00 +0900").should be_nil
      Hwaro::Utils::DateUtils.parse_content_date("not a date").should be_nil
    end
  end
end
