require "../../../spec_helper"

describe "[privacy] config" do
  it "defaults to off with the documented values" do
    privacy = load_config(%(title = "T")).privacy
    privacy.enabled.should be_false
    privacy.include.should be_empty
    privacy.exclude.should be_empty
    privacy.output_dir.should eq("assets/external")
    privacy.cache_ttl.should eq(7.days)
    privacy.on_error.should eq("warn-and-keep")
  end

  it "parses every key" do
    privacy = load_config(<<-TOML).privacy
      [privacy]
      enabled = true
      include = ["Fonts.GoogleAPIs.com", "cdn.jsdelivr.net"]
      exclude = "www.youtube.com"
      output_dir = "/vendor/ext/"
      cache_ttl = "12h"
      on_error = "fail"
      TOML
    privacy.enabled.should be_true
    privacy.include.should eq(["fonts.googleapis.com", "cdn.jsdelivr.net"])
    privacy.exclude.should eq(["www.youtube.com"])
    privacy.output_dir.should eq("vendor/ext")
    privacy.cache_ttl.should eq(12.hours)
    privacy.on_error.should eq("fail")
  end

  it "rejects an unknown on_error and a bad cache_ttl" do
    expect_config_error(%([privacy]\non_error = "ignore")).message.to_s.should contain("unknown on_error")
    expect_config_error(%([privacy]\ncache_ttl = "soon")).message.to_s.should contain("invalid cache_ttl")
  end

  it "warns on unknown keys" do
    log = with_captured_log { load_config(%([privacy]\nenabeld = true)) }
    log.should contain("[privacy]: unknown key 'enabeld'")
  end
end
