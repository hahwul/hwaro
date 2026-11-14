require "../../../spec_helper"
require "../../../../src/services/doctor"

private def fix_plugins(config : String, dry_run : Bool = false) : {Hwaro::Services::Doctor::FixSummary, String, String}
  Dir.mktmpdir do |dir|
    path = File.join(dir, "config.toml")
    File.write(path, config)
    doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: path)
    summary = nil
    log = with_captured_log { summary = doctor.fix_config(dry_run: dry_run) }
    {summary.not_nil!, File.read(path), log}
  end
end

# `[plugins]` was removed in 1.0; every config.toml an older `hwaro init`
# wrote still has it.
describe "Doctor#fix_config and the removed [plugins] section" do
  scaffold = "title = \"S\"\nbase_url = \"https://example.com\"\n\n" \
             "# Plugins\n# Configure content processors and extensions\n\n" \
             "[plugins]\nprocessors = [\"markdown\"]\n\n# next\n[sitemap]\nenabled = true\n"

  it "removes the scaffold default, keeping every other line, and a second run is a no-op" do
    summary, text, _ = fix_plugins(scaffold)
    summary.value_fixes.map(&.field).should eq(["plugins"])
    text.should eq(scaffold.sub("[plugins]\nprocessors = [\"markdown\"]\n", ""))

    again, text2, _ = fix_plugins(text)
    again.empty?.should be_true
    text2.should eq(text)
  end

  it "keeps CRLF line endings and removes an empty section" do
    crlf = scaffold.gsub("\n", "\r\n")
    _, text, _ = fix_plugins(crlf)
    text.should eq(crlf.sub("[plugins]\r\nprocessors = [\"markdown\"]\r\n", ""))

    _, text, _ = fix_plugins("title = \"S\"\n[plugins] # old\n\n[sitemap]\nenabled = true")
    text.should eq("title = \"S\"\n\n[sitemap]\nenabled = true\n")
  end

  it "previews the removal under --dry-run without writing" do
    summary, text, _ = fix_plugins(scaffold, dry_run: true)
    summary.value_fixes.map(&.field).should eq(["plugins"])
    text.should eq(scaffold)
  end

  it "leaves a section holding anything else, and says so" do
    {"processors = [\"markdown\", \"x\"]", "processors = [\"markdown\"]\nother = 1", "[plugins.sub]\nk = 1"}.each do |body|
      config = "title = \"S\"\n[plugins]\n#{body}\n[sitemap]\nenabled = true\n"
      summary, text, log = fix_plugins(config)
      summary.value_fixes.map(&.field).should_not contain("plugins")
      text.should eq(config)
      log.should contain("--fix leaves it")
    end
  end
end
