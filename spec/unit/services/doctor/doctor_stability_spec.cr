require "../../../spec_helper"
require "../../../../src/services/doctor"

# Regression specs for doctor stability fixes:
#  - symlink-cycle resilience in the content and template scans
#  - TOML multi-line-string awareness in the line-oriented scanners
#    (`--fix` value fixers + `mentioned_sections`)
#  - unclassified parse errors surfacing as issues instead of being
#    silently dropped by ParallelHelper.map's success-only filter
#  - `--max-warnings` usage-error parity with `hwaro tool validate`

private def new_doctor(dir : String) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
  )
end

private def write_site(dir : String, config : String = %(title = "S"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "config.toml"), config)
  FileUtils.mkdir_p(File.join(dir, "content"))
end

describe Hwaro::Services::Doctor do
  describe "symlink-cycle resilience" do
    # `File.file?` FOLLOWS symlinks, so a self-referential link matching
    # the content glob raised File::Error (ELOOP) out of the whole run —
    # zero diagnostics, and no JSON payload under --json.
    it "survives a symlink cycle matching the content glob" do
      Dir.mktmpdir do |dir|
        write_site(dir)
        File.write(File.join(dir, "content", "ok.md"), "+++\ntitle = \"A\"\n+++\nbody\n")
        File.symlink("loop.md", File.join(dir, "content", "loop.md"))

        issues = new_doctor(dir).run
        # The healthy sibling file must still have been scanned cleanly.
        issues.any? { |i| i.id == "content-frontmatter-invalid" }.should be_false
        issues.any? { |i| i.id == "content-read-error" }.should be_false
      end
    end

    # `File.directory?` in template_files followed symlinks the same way,
    # so one bad link under templates/ killed every check.
    it "survives a symlink cycle under templates/" do
      Dir.mktmpdir do |dir|
        write_site(dir)
        tpl = File.join(dir, "templates")
        FileUtils.mkdir_p(tpl)
        File.write(File.join(tpl, "page.html"), "<html>{{ page.title }}</html>")
        File.write(File.join(tpl, "section.html"), "<html>{{ section.title }}</html>")
        File.symlink("loop.html", File.join(tpl, "loop.html"))

        issues = new_doctor(dir).run
        issues.any? { |i| i.id == "template-required-missing" }.should be_false
        issues.any? { |i| i.id == "template-read-error" }.should be_false
      end
    end
  end

  describe "TOML multi-line string awareness" do
    it "does not edit a base_url-looking line inside a multi-line string but fixes the real one" do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.toml")
        config = <<-TOML
          title = "S"
          notes = """
          base_url = "https://inside.example.com/"
          """
          base_url = "https://example.com/"

          TOML
        File.write(config_path, config)

        doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
        summary = doctor.fix_config
        summary.value_fixes.any? { |f| f.field == "base_url" && f.after == "https://example.com" }.should be_true

        text = File.read(config_path)
        # The string CONTENT is user data and must survive byte-exactly.
        text.should contain(%(base_url = "https://inside.example.com/"))
        text.should contain(%(base_url = "https://example.com"))
        text.should_not contain(%(base_url = "https://example.com/"))
      end
    end

    it "does not clamp a priority-looking line inside a multi-line string after [sitemap]" do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.toml")
        original = <<-TOML
          title = "S"
          base_url = "https://example.com"

          [sitemap]
          changefreq = "weekly"
          note = '''
          priority = 9.5
          '''

          TOML
        File.write(config_path, original)

        doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
        summary = doctor.fix_config
        summary.value_fixes.should be_empty
        File.read(config_path).should eq(original)
      end
    end

    it "still reports a section missing when its header only appears inside a multi-line string" do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.toml")
        config = <<-TOML
          title = "S"
          base_url = "https://example.com"
          notes = """
          [menus]
          """

          TOML
        File.write(config_path, config)

        doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
        doctor.missing_config_sections.should contain("menus")
      end
    end

    it "treats a multi-line string that opens and closes on one line as closed" do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.toml")
        config = <<-TOML
          title = "S"
          note = """[menus] not a header"""
          base_url = "https://example.com/"

          TOML
        File.write(config_path, config)

        doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
        summary = doctor.fix_config
        summary.value_fixes.any? { |f| f.field == "base_url" && f.after == "https://example.com" }.should be_true
        File.read(config_path).should contain(%(note = """[menus] not a header"""))
      end
    end
  end

  describe "unclassified content parse errors" do
    # A file whose parse raises a non-HwaroError (invalid UTF-8 makes the
    # frontmatter regex raise ArgumentError) was silently dropped by
    # ParallelHelper.map's success-only filter — doctor said "no issues"
    # while `hwaro build` fails on the same file.
    it "reports a content file whose parse raises a non-classified error" do
      Dir.mktmpdir do |dir|
        write_site(dir)
        path = File.join(dir, "content", "bad.md")
        File.open(path, "w") do |f|
          f << "+++\ntitle = \""
          f.write(Bytes[0xff, 0xfe, 0xfa])
          f << "\"\n+++\nbody\n"
        end

        issues = new_doctor(dir).run
        issues.any? { |i| i.id == "content-frontmatter-invalid" && i.file == path && i.level == :error }.should be_true
      end
    end
  end
end

describe Hwaro::CLI::Commands::Tool::DoctorCommand do
  # `tool validate` raises HWARO_E_USAGE (exit 2, JSON-aware) for a bad
  # --max-warnings; doctor used Logger.error + exit(1) with no JSON.
  it "raises a classified usage error for a non-numeric --max-warnings" do
    err = expect_raises(Hwaro::HwaroError) do
      Hwaro::CLI::Commands::Tool::DoctorCommand.new.run(["--max-warnings", "abc"])
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
  end

  it "raises a classified usage error for a negative --max-warnings" do
    err = expect_raises(Hwaro::HwaroError) do
      Hwaro::CLI::Commands::Tool::DoctorCommand.new.run(["--max-warnings=-3"])
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
  end
end
