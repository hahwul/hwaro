require "../spec_helper"

# Issue #761: doctor's acceptance oracle for a route with no source file is a
# previous build's `[build] output_dir`. A serve-only workflow never populates
# it (since #758 serve builds into `.hwaro/serve/`), so doctor used to report
# every pipeline-emitted asset missing with no clue why — or validate against
# a tree frozen at a long-past build.
private def doctor_for(dir : String) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    static_dir: File.join(dir, "static"),
  )
end

private def pwa_asset_config(dir : String, output_dir : String? = nil) : Nil
  build = output_dir ? "[build]\noutput_dir = \"#{output_dir}\"\n" : ""
  File.write(File.join(dir, "config.toml"),
    %(title = "T"\nbase_url = "http://x"\n#{build}[pwa]\nenabled = true\nprecache_urls = ["/css/app.css"]\n))
end

describe "doctor build-output oracle" do
  it "explains an absent output tree instead of only reporting the asset missing" do
    Dir.mktmpdir do |dir|
      pwa_asset_config(dir)

      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_true

        advisory = issues.find { |i| i.id == "build-output-unusable" }
        advisory.should_not be_nil
        advisory.try(&.level).should eq(:info)
        advisory.try(&.message.includes?("hwaro build")).should be_true
        advisory.try(&.message.includes?(".hwaro/serve")).should be_true
      end
    end
  end

  # `hwaro serve --output public` still stamps the configured directory. Dev
  # output is not what a build produces, so it is not evidence — the same rule
  # `hwaro deploy` applies.
  it "refuses serve output as evidence and names the marker" do
    Dir.mktmpdir do |dir|
      pwa_asset_config(dir)
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      Hwaro::Utils::DevMarker.write(File.join(dir, "public"))

      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_true
        advisory = issues.find { |i| i.id == "build-output-unusable" }
        advisory.try(&.message.includes?(Hwaro::Utils::DevMarker::FILENAME)).should be_true
      end
    end
  end

  it "stays silent when a real build tree answers the route" do
    Dir.mktmpdir do |dir|
      pwa_asset_config(dir)
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")

      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_false
        issues.any?(&.id.starts_with?("build-output-")).should be_false
      end
    end
  end

  it "says nothing about a missing output tree when no route needed it" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n))

      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.any?(&.id.starts_with?("build-output-")).should be_false
      end
    end
  end

  it "flags a route accepted only from output older than the sources" do
    Dir.mktmpdir do |dir|
      pwa_asset_config(dir)
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      File.write(File.join(dir, "content", "post.md"), "+++\ntitle = \"P\"\n+++\n")
      File.touch(File.join(dir, "public", "css", "app.css"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content", "post.md"), Time.utc(2026, 2, 1))

      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_false
        stale = issues.find { |i| i.id == "build-output-stale" }
        stale.try(&.message.includes?("older than the newest source")).should be_true
      end
    end
  end

  # `[build] output_dir` is followed rather than assumed, and the hint names
  # the directory the site actually configures.
  it "follows a custom output_dir in both the probe and the hint" do
    Dir.mktmpdir do |dir|
      pwa_asset_config(dir, output_dir: "dist")

      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.find { |i| i.id == "build-output-unusable" }.try(&.message.includes?("dist/")).should be_true
      end

      FileUtils.mkdir_p(File.join(dir, "dist", "css"))
      File.write(File.join(dir, "dist", "css", "app.css"), "body{}")
      Dir.cd(dir) do
        issues = doctor_for(dir).run
        issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_false
      end
    end
  end

  # `[doctor] ignore` validates entries against the ids derived from
  # CHECK_GROUPS, so an unregistered advisory could never be silenced.
  it "registers both advisory ids as known doctor rules" do
    Hwaro::Services::Doctor.known_issue_id?("build-output-unusable").should be_true
    Hwaro::Services::Doctor.known_issue_id?("build-output-stale").should be_true
  end
end
