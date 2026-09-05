require "../../spec_helper"

# Stability audit 2026-08-23 for `FrontmatterWriter.serialize_time` — the
# single source of truth for frontmatter date emission (`tool convert`,
# `tool export`, importers).
#
# (a) A midnight with a NON-local fixed offset collapsed to a bare
#     `YYYY-MM-DD`, silently shifting the instant when reparsed. Only a
#     local-zone midnight (what a parsed TOML/YAML *local date* produces) or
#     a UTC midnight may take the bare-date shortcut — for those the bare
#     date round-trips.
# (b) Fractional seconds were dropped by both the UTC and offset formats.
describe Hwaro::Utils::FrontmatterWriter do
  describe ".serialize_time stability" do
    it "keeps the offset for a fixed-offset midnight instead of collapsing to a bare date" do
      time = Time.local(2026, 5, 20, 0, 0, 0, location: Time::Location.fixed(9 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T00:00:00+09:00")
    end

    it "keeps the offset for a fixed negative-offset midnight" do
      time = Time.local(2026, 5, 20, 0, 0, 0, location: Time::Location.fixed(-5 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T00:00:00-05:00")
    end

    # A local date (`date = 2026-05-20`) parses to midnight in the ambient
    # local zone; the bare date is exact for it and must survive whatever
    # zone the machine runs in.
    it "still collapses a local-zone midnight to a bare date" do
      time = Time.local(2026, 5, 20)
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20")
    end

    it "still collapses a UTC midnight to a bare date" do
      time = Time.utc(2026, 5, 20)
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20")
    end

    it "keeps millisecond fractions in the UTC format" do
      time = Time.utc(2026, 5, 20, 1, 2, 3, nanosecond: 500_000_000)
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T01:02:03.500Z")
    end

    it "keeps sub-millisecond fractions in the UTC format" do
      time = Time.utc(2026, 5, 20, 1, 2, 3, nanosecond: 1)
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T01:02:03.000000001Z")
    end

    it "keeps fractional seconds in the offset format" do
      time = Time.local(2026, 5, 20, 8, 0, 0, nanosecond: 123_456_000, location: Time::Location.fixed(9 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T08:00:00.123456+09:00")
    end

    it "does not shift a fixed-offset sub-second midnight onto the bare-date path" do
      time = Time.local(2026, 5, 20, 0, 0, 0, nanosecond: 250_000_000, location: Time::Location.fixed(9 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T00:00:00.250+09:00")
    end
  end
end
