require "../../../spec_helper"

# Finding 3 (corrected after review): doctor must agree with what the build
# ACTUALLY loads. `Phases::Initialize` keys a template by
# `Path[path].relative_to("templates").gsub(TEMPLATE_EXTENSION_REGEX, "")`, so:
#
#   templates/page.html        -> "page"          applied
#   templates/page.jinja       -> "page"          applied
#   templates/page.html.jinja  -> "page.html"     NOT applied (built-in default)
#   templates/partials/page.html -> "partials/page"  NOT applied
#
# Verified by putting a marker in each template body and grepping the built
# output. The first version of this fix had the comparison inverted: it
# accepted `page.html.jinja` (which the build ignores) and rejected
# `page.jinja` (which the build honours).
private def doctor_for(dir : String) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    static_dir: File.join(dir, "static"),
  )
end

private def doctor_project(dir : String)
  %w[content templates static].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: H\n---\nBody")
end

describe Hwaro::Services::Doctor do
  describe "template extensions" do
    it "accepts required templates named page.jinja / section.jinja" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "templates", "page.jinja"), "{{ page.title }}")
        File.write(File.join(dir, "templates", "section.jinja"), "{{ section.title }}")

        ids = doctor_for(dir).run.map(&.id)
        ids.should_not contain("template-required-missing")
      end
    end

    it "accepts .j2 and .ecr spellings too" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "templates", "page.j2"), "{{ page.title }}")
        File.write(File.join(dir, "templates", "section.ecr"), "section")

        ids = doctor_for(dir).run.map(&.id)
        ids.should_not contain("template-required-missing")
      end
    end

    it "still reports genuinely missing required templates" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "templates", "index.html"), "home")

        ids = doctor_for(dir).run.map(&.id)
        ids.count("template-required-missing").should eq(2)
      end
    end

    it "syntax-checks non-.html templates" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "templates", "page.jinja"), "{% if x %}never closed")
        File.write(File.join(dir, "templates", "section.jinja"), "{{ section.title }}")

        issues = doctor_for(dir).run
        syntax = issues.select { |i| i.id == "template-syntax-error" }
        syntax.size.should eq(1)
        syntax.first.file.to_s.should contain("page.jinja")
      end
    end

    it "keeps plain .html templates working" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "templates", "page.html"), "{{ page.title }}")
        File.write(File.join(dir, "templates", "section.html"), "{% if x %}never closed")

        issues = doctor_for(dir).run
        issues.map(&.id).should_not contain("template-required-missing")
        issues.count { |i| i.id == "template-syntax-error" }.should eq(1)
      end
    end
  end

  # Finding 11: `[doctor] ignore` deliberately refuses to silence error-level
  # rules, but the docs listed error IDs as ignorable and nothing said why the
  # entry had no effect.
  describe "[doctor] ignore of an error-level rule" do
    it "warns that the entry cannot be silenced and keeps reporting the issue" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "config.toml"), <<-TOML)
          title = "Site"
          base_url = "https://example.com"

          [doctor]
          ignore = ["template-required-missing"]
          TOML

        output = with_captured_log do
          doctor_for(dir).run.map(&.id).should contain("template-required-missing")
        end

        output.should contain("ignore entry 'template-required-missing'")
        output.should contain("cannot be silenced")
      end
    end

    it "stays quiet and still silences a warning-level rule" do
      Dir.mktmpdir do |dir|
        doctor_project(dir)
        File.write(File.join(dir, "templates", "page.html"), "p")
        File.write(File.join(dir, "templates", "section.html"), "s")
        File.write(File.join(dir, "config.toml"), <<-TOML)
          title = "Site"
          base_url = "https://example.com/"

          [doctor]
          ignore = ["base-url-trailing-slash"]
          TOML

        output = with_captured_log do
          doctor_for(dir).run.map(&.id).should_not contain("base-url-trailing-slash")
        end

        output.should_not contain("cannot be silenced")
      end
    end
  end
end
