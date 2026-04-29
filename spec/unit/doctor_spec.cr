require "../spec_helper"
require "../../src/services/doctor"

private def run_doctor(config_content : String, content_files = {} of String => String) : Array(Hwaro::Services::Issue)
  Dir.mktmpdir do |dir|
    config_path = File.join(dir, "config.toml")
    File.write(config_path, config_content)
    content_dir = File.join(dir, "content")
    unless content_files.empty?
      FileUtils.mkdir_p(content_dir)
      content_files.each { |name, body| File.write(File.join(content_dir, name), body) }
    end
    doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path)
    doctor.run
  end
end

private def run_doctor_no_config(content_dir : String? = nil) : Array(Hwaro::Services::Issue)
  Dir.mktmpdir do |dir|
    doctor = Hwaro::Services::Doctor.new(
      content_dir: content_dir || File.join(dir, "content"),
      config_path: File.join(dir, "config.toml")
    )
    doctor.run
  end
end

private def base_config(extra = "")
  %(title = "My Site"\nbase_url = "https://example.com"\n#{extra})
end

describe Hwaro::Services::Doctor do
  describe "#run" do
    describe "config diagnostics" do
      it "reports missing config file as an error (build-blocking)" do
        issues = run_doctor_no_config
        issues.any? do |i|
          i.category == "config" &&
            i.message.includes?("not found") &&
            i.level == :error
        end.should be_true
      end

      it "warns when base_url is empty" do
        issues = run_doctor(%(title = "My Site"\n))
        issues.any?(&.message.includes?("base_url")).should be_true
      end

      it "warns when title is default" do
        issues = run_doctor(%(title = "Hwaro Site"\nbase_url = "https://example.com"\n))
        issues.any?(&.message.includes?("default value")).should be_true
      end

      it "does not warn when title is custom" do
        issues = run_doctor(base_config)
        issues.any?(&.message.includes?("default value")).should be_false
      end

      it "does not warn when feeds enabled with empty filename (uses runtime default)" do
        issues = run_doctor(base_config("\n[feeds]\nenabled = true\nfilename = \"\"\n"))
        issues.any?(&.message.includes?("feeds.filename")).should be_false
      end

      it "does not warn when feeds disabled" do
        issues = run_doctor(base_config("\n[feeds]\nenabled = false\n"))
        issues.any?(&.message.includes?("feeds.filename")).should be_false
      end

      it "warns on invalid sitemap changefreq" do
        issues = run_doctor(base_config("\n[sitemap]\nchangefreq = \"biweekly\"\n"))
        issues.any? { |i| i.message.includes?("changefreq") && i.message.includes?("biweekly") }.should be_true
      end

      it "does not warn on valid sitemap changefreq" do
        issues = run_doctor(base_config("\n[sitemap]\nchangefreq = \"daily\"\n"))
        issues.any?(&.message.includes?("changefreq")).should be_false
      end

      it "warns on sitemap priority out of range" do
        issues = run_doctor(base_config("\n[sitemap]\npriority = 1.5\n"))
        issues.any? { |i| i.message.includes?("priority") && i.message.includes?("out of range") }.should be_true
      end

      it "warns on duplicate taxonomy names" do
        issues = run_doctor(base_config("\n[[taxonomies]]\nname = \"tags\"\n\n[[taxonomies]]\nname = \"tags\"\n"))
        issues.any?(&.message.includes?("Duplicate taxonomy")).should be_true
      end

      it "does not warn on unique taxonomy names" do
        issues = run_doctor(base_config("\n[[taxonomies]]\nname = \"tags\"\n\n[[taxonomies]]\nname = \"categories\"\n"))
        issues.any?(&.message.includes?("Duplicate taxonomy")).should be_false
      end

      it "warns on invalid search format when search enabled" do
        issues = run_doctor(base_config("\n[search]\nenabled = true\nformat = \"invalid_format\"\n"))
        issues.any?(&.message.includes?("search.format")).should be_true
      end

      it "does not warn on valid search format" do
        issues = run_doctor(base_config("\n[search]\nenabled = true\nformat = \"fuse_json\"\n"))
        issues.any?(&.message.includes?("search.format")).should be_false
      end

      it "reports error on invalid config TOML" do
        issues = run_doctor("invalid = [toml\n")
        issues.any? { |i| i.level == :error && i.message.includes?("parse") }.should be_true
      end
    end

    describe "config — base_url format" do
      # Scheme/host validity is enforced at `Config.load`, so bad URLs
      # surface as a `config-parse-error` rather than a style advisory
      # here. The doctor retains advisory checks for empty and
      # trailing-slash variants only.

      it "reports the load-time base_url error when scheme is missing" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "example.com"\n))
        issues.any? { |i| i.id == "config-parse-error" && (i.message || "").includes?("Invalid base_url") }.should be_true
      end

      it "warns when base_url has trailing slash" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com/"\n))
        issues.any?(&.message.includes?("trailing slash")).should be_true
      end

      it "does not warn on proper base_url" do
        issues = run_doctor(base_config)
        issues.any?(&.message.includes?("trailing slash")).should be_false
        issues.any?(&.message.includes?("Invalid base_url")).should be_false
      end
    end

    describe "template diagnostics" do
      it "reports missing templates directory as an error (build-blocking)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? do |i|
            i.category == "template" && i.message.includes?("not found") && i.level == :error
          end.should be_true
        end
      end

      it "reports missing required template files as errors (build-blocking)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir)
          # Only create page.html, not section.html
          File.write(File.join(templates_dir, "page.html"), "<html>{{ content }}</html>")

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: templates_dir)
          issues = doctor.run
          tpl_issues = issues.select { |i| i.category == "template" }
          tpl_issues.any? { |i| i.message.includes?("section.html") && i.level == :error }.should be_true
          tpl_issues.any?(&.message.includes?("page.html")).should be_false
        end
      end

      it "reports unclosed template block tags as errors (build-blocking)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir)
          File.write(File.join(templates_dir, "page.html"), "{% if true %}hello")
          File.write(File.join(templates_dir, "section.html"), "<html></html>")

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: templates_dir)
          issues = doctor.run
          issues.any? do |i|
            i.message.includes?("unclosed template block") && i.level == :error
          end.should be_true
        end
      end

      it "no template warnings when all valid" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir)
          File.write(File.join(templates_dir, "page.html"), "{% if true %}hello{% endif %}")
          File.write(File.join(templates_dir, "section.html"), "{{ content }}")

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: templates_dir)
          issues = doctor.run
          tpl_issues = issues.select { |i| i.category == "template" }
          tpl_issues.should be_empty
        end
      end
    end

    describe "missing config sections" do
      it "reports missing config sections" do
        # Minimal config with no sections
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.should_not be_empty

        # Should mention pwa, amp among others
        messages = missing_issues.map(&.message)
        messages.any?(&.includes?("[pwa]")).should be_true
        messages.any?(&.includes?("[amp]")).should be_true
      end

      it "reports og.auto_image when [og] exists but sub-section is missing" do
        config = <<-TOML
          title = "My Site"
          base_url = "https://example.com"
          [og]
          default_image = "/img.png"
          TOML
        issues = run_doctor(config)
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.any?(&.message.includes?("[og.auto_image]")).should be_true
      end

      it "does not report og.auto_image when [og] itself is missing" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.none?(&.message.includes?("[og.auto_image]")).should be_true
      end

      it "does not report sections that exist" do
        config = <<-TOML
          title = "My Site"
          base_url = "https://example.com"
          [pwa]
          enabled = false
          [amp]
          enabled = false
          TOML
        issues = run_doctor(config)
        missing_issues = issues.select { |i| i.category == "config_missing" }

        missing_issues.none?(&.message.includes?("[pwa]")).should be_true
        missing_issues.none?(&.message.includes?("[amp]")).should be_true
      end

      it "does not report commented-out sections as missing" do
        config = <<-TOML
          title = "My Site"
          base_url = "https://example.com"
          # [pwa]
          # enabled = true
          # [amp]
          # enabled = true
          TOML
        issues = run_doctor(config)
        missing_issues = issues.select { |i| i.category == "config_missing" }

        missing_issues.none?(&.message.includes?("[pwa]")).should be_true
        missing_issues.none?(&.message.includes?("[amp]")).should be_true
      end

      it "does not report commented-out sub-sections as missing" do
        config = <<-TOML
          title = "My Site"
          base_url = "https://example.com"
          [og]
          default_image = "/img.png"
          # [og.auto_image]
          # enabled = true
          TOML
        issues = run_doctor(config)
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.none?(&.message.includes?("[og.auto_image]")).should be_true
      end

      it "does not report og.auto_image when it exists" do
        config = <<-TOML
          title = "My Site"
          base_url = "https://example.com"
          [og]
          default_image = "/img.png"
          [og.auto_image]
          enabled = false
          TOML
        issues = run_doctor(config)
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.none?(&.message.includes?("[og.auto_image]")).should be_true
      end

      it "suggests --fix in issue messages" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.all?(&.message.includes?("--fix")).should be_true
      end
    end

    describe "#fix_config" do
      it "appends missing sections to config.toml" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config

          added.should_not be_empty
          added.should contain("pwa")
          added.should contain("amp")

          content = File.read(config_path)
          content.should contain("[pwa]")
          content.should contain("[amp]")
        end
      end

      it "appends og.auto_image when [og] exists but sub-section missing" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n[og]\ndefault_image = "/img.png"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config

          added.should contain("og.auto_image")

          content = File.read(config_path)
          content.should contain("[og.auto_image]")
        end
      end

      it "does not duplicate existing sections" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n[pwa]\nenabled = false\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config

          added.should_not contain("pwa")
        end
      end

      it "skips optional sections with minimal flag" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config(minimal: true)

          # Should add common sections (search, pagination, etc.)
          added.should contain("search")
          added.should contain("pagination")

          # Should skip advanced optional sections
          added.should_not contain("pwa")
          added.should_not contain("amp")
          added.should_not contain("assets")
          added.should_not contain("deployment")
          added.should_not contain("image_processing")
        end
      end

      it "adds all sections without minimal flag" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config(minimal: false)

          added.should contain("pwa")
          added.should contain("amp")
          added.should contain("assets")
          added.should contain("deployment")
        end
      end

      it "raises HwaroError(HWARO_E_CONFIG) when config.toml is missing" do
        Dir.mktmpdir do |dir|
          # No config.toml at all.
          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: File.join(dir, "config.toml"))
          err = expect_raises(Hwaro::HwaroError) { doctor.fix_config }
          err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          (err.message || "").should contain("not found")
        end
      end

      it "raises HwaroError(HWARO_E_CONFIG) when config.toml has TOML parse errors" do
        # Refuses to --fix a broken config rather than silently saying
        # "up to date" (the old behaviour from the bare-rescue return).
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "Ok"\nbroken = = \n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          err = expect_raises(Hwaro::HwaroError) { doctor.fix_config }
          err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          (err.message || "").downcase.should contain("parse error")
          (err.hint || "").should contain("'hwaro doctor'")

          # And the broken input is NOT modified — no half-append.
          File.read(config_path).should eq(%(title = "Ok"\nbroken = = \n))
        end
      end

      it "writes atomically via a temp file so a concurrent reader never sees a partial config" do
        # End-to-end sanity for the temp-file + rename approach: the
        # temp file lives at `<config>.hwaro-tmp` during the write and
        # is renamed into place in one step, so there is no leftover
        # temp file after a successful fix.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config
          added.should_not be_empty

          File.exists?("#{config_path}.hwaro-tmp").should be_false
          # Config now contains the original pre-existing content plus
          # at least one appended section, end-to-end.
          text = File.read(config_path)
          text.should contain(%(title = "My Site"))
          text.should contain("[pwa]")
        end
      end

      it "returns empty when nothing is missing" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          # Synthesize a config that lists every known top-level section
          # and each known sub-section exactly once, in an order that's
          # valid TOML (sub-sections right after their parents). Previous
          # versions of this spec duplicated `[og]` which happened to
          # parse under a bare `rescue` that swallowed errors — now
          # `fix_config` surfaces parse errors as HwaroError.
          sub_children_by_parent = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
          Hwaro::Services::Doctor::KNOWN_SUB_SECTIONS.each_key do |parent, child|
            sub_children_by_parent[parent] << child
          end

          body = String.build do |str|
            str << %(title = "My Site"\n)
            str << %(base_url = "https://example.com"\n)
            Hwaro::Services::Doctor::KNOWN_CONFIG_SECTIONS.each_key do |key|
              str << "[#{key}]\n"
              sub_children_by_parent[key]?.try &.each do |child|
                str << "[#{key}.#{child}]\n"
              end
            end
          end
          File.write(config_path, body)

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config
          added.should be_empty
        end
      end
    end

    describe "ignore rules" do
      it "suppresses issues matching ignore list" do
        config = %(title = "Hwaro Site"\nbase_url = "https://example.com"\n[doctor]\nignore = ["title-default"]\n)
        issues = run_doctor(config)
        issues.any? { |i| i.id == "title-default" }.should be_false
      end

      it "does not suppress issues not in ignore list" do
        config = %(title = "Hwaro Site"\nbase_url = "https://example.com"\n[doctor]\nignore = ["base-url-missing"]\n)
        issues = run_doctor(config)
        issues.any? { |i| i.id == "title-default" }.should be_true
      end

      it "works with empty ignore list" do
        config = %(title = "Hwaro Site"\nbase_url = "https://example.com"\n[doctor]\nignore = []\n)
        issues = run_doctor(config)
        issues.any? { |i| i.id == "title-default" }.should be_true
      end

      it "suppresses issues by id" do
        config = base_config("\n[doctor]\nignore = [\"title-default\"]\n")
        issues = run_doctor(config)
        issues.any? { |i| i.id == "title-default" }.should be_false
      end

      it "refuses to suppress :error-level issues even if listed" do
        # template-required-missing is :error and would fail `hwaro build`;
        # adding it to the ignore list must NOT make it disappear from doctor.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config("\n[doctor]\nignore = [\"template-required-missing\"]\n"))
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir) # exists but empty
          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: templates_dir,
          )
          issues = doctor.run
          issues.any? { |i| i.id == "template-required-missing" && i.level == :error }.should be_true
        end
      end
    end

    describe "directory structure" do
      it "reports info when section dir missing _index.md" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "blog"))
          File.write(File.join(content_dir, "blog", "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? { |i| i.category == "structure" && i.message.includes?("_index.md") }.should be_true
        end
      end

      it "no structure warning when _index.md exists" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "blog"))
          File.write(File.join(content_dir, "blog", "_index.md"), "+++\ntitle = \"Blog\"\n+++\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? { |i| i.category == "structure" && i.message.includes?("_index.md") }.should be_false
        end
      end
    end

    describe "content front matter diagnostics" do
      # Scans each `.md` / `.markdown` file with the same parser the
      # builder uses so doctor catches `HWARO_E_CONTENT`-class issues
      # before `hwaro build` runs.

      it "reports malformed TOML front matter as a content error" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(content_dir)
          File.write(File.join(content_dir, "bad.md"), "+++\ntitle = \"Unclosed\n+++\nbody\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          matching = issues.select do |i|
            i.category == "content" &&
              i.id == "content-frontmatter-invalid" &&
              i.level == :error
          end
          matching.should_not be_empty
          (matching.first.file || "").should contain("bad.md")
        end
      end

      it "reports malformed YAML front matter as a content error" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(content_dir)
          File.write(File.join(content_dir, "bad-yaml.md"), "---\ntitle: \"Unclosed\n---\nbody\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? do |i|
            i.category == "content" && i.level == :error && (i.file || "").includes?("bad-yaml.md")
          end.should be_true
        end
      end

      it "does not report anything for a clean scaffold" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(content_dir)
          File.write(File.join(content_dir, "index.md"), "+++\ntitle = \"Home\"\n+++\nbody\n")
          File.write(File.join(content_dir, "about.md"), "---\ntitle: About\n---\nbody\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? { |i| i.category == "content" }.should be_false
        end
      end

      it "warns when [og] default_image path does not exist under static/" do
        # Regression for https://github.com/hahwul/hwaro/issues/489
        # The path-shaped fields in `config.toml` (`[og] default_image`,
        # `[og.auto_image] logo`, `[pwa] icons`, `[pwa] offline_page`)
        # used to slip past doctor unchecked. A typoed image path would
        # only surface when the build emitted a 404 in production.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[og]\ndefault_image = "/images/og-default.png"\n))
          # No `static/images/og-default.png` exists.
          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: File.join(dir, "static"),
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? do |i|
              i.id == "config-path-missing" &&
                i.message.includes?("default_image") &&
                i.message.includes?("/images/og-default.png")
            end.should be_true
          end
        end
      end

      it "does not warn when [og] default_image points to a real file" do
        Dir.mktmpdir do |dir|
          static_dir = File.join(dir, "static")
          FileUtils.mkdir_p(File.join(static_dir, "images"))
          File.write(File.join(static_dir, "images", "og.png"), "fake png")

          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[og]\ndefault_image = "/images/og.png"\n))

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: static_dir,
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? { |i| i.id == "config-path-missing" }.should be_false
          end
        end
      end

      it "warns for missing [pwa] icons paths" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, <<-TOML)
            title = "T"
            base_url = "http://x"
            [pwa]
            enabled = true
            icons = ["static/icon-192.png", "static/icon-512.png"]
            TOML

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: File.join(dir, "static"),
          )
          Dir.cd(dir) do
            issues = doctor.run
            missing = issues.select { |i| i.id == "config-path-missing" && i.message.includes?("[pwa] icons") }
            missing.size.should eq(2)
          end
        end
      end

      it "strips query string and fragment before resolving referenced paths" do
        # `/images/og.png?v=2` should resolve to /images/og.png on disk.
        # Without stripping, doctor would emit a spurious config-path-missing.
        Dir.mktmpdir do |dir|
          static_dir = File.join(dir, "static")
          FileUtils.mkdir_p(File.join(static_dir, "images"))
          File.write(File.join(static_dir, "images", "og.png"), "fake png")

          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[og]\ndefault_image = "/images/og.png?v=2"\n))

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: static_dir,
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? { |i| i.id == "config-path-missing" }.should be_false
          end
        end
      end

      it "warns for missing [auto_includes] dirs (when enabled)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, <<-TOML)
            title = "T"
            base_url = "http://x"
            [auto_includes]
            enabled = true
            dirs = ["assets/css", "assets/js"]
            TOML

          static_dir = File.join(dir, "static")
          FileUtils.mkdir_p(File.join(static_dir, "assets", "css")) # only css exists

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: static_dir,
          )
          Dir.cd(dir) do
            issues = doctor.run
            missing = issues.select { |i| i.id == "config-dir-missing" && i.message.includes?("auto_includes") }
            missing.size.should eq(1)
            missing.first.message.should contain("assets/js")
          end
        end
      end

      it "does not check [auto_includes] when disabled" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, <<-TOML)
            title = "T"
            base_url = "http://x"
            [auto_includes]
            enabled = false
            dirs = ["does/not/exist"]
            TOML

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: File.join(dir, "static"),
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? { |i| i.id == "config-dir-missing" }.should be_false
          end
        end
      end

      it "warns for missing [[assets.bundles]] files relative to assets.source_dir" do
        Dir.mktmpdir do |dir|
          static_dir = File.join(dir, "static")
          FileUtils.mkdir_p(File.join(static_dir, "css"))
          File.write(File.join(static_dir, "css", "reset.css"), "")
          # css/style.css missing on purpose

          config_path = File.join(dir, "config.toml")
          File.write(config_path, <<-TOML)
            title = "T"
            base_url = "http://x"
            [assets]
            enabled = true
            source_dir = "static"
            [[assets.bundles]]
            name = "main.css"
            files = ["css/reset.css", "css/style.css"]
            TOML

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: static_dir,
          )
          Dir.cd(dir) do
            issues = doctor.run
            missing = issues.select { |i| i.id == "config-path-missing" && i.message.includes?("assets.bundles") }
            missing.size.should eq(1)
            missing.first.message.should contain("css/style.css")
          end
        end
      end

      it "skips silently when the content directory doesn't exist" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          # No content dir at all.
          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? { |i| i.category == "content" }.should be_false
        end
      end

      it "also scans nested directories and .markdown extension" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "posts", "deep"))
          File.write(File.join(content_dir, "posts", "deep", "bad.markdown"), "+++\ntitle = \"Broken\n+++\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? do |i|
            i.category == "content" && (i.file || "").ends_with?("bad.markdown")
          end.should be_true
        end
      end
    end
  end

  describe "ConfigSnippets drift guard" do
    it "doctor_snippet_for returns non-nil for every KNOWN_SECTIONS key" do
      Hwaro::Services::ConfigSnippets::KNOWN_SECTIONS.each_key do |key|
        Hwaro::Services::ConfigSnippets.doctor_snippet_for(key).should_not be_nil,
          "ConfigSnippets.doctor_snippet_for(#{key.inspect}) returned nil — add a case branch"
      end
    end

    it "doctor_snippet_for returns non-nil for every KNOWN_SUB_SECTIONS key" do
      Hwaro::Services::ConfigSnippets::KNOWN_SUB_SECTIONS.each_key do |parent, child|
        key = "#{parent}.#{child}"
        Hwaro::Services::ConfigSnippets.doctor_snippet_for(key).should_not be_nil,
          "ConfigSnippets.doctor_snippet_for(#{key.inspect}) returned nil — add a case branch"
      end
    end
  end

  describe "Issue JSON serialization" do
    it "serializes level (Symbol) as a plain string in JSON" do
      issue = Hwaro::Services::Issue.new(
        id: "test-rule",
        level: :warning,
        category: "config",
        file: "config.toml",
        message: "something",
      )
      json = issue.to_json
      json.should contain(%("level":"warning"))
      json.should contain(%("id":"test-rule"))
      json.should contain(%("category":"config"))
    end

    it "omits file from JSON when nil" do
      issue = Hwaro::Services::Issue.new(
        id: "x",
        level: :error,
        category: "structure",
        file: nil,
        message: "m",
      )
      json = issue.to_json
      json.should_not contain(%("file":))
      json.should contain(%("level":"error"))
    end

    it "round-trips level through SymbolConverter.from_json" do
      # Regression: previously returned a String from a Symbol-typed method.
      # Validate every level the doctor service can emit.
      [:error, :warning, :info].each do |level|
        original = Hwaro::Services::Issue.new(
          id: "rt-#{level}",
          level: level,
          category: "config",
          file: nil,
          message: "round-trip",
        )
        decoded = Hwaro::Services::Issue.from_json(original.to_json)
        decoded.level.should eq(level)
        decoded.id.should eq(original.id)
      end
    end

    it "raises a parse error on unknown level strings" do
      bogus = %({"id":"x","level":"fatal","category":"config","message":"m"})
      expect_raises(JSON::ParseException, /Unknown issue level/) do
        Hwaro::Services::Issue.from_json(bogus)
      end
    end
  end
end
