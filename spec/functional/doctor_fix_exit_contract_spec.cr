require "../spec_helper"

# Review finding 9, plus the test gap the reviewer proved: the unit spec only
# exercised the extracted `post_fix_exit_code` through a test-only wrapper, so
# restoring the old `return` inside `run` left it green. `run` calls `exit`,
# which cannot be observed in-process, so these drive the built binary and
# assert on the real exit status and the real stdout document.
private HWARO_BIN = File.expand_path("../../bin/hwaro", __DIR__)

Spec.before_suite do
  unless File.exists?(HWARO_BIN) && File::Info.executable?(HWARO_BIN)
    raise "Binary #{HWARO_BIN} is missing or not executable. Run `shards build` first."
  end
end

private def fix_project(dir : String, *, templates : Bool, title : String = "Site")
  %w[content templates static].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "config.toml"), %(title = "#{title}"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: H\n---\nBody")
  if templates
    File.write(File.join(dir, "templates", "page.html"), "{{ page.title }}")
    File.write(File.join(dir, "templates", "section.html"), "{{ section.title }}")
  end
end

private def doctor_run(dir : String, args : Array(String))
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(HWARO_BIN, args, chdir: dir, output: stdout, error: stderr)
  {status.exit_code, stdout.to_s, stderr.to_s}
end

describe "hwaro doctor --fix exit contract" do
  it "exits non-zero from run when errors remain" do
    Dir.mktmpdir do |dir|
      fix_project(dir, templates: false)
      code, _, err = doctor_run(dir, ["doctor", "--fix"])

      code.should eq(Hwaro::Errors::EXIT_TEMPLATE)
      err.should contain("issue(s) remain")
    end
  end

  it "exits zero from run on a clean site" do
    Dir.mktmpdir do |dir|
      fix_project(dir, templates: true)
      doctor_run(dir, ["doctor", "--full"])[0].should eq(Hwaro::Errors::EXIT_SUCCESS)
    end
  end

  it "honours --strict and --max-warnings through run" do
    Dir.mktmpdir do |dir|
      fix_project(dir, templates: true, title: "Hwaro Site")

      doctor_run(dir, ["doctor", "--fix"])[0].should eq(Hwaro::Errors::EXIT_SUCCESS)
      doctor_run(dir, ["doctor", "--fix", "--strict"])[0].should eq(Hwaro::Errors::EXIT_GENERIC)
      doctor_run(dir, ["doctor", "--fix", "--max-warnings", "0"])[0].should eq(Hwaro::Errors::EXIT_GENERIC)
    end
  end

  describe "--fix --json payload (finding 9)" do
    it "explains a non-zero exit inside the JSON document" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: false)
        code, stdout, _ = doctor_run(dir, ["doctor", "--fix", "--json"])

        code.should eq(Hwaro::Errors::EXIT_TEMPLATE)
        payload = JSON.parse(stdout)
        payload["exit_code"].as_i.should eq(Hwaro::Errors::EXIT_TEMPLATE)
        payload["summary"]["errors"].as_i.should eq(2)
        payload["issues"].as_a.map(&.["id"].as_s).should contain("template-required-missing")
        # Pre-existing fix-mode fields must survive.
        payload["sections_added"].as_a.should be_empty
        payload["value_fixes"].as_a.should be_empty
        payload["dry_run"].as_bool.should be_false
      end
    end

    it "emits exactly one parseable document on a clean site" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: true)
        code, stdout, _ = doctor_run(dir, ["doctor", "--full", "--json"])

        code.should eq(Hwaro::Errors::EXIT_SUCCESS)
        payload = JSON.parse(stdout)
        payload["exit_code"].as_i.should eq(0)
        payload["schema_version"].as_i.should eq(1)
      end
    end

    it "reports the sections it added alongside the diagnosis" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: true)
        _, stdout, _ = doctor_run(dir, ["doctor", "--approve", "--json"])

        payload = JSON.parse(stdout)
        payload["sections_added"].as_a.should_not be_empty
        payload["exit_code"].as_i.should eq(0)
      end
    end
  end
end
