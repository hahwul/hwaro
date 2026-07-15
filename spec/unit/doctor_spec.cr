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

      # `default_language` must resolve to a `[languages.<code>]` block,
      # otherwise the multilingual pipeline silently falls through to
      # untranslated content with broken hreflang.
      it "warns when default_language has no matching [languages.<code>] block" do
        config = base_config(%(\ndefault_language = "ja"\n\n[languages.en]\nlanguage_name = "English"\nweight = 1\n))
        issues = run_doctor(config)
        issues.any? { |i| i.id == "default-language-undefined" && i.message.includes?("\"ja\"") && i.message.includes?("en") }.should be_true
      end

      it "does not warn when default_language matches a defined language" do
        config = base_config(%(\ndefault_language = "en"\n\n[languages.en]\nlanguage_name = "English"\nweight = 1\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("default-language-undefined")).should be_false
      end

      it "skips default_language check when no [languages.*] are defined (single-language site)" do
        config = base_config(%(\ndefault_language = "ja"\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("default-language-undefined")).should be_false
      end

      # `markdown.math_engine` only renders for "katex" / "mathjax";
      # other strings silently produce no math output. The check is
      # gated on `math = true` because the field is a no-op otherwise.
      it "warns on invalid markdown.math_engine when math is enabled" do
        config = base_config(%(\n[markdown]\nmath = true\nmath_engine = "wolfram"\n))
        issues = run_doctor(config)
        issues.any? { |i| i.id == "markdown-math-engine-invalid" && i.message.includes?("wolfram") }.should be_true
      end

      it "does not warn on invalid markdown.math_engine when math is disabled" do
        config = base_config(%(\n[markdown]\nmath = false\nmath_engine = "wolfram"\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("markdown-math-engine-invalid")).should be_false
      end

      it "does not warn on katex or mathjax math_engine" do
        ["katex", "mathjax"].each do |engine|
          config = base_config(%(\n[markdown]\nmath = true\nmath_engine = "#{engine}"\n))
          issues = run_doctor(config)
          issues.any?(&.id.==("markdown-math-engine-invalid")).should be_false
        end
      end

      # `Models::Config.load` silently coerces an unknown
      # `pwa.cache_strategy` back to "cache-first", so doctor reads the
      # raw TOML to surface what the user actually typed.
      it "warns on invalid pwa.cache_strategy when pwa enabled" do
        config = base_config(%(\n[pwa]\nenabled = true\ncache_strategy = "telepathic"\n))
        issues = run_doctor(config)
        issues.any? { |i| i.id == "pwa-cache-strategy-invalid" && i.message.includes?("telepathic") }.should be_true
      end

      it "does not warn on valid pwa.cache_strategy values" do
        ["cache-first", "network-first", "stale-while-revalidate"].each do |strategy|
          config = base_config(%(\n[pwa]\nenabled = true\ncache_strategy = "#{strategy}"\n))
          issues = run_doctor(config)
          issues.any?(&.id.==("pwa-cache-strategy-invalid")).should be_false
        end
      end

      # `[deployment].target` selects which `[[deployment.targets]]`
      # block `hwaro deploy` uses. Pointing at an undefined name fails
      # at runtime; surfacing it here saves an actual deploy attempt.
      it "warns when deployment.target references an undefined target" do
        config = base_config(%(\n[deployment]\ntarget = "doesnotexist"\n\n[[deployment.targets]]\nname = "prod"\nurl = "file://./out"\n))
        issues = run_doctor(config)
        issues.any? { |i| i.id == "deployment-target-undefined" && i.message.includes?("doesnotexist") && i.message.includes?("prod") }.should be_true
      end

      it "does not warn when deployment.target matches a defined target" do
        config = base_config(%(\n[deployment]\ntarget = "prod"\n\n[[deployment.targets]]\nname = "prod"\nurl = "file://./out"\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("deployment-target-undefined")).should be_false
      end

      # `[related].taxonomies` referencing an undefined `[[taxonomies]]`
      # name makes the related-posts feature silently produce zero
      # matches — there's no other surface that flags this.
      it "warns when [related].taxonomies references an undefined taxonomy" do
        config = base_config(%(\n[related]\nenabled = true\ntaxonomies = ["nonexistent"]\n\n[[taxonomies]]\nname = "tags"\n))
        issues = run_doctor(config)
        issues.any? { |i| i.id == "related-taxonomy-undefined" && i.message.includes?("nonexistent") && i.message.includes?("tags") }.should be_true
      end

      it "does not warn when [related].taxonomies matches a defined taxonomy" do
        config = base_config(%(\n[related]\nenabled = true\ntaxonomies = ["tags"]\n\n[[taxonomies]]\nname = "tags"\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("related-taxonomy-undefined")).should be_false
      end

      it "does not warn when [related] is disabled" do
        config = base_config(%(\n[related]\nenabled = false\ntaxonomies = ["nonexistent"]\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("related-taxonomy-undefined")).should be_false
      end

      # A `[[menus.*]]` entry's `parent` must reference another entry's
      # `identifier` in the SAME menu. A typo silently gets promoted to
      # root at build time with only a build-log warning.
      it "warns when a menu entry's parent references an undefined identifier" do
        config = base_config(%(\n[[menus.main]]\nname = "Posts"\nidentifier = "posts"\n\n[[menus.main]]\nname = "Orphan"\nparent = "nonexistent"\n))
        issues = run_doctor(config)
        issues.any? { |i| i.id == "menu-parent-undefined" && i.message.includes?("nonexistent") && i.message.includes?("main") }.should be_true
      end

      it "does not warn when a menu entry's parent matches a declared identifier" do
        config = base_config(%(\n[[menus.main]]\nname = "Posts"\nidentifier = "posts"\n\n[[menus.main]]\nname = "First Post"\nparent = "posts"\n))
        issues = run_doctor(config)
        issues.any?(&.id.==("menu-parent-undefined")).should be_false
      end

      it "validates a per-language menu override's parent references against its OWN identifiers" do
        config = base_config(%(\n[[menus.main]]\nname = "Posts"\nidentifier = "posts"\n\n[languages.ko]\nlanguage_name = "Korean"\n\n[[languages.ko.menus.main]]\nname = "orphan-ko"\nparent = "posts"\n))
        issues = run_doctor(config)
        # "posts" is a GLOBAL identifier, not one declared in the ko override
        # (a per-language menu set fully replaces the global one), so this
        # must still be flagged even though "posts" exists in config.menus.
        issues.any? { |i| i.id == "menu-parent-undefined" && i.message.includes?("languages.ko.menus.main") }.should be_true
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
            i.id == "template-syntax-error" && i.level == :error && (i.file || "").ends_with?("page.html")
          end.should be_true
        end
      end

      it "catches reordered end-before-start (no longer fooled by balanced counts)" do
        # Previously the regex check counted opens vs closes; a swapped
        # `{% endif %}{% if true %}` pair had matching counts but is
        # still a syntax error — which Crinja's parser rejects.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir)
          File.write(File.join(templates_dir, "page.html"), "{% endif %}hello{% if true %}")
          File.write(File.join(templates_dir, "section.html"), "<html></html>")

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: templates_dir)
          issues = doctor.run
          issues.any? { |i| i.id == "template-syntax-error" && i.level == :error }.should be_true
        end
      end

      it "catches paired tags beyond if/for/block/macro (e.g. raw)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir)
          # `{% raw %}` is a Jinja paired tag; the regex check ignored it.
          File.write(File.join(templates_dir, "page.html"), "{% raw %}{{ literal }}")
          File.write(File.join(templates_dir, "section.html"), "<html></html>")

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: templates_dir)
          issues = doctor.run
          issues.any? { |i| i.id == "template-syntax-error" && i.level == :error }.should be_true
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

        # Should mention non-optional sections like [markdown], [sitemap]
        # (niche/optional sections like [robots], [pwa], [amp] are skipped in
        # normal doctor output because `doctor --fix` (without --full/--approve)
        # won't add them either; users opt-in explicitly).
        messages = missing_issues.map(&.message)
        messages.any?(&.includes?("[markdown]")).should be_true
        messages.any?(&.includes?("[sitemap]")).should be_true
      end

      it "does not report niche optional sections (pwa/amp/etc) that --fix won't auto-add" do
        # Without this skip, a freshly-scaffolded `bare` site would flag
        # 8 'info' rows for sections that the recommended fix path won't
        # actually add. Stay silent — users opt in by configuring them.
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        messages = missing_issues.map(&.message)
        messages.any?(&.includes?("[pwa]")).should be_false
        messages.any?(&.includes?("[amp]")).should be_false
        messages.any?(&.includes?("[build]")).should be_false
        messages.any?(&.includes?("[menus]")).should be_false
      end

      it "does not report og.auto_image (optional sub-section) even when [og] exists" do
        config = <<-TOML
          title = "My Site"
          base_url = "https://example.com"
          [og]
          default_image = "/img.png"
          TOML
        issues = run_doctor(config)
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.any?(&.message.includes?("[og.auto_image]")).should be_false
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

      it "suggests --full in issue messages" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        # Current messages guide users to `hwaro doctor --full` (or --approve)
        # for section recommendations; plain --fix only does value corrections.
        missing_issues.all?(&.message.includes?("--full")).should be_true
      end
    end

    describe "#fix_config" do
      it "appends missing sections to config.toml" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          # In the new model, plain fix_config() does not add sections by default.
          # Use approve_sections: true to request them.
          added = doctor.fix_config(approve_sections: true).sections_added

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
          added = doctor.fix_config(approve_sections: true).sections_added

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
          added = doctor.fix_config.sections_added

          added.should_not contain("pwa")
        end
      end

      it "adds recommended sections only when approve_sections is true" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)

          # Default (plain --fix): should not add optional sections
          added_default = doctor.fix_config.sections_added
          added_default.should be_empty

          # With approve_sections: true (--approve or --full)
          added = doctor.fix_config(approve_sections: true).sections_added
          added.should contain("search")
          added.should contain("pagination")
          added.should contain("pwa") # now included when explicitly approved
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
        # With the new model, plain fix_config() does not add sections by default.
        # Use approve_sections: true to test the section-adding path atomically.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config(approve_sections: true)
          summary.sections_added.should_not be_empty

          File.exists?("#{config_path}.hwaro-tmp").should be_false
          text = File.read(config_path)
          text.should contain(%(title = "My Site"))
          # At least one recommended section should have been appended
          text.should match(/\[pwa\]|\[search\]|\[feeds\]/)
        end
      end

      it "trims trailing slash from base_url as a value fix" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com/"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.any? { |f| f.field == "base_url" && f.before.ends_with?("/") && !f.after.ends_with?("/") }.should be_true

          File.read(config_path).should contain(%(base_url = "https://example.com"))
          File.read(config_path).should_not contain(%(base_url = "https://example.com/"))
        end
      end

      it "clamps out-of-range sitemap.priority as a value fix" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = "https://example.com"\n[sitemap]\npriority = 1.5\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.any? { |f| f.field == "sitemap.priority" && f.after == "1.0" }.should be_true

          File.read(config_path).should contain("priority = 1.0")
        end
      end

      it "leaves files untouched in dry-run and reports the planned fix" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          original = %(title = "S"\nbase_url = "https://example.com/"\n)
          File.write(config_path, original)

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config(dry_run: true)
          summary.dry_run.should be_true
          summary.value_fixes.any? { |f| f.field == "base_url" }.should be_true

          # File contents must be byte-identical when dry-running.
          File.read(config_path).should eq(original)
        end
      end

      # Regression: the header tracker only matched `[name]` headers, so a
      # `[[array.of.tables]]` header after `[sitemap]` did not reset the
      # in-sitemap state and `--fix` clamped priority keys belonging to
      # completely unrelated tables — silent corruption of user data.
      it "does not clamp priority keys in unrelated [[array-of-tables]] after [sitemap]" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          original = %(title = "S"\nbase_url = "https://example.com"\n\n[sitemap]\nchangefreq = "weekly"\n\n[[taxonomies]]\nname = "tags"\npriority = 2\n)
          File.write(config_path, original)

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.should be_empty
          File.read(config_path).should eq(original)
        end
      end

      it "clamps sitemap.priority when the [sitemap] header carries a trailing comment" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = "https://example.com"\n\n[sitemap] # sitemap tuning\npriority = 5.0\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.any? { |f| f.field == "sitemap.priority" && f.after == "1.0" }.should be_true
          File.read(config_path).should contain("priority = 1.0")
        end
      end

      it "clamps a top-level dotted sitemap.priority key" do
        # `sitemap.priority = N` above the first table header is the same
        # config value as `[sitemap] priority = N`; doctor's advisory fires
        # on it, so --fix must be able to repair it too.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = "https://example.com"\nsitemap.priority = 3.0\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.any? { |f| f.field == "sitemap.priority" && f.after == "1.0" }.should be_true
          File.read(config_path).should contain("sitemap.priority = 1.0")
        end
      end

      it "does not clamp a dotted sitemap.priority spelling below a table header" do
        # After a header, `sitemap.priority` names `<table>.sitemap.priority`,
        # which is not the sitemap config value.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          original = %(title = "S"\nbase_url = "https://example.com"\n\n[extra]\nsitemap.priority = 3.0\n)
          File.write(config_path, original)

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          doctor.fix_config.value_fixes.should be_empty
          File.read(config_path).should eq(original)
        end
      end

      it "clamps a negative sitemap.priority up to 0.0" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = "https://example.com"\n[sitemap]\npriority = -0.5\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.any? { |f| f.field == "sitemap.priority" && f.after == "0.0" }.should be_true
          File.read(config_path).should contain("priority = 0.0")
        end
      end

      it "trims trailing slash from a single-quoted (TOML literal string) base_url" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = 'https://example.com/'\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config
          summary.value_fixes.any? { |f| f.field == "base_url" }.should be_true
          File.read(config_path).should contain(%(base_url = 'https://example.com'))
        end
      end

      # Regression: the commented [menus] snippet only contains
      # `# [[menus.main]]` lines (no `# [menus]` header), which neither the
      # missing-section scan nor the duplicate guard recognized — so every
      # approve run re-reported "menus" as missing and appended the snippet
      # again, growing config.toml forever.
      it "is idempotent: a second approve_sections run adds nothing" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          doctor.fix_config(approve_sections: true).sections_added.should_not be_empty
          after_first = File.read(config_path)

          doctor.fix_config(approve_sections: true).sections_added.should be_empty
          File.read(config_path).should eq(after_first)
        end
      end

      it "preserves file permissions when rewriting config.toml" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = "https://example.com/"\n))
          File.chmod(config_path, 0o600)

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          doctor.fix_config.value_fixes.should_not be_empty
          (File.info(config_path).permissions.value & 0o777).should eq(0o600)
        end
      end

      it "does not apply value fixes when apply_value_fixes is false (bare --approve)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "S"\nbase_url = "https://example.com/"\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          summary = doctor.fix_config(approve_sections: true, apply_value_fixes: false)
          summary.value_fixes.should be_empty
          summary.sections_added.should_not be_empty
          # The trailing slash must survive — --approve only adds sections.
          File.read(config_path).should contain(%(base_url = "https://example.com/"))
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
          added = doctor.fix_config.sections_added
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

    describe "directory structure (recursive)" do
      it "flags nested section directories that are missing _index.md" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          # blog/ has _index, blog/2024/ does not but does contain content
          FileUtils.mkdir_p(File.join(content_dir, "blog", "2024"))
          File.write(File.join(content_dir, "blog", "_index.md"), "+++\ntitle = \"Blog\"\n+++\n")
          File.write(File.join(content_dir, "blog", "2024", "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"\"\n+++\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? { |i| i.id == "structure-missing-index" && i.message.includes?("blog/2024/") }.should be_true
        end
      end

      it "does not flag asset-only directories (no markdown underneath)" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "blog", "images"))
          File.write(File.join(content_dir, "blog", "_index.md"), "+++\ntitle = \"Blog\"\n+++\n")
          File.write(File.join(content_dir, "blog", "images", "hero.png"), "fake png")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          # no warning for blog/images even though it has no _index.md
          issues.any? { |i| i.id == "structure-missing-index" && i.message.includes?("images") }.should be_false
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

      # `[pwa] offline_page` / `precache_urls` are routes, not just static
      # files: `/about/` builds to `public/about/index.html` from
      # `content/about.md`. Resolving against `static/` alone produced a
      # spurious "file not found" for valid routes.
      it "does not warn on a [pwa] offline_page route backed by a content file" do
        Dir.mktmpdir do |dir|
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(content_dir)
          File.write(File.join(content_dir, "about.md"), "+++\ntitle = \"About\"\n+++\n")

          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[pwa]\nenabled = true\noffline_page = "/about/"\n))

          doctor = Hwaro::Services::Doctor.new(
            content_dir: content_dir,
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: File.join(dir, "static"),
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("offline_page") }.should be_false
          end
        end
      end

      it "does not warn on a [pwa] precache route backed by a built public page" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[pwa]\nenabled = true\nprecache_urls = ["/blog/"]\n))

          # No content source, but the built output page exists.
          FileUtils.mkdir_p(File.join(dir, "public", "blog"))
          File.write(File.join(dir, "public", "blog", "index.html"), "<html></html>")

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: File.join(dir, "static"),
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_false
          end
        end
      end

      it "still warns on a genuinely-missing [pwa] precache asset (non-route path)" do
        # Route-style values (trailing slash / no extension) are produced at
        # build time and can't be validated pre-build, so doctor stays quiet on
        # them and lets the authoritative build-time precache check catch misses.
        # An asset-style path that resolves nowhere is still flagged here.
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[pwa]\nenabled = true\nprecache_urls = ["/ghost.png"]\n))

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
                i.message.includes?("precache_urls") &&
                i.message.includes?("/ghost.png")
            end.should be_true
          end
        end
      end

      it "does not validate external [pwa] precache URLs" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, %(title = "T"\nbase_url = "http://x"\n[pwa]\nenabled = true\nprecache_urls = ["https://cdn.example.com/app.js"]\n))

          doctor = Hwaro::Services::Doctor.new(
            content_dir: File.join(dir, "content"),
            config_path: config_path,
            templates_dir: File.join(dir, "templates"),
            static_dir: File.join(dir, "static"),
          )
          Dir.cd(dir) do
            issues = doctor.run
            issues.any? { |i| i.id == "config-path-missing" && i.message.includes?("precache") }.should be_false
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

      # A page/section can register a menu name that no [[menus.*]] block
      # declares — but ONLY worth flagging when config declares at least one
      # menu at all, since a fully front-matter-defined menu (no [[menus.*]]
      # anywhere) is a legal, supported setup on its own.
      it "warns when front matter registers a menu name not declared in config" do
        issues = run_doctor(
          base_config(%(\n[[menus.main]]\nname = "Home"\nurl = "/"\n)),
          {"post.md" => %(+++\ntitle = "Post"\nmenus = ["sidebar"]\n+++\nBody\n)}
        )
        issues.any? { |i| i.id == "menu-undeclared" && i.message.includes?("sidebar") && i.message.includes?("main") }.should be_true
      end

      it "does not warn when front matter registers a menu name that config declares" do
        issues = run_doctor(
          base_config(%(\n[[menus.main]]\nname = "Home"\nurl = "/"\n)),
          {"post.md" => %(+++\ntitle = "Post"\nmenus = ["main"]\n+++\nBody\n)}
        )
        issues.any?(&.id.==("menu-undeclared")).should be_false
      end

      it "does not warn about undeclared front-matter menus when config declares no menus at all" do
        issues = run_doctor(
          base_config,
          {"post.md" => %(+++\ntitle = "Post"\nmenus = ["main"]\n+++\nBody\n)}
        )
        issues.any?(&.id.==("menu-undeclared")).should be_false
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

    it "round-trips through JSON when an Issue list is decoded" do
      issues = [
        Hwaro::Services::Issue.new(id: "a", level: :error, category: "config", file: "config.toml", message: "boom"),
        Hwaro::Services::Issue.new(id: "b", level: :warning, category: "content", file: nil, message: "soft"),
      ]
      decoded = Array(Hwaro::Services::Issue).from_json(issues.to_json)
      decoded.size.should eq(2)
      decoded.first.level.should eq(:error)
      decoded.last.level.should eq(:warning)
    end

    it "raises a parse error on unknown level strings" do
      bogus = %({"id":"x","level":"fatal","category":"config","message":"m"})
      expect_raises(JSON::ParseException, /Unknown issue level/) do
        Hwaro::Services::Issue.from_json(bogus)
      end
    end
  end
end
