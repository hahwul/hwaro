require "../../spec_helper"

# ext/yaml_local_time_fix.cr — zone-less YAML timestamps.
describe "YAML zone-less timestamps (ext/yaml_local_time_fix)" do
  # Regression: an unquoted YAML date parsed as UTC while the same value in
  # TOML (or quoted) parsed as local time, so in a +09:00 zone a YAML post
  # dated today was a future post and hidden.
  it "reads a zone-less timestamp in the local zone, like TOML" do
    saved = Time::Location.local
    Time::Location.local = Time::Location.load("Asia/Seoul")
    begin
      {"2024-03-05", "2024-03-05T10:20:30", "2024-03-05 10:20:30.5"}.each do |src|
        yaml = YAML.parse("a: #{src}")["a"].as_time
        toml = TOML.parse("a = #{src.sub(' ', 'T')}")["a"].raw.as(Time)
        yaml.should eq(toml)
        yaml.offset.should eq(9 * 3600)
      end
    ensure
      Time::Location.local = saved
    end
  end

  it "keeps a written zone exact" do
    saved = Time::Location.local
    Time::Location.local = Time::Location.load("Asia/Seoul")
    begin
      YAML.parse("a: 2024-03-05T10:20:30Z")["a"].as_time.should eq(Time.utc(2024, 3, 5, 10, 20, 30))
      t = YAML.parse("a: 2024-03-05T10:20:30-05:00")["a"].as_time
      t.offset.should eq(-5 * 3600)
      t.to_utc.should eq(Time.utc(2024, 3, 5, 15, 20, 30))
    ensure
      Time::Location.local = saved
    end
  end
end
