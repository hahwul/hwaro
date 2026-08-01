require "../spec_helper"

# Review findings 3 and 4. `doctor`'s required-template check must agree with
# the name the build actually loads a template under
# (`Phases::Initialize`: path relative to `templates/`, minus ONE trailing
# template extension). Two ways the first version of the fix disagreed:
#
#   3. It compared the candidate's extension-stripped name against the
#      requirement WITH its extension (`"page.html"`), so only `page.html.jinja`
#      matched — the one naming the build ignores — while `page.jinja`, which
#      the build honours, was reported missing.
#   4. It compared `File.basename`, so `partials/page.html.jinja` satisfied the
#      root requirement and a build-blocking error became invisible.
#
# Both directions are pinned here: a naming the build APPLIES must not be
# reported missing, and a naming the build IGNORES must be.
private def parity_doctor(dir : String) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    static_dir: File.join(dir, "static"),
  )
end

private def parity_project(dir : String)
  %w[content templates static].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: H\n---\nBody")
end

private def required_missing_count(dir : String) : Int32
  parity_doctor(dir).run.count { |i| i.id == "template-required-missing" }
end

describe Hwaro::Services::Doctor do
  describe "required-template naming matches the loader" do
    # The loader name for each of these is "page"/"section", so the build
    # applies them and doctor must stay quiet.
    {"html", "jinja", "j2", "jinja2", "ecr"}.each do |ext|
      it "accepts page.#{ext} / section.#{ext} (loader name \"page\")" do
        Dir.mktmpdir do |dir|
          parity_project(dir)
          File.write(File.join(dir, "templates", "page.#{ext}"), "page")
          File.write(File.join(dir, "templates", "section.#{ext}"), "section")

          required_missing_count(dir).should eq(0)
        end
      end
    end

    # `page.html.jinja` loads as "page.html", NOT "page" — the build falls back
    # to its built-in default and the file is never applied. Verified with a
    # marker in the template body. Doctor must report it missing.
    {"jinja", "j2", "jinja2", "ecr"}.each do |ext|
      it "rejects page.html.#{ext} (loader name \"page.html\", never applied)" do
        Dir.mktmpdir do |dir|
          parity_project(dir)
          File.write(File.join(dir, "templates", "page.html.#{ext}"), "page")
          File.write(File.join(dir, "templates", "section.html.#{ext}"), "section")

          required_missing_count(dir).should eq(2)
        end
      end
    end

    it "rejects templates that only exist in a subdirectory" do
      # `partials/page.html` loads as "partials/page"; it cannot satisfy the
      # root `page` requirement, and the build renders with the default.
      Dir.mktmpdir do |dir|
        parity_project(dir)
        FileUtils.mkdir_p(File.join(dir, "templates", "partials"))
        File.write(File.join(dir, "templates", "partials", "page.html"), "page")
        File.write(File.join(dir, "templates", "partials", "section.html"), "section")

        required_missing_count(dir).should eq(2)
      end
    end

    it "rejects a nested .jinja template for a root requirement" do
      Dir.mktmpdir do |dir|
        parity_project(dir)
        FileUtils.mkdir_p(File.join(dir, "templates", "partials"))
        File.write(File.join(dir, "templates", "partials", "page.html.jinja"), "page")
        File.write(File.join(dir, "templates", "partials", "section.html.jinja"), "section")

        required_missing_count(dir).should eq(2)
      end
    end

    it "accepts a root template alongside unrelated nested ones" do
      Dir.mktmpdir do |dir|
        parity_project(dir)
        FileUtils.mkdir_p(File.join(dir, "templates", "partials"))
        File.write(File.join(dir, "templates", "page.jinja"), "page")
        File.write(File.join(dir, "templates", "section.jinja"), "section")
        File.write(File.join(dir, "templates", "partials", "nav.html"), "nav")

        required_missing_count(dir).should eq(0)
      end
    end
  end
end
