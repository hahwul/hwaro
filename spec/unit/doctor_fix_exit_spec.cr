require "../spec_helper"

# Finding 5: `--fix` / `--approve` / `--full` printed their summary and
# returned, so the process always exited 0 — a CI step running
# `hwaro doctor --fix` passed on a site with missing templates or an
# unfixable config error, and no diagnostics were shown at all.
class Hwaro::CLI::Commands::Tool::DoctorCommand
  def post_fix_exit_code_for_test(doctor : Hwaro::Services::Doctor, strict : Bool = false,
                                  max_warnings : Int32 = -1, report : Bool = true) : Int32
    post_fix_exit_code(doctor, strict: strict, max_warnings: max_warnings, report: report)
  end
end

private def fix_doctor_for(dir : String) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    static_dir: File.join(dir, "static"),
  )
end

private def fix_project(dir : String, *, templates : Bool)
  %w[content templates static].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: H\n---\nBody")
  if templates
    File.write(File.join(dir, "templates", "page.html"), "{{ page.title }}")
    File.write(File.join(dir, "templates", "section.html"), "{{ section.title }}")
  end
end

describe Hwaro::CLI::Commands::Tool::DoctorCommand do
  describe "#post_fix_exit_code" do
    it "returns a failing exit code when errors remain after a fix run" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: false)

        cmd = Hwaro::CLI::Commands::Tool::DoctorCommand.new
        code = cmd.post_fix_exit_code_for_test(fix_doctor_for(dir), report: false)

        code.should eq(Hwaro::Errors::EXIT_TEMPLATE)
      end
    end

    it "returns success when nothing is left broken" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: true)

        cmd = Hwaro::CLI::Commands::Tool::DoctorCommand.new
        cmd.post_fix_exit_code_for_test(fix_doctor_for(dir), report: false)
          .should eq(Hwaro::Errors::EXIT_SUCCESS)
      end
    end

    it "honours --strict on leftover warnings" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: true)
        # `title-default` is a warning that --fix cannot repair.
        File.write(File.join(dir, "config.toml"), %(title = "Hwaro Site"\nbase_url = "https://example.com"\n))

        cmd = Hwaro::CLI::Commands::Tool::DoctorCommand.new
        warnings = fix_doctor_for(dir).run.count { |i| i.level == :warning }
        warnings.should be > 0

        cmd.post_fix_exit_code_for_test(fix_doctor_for(dir), strict: true, report: false)
          .should eq(Hwaro::Errors::EXIT_GENERIC)
      end
    end

    it "honours --max-warnings on leftover warnings" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: true)
        File.write(File.join(dir, "config.toml"), %(title = "Hwaro Site"\nbase_url = "https://example.com"\n))

        cmd = Hwaro::CLI::Commands::Tool::DoctorCommand.new
        cmd.post_fix_exit_code_for_test(fix_doctor_for(dir), max_warnings: 0, report: false)
          .should eq(Hwaro::Errors::EXIT_GENERIC)
      end
    end

    it "points at the plain report when issues remain" do
      Dir.mktmpdir do |dir|
        fix_project(dir, templates: false)

        cmd = Hwaro::CLI::Commands::Tool::DoctorCommand.new
        output = with_captured_log do
          cmd.post_fix_exit_code_for_test(fix_doctor_for(dir))
        end

        output.should contain("issue(s) remain")
      end
    end
  end
end
