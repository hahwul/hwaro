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
      it "warns when config file is missing" do
        issues = run_doctor_no_config
        issues.any? { |i| i.category == "config" && i.message.includes?("not found") }.should be_true
      end

      it "warns when base_url is empty" do
        issues = run_doctor(%(title = "My Site"\n))
        issues.any? { |i| i.message.includes?("base_url") }.should be_true
      end

      it "warns when title is default" do
        issues = run_doctor(%(title = "Hwaro Site"\nbase_url = "https://example.com"\n))
        issues.any? { |i| i.message.includes?("default value") }.should be_true
      end

      it "does not warn when title is custom" do
        issues = run_doctor(base_config)
        issues.any? { |i| i.message.includes?("default value") }.should be_false
      end

      it "warns when feeds enabled but filename empty" do
        issues = run_doctor(base_config("\n[feeds]\nenabled = true\nfilename = \"\"\n"))
        issues.any? { |i| i.message.includes?("feeds.filename") }.should be_true
      end

      it "does not warn when feeds disabled" do
        issues = run_doctor(base_config("\n[feeds]\nenabled = false\n"))
        issues.any? { |i| i.message.includes?("feeds.filename") }.should be_false
      end

      it "warns on invalid sitemap changefreq" do
        issues = run_doctor(base_config("\n[sitemap]\nchangefreq = \"biweekly\"\n"))
        issues.any? { |i| i.message.includes?("changefreq") && i.message.includes?("biweekly") }.should be_true
      end

      it "does not warn on valid sitemap changefreq" do
        issues = run_doctor(base_config("\n[sitemap]\nchangefreq = \"daily\"\n"))
        issues.any? { |i| i.message.includes?("changefreq") }.should be_false
      end

      it "warns on sitemap priority out of range" do
        issues = run_doctor(base_config("\n[sitemap]\npriority = 1.5\n"))
        issues.any? { |i| i.message.includes?("priority") && i.message.includes?("out of range") }.should be_true
      end

      it "warns on duplicate taxonomy names" do
        issues = run_doctor(base_config("\n[[taxonomies]]\nname = \"tags\"\n\n[[taxonomies]]\nname = \"tags\"\n"))
        issues.any? { |i| i.message.includes?("Duplicate taxonomy") }.should be_true
      end

      it "does not warn on unique taxonomy names" do
        issues = run_doctor(base_config("\n[[taxonomies]]\nname = \"tags\"\n\n[[taxonomies]]\nname = \"categories\"\n"))
        issues.any? { |i| i.message.includes?("Duplicate taxonomy") }.should be_false
      end

      it "warns on invalid search format when search enabled" do
        issues = run_doctor(base_config("\n[search]\nenabled = true\nformat = \"invalid_format\"\n"))
        issues.any? { |i| i.message.includes?("search.format") }.should be_true
      end

      it "does not warn on valid search format" do
        issues = run_doctor(base_config("\n[search]\nenabled = true\nformat = \"fuse_json\"\n"))
        issues.any? { |i| i.message.includes?("search.format") }.should be_false
      end

      it "reports error on invalid config TOML" do
        issues = run_doctor("invalid = [toml\n")
        issues.any? { |i| i.level == :error && i.message.includes?("parse") }.should be_true
      end
    end

    describe "content diagnostics" do
      it "warns on missing title in TOML frontmatter" do
        issues = run_doctor(base_config, {"test.md" => "+++\ndate = \"2024-01-01\"\n+++\n\nHello"})
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.any? { |i| i.message.includes?("Missing title") }.should be_true
      end

      it "warns on Untitled title" do
        issues = run_doctor(base_config, {"test.md" => "+++\ntitle = \"Untitled\"\ndate = \"2024-01-01\"\n+++\n\nHello"})
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.any? { |i| i.message.includes?("Untitled") }.should be_true
      end

      it "warns on missing description" do
        issues = run_doctor(base_config, {"test.md" => "+++\ntitle = \"My Post\"\ndate = \"2024-01-01\"\n+++\n\nHello"})
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.any? { |i| i.message.includes?("Missing description") }.should be_true
      end

      it "does not warn on missing date" do
        issues = run_doctor(base_config, {"test.md" => "+++\ntitle = \"My Post\"\ndescription = \"A post\"\n+++\n\nHello"})
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.any? { |i| i.message.includes?("Missing date") }.should be_false
      end

      it "reports draft files as info" do
        issues = run_doctor(base_config, {"test.md" => "+++\ntitle = \"Draft Post\"\ndraft = true\ndate = \"2024-01-01\"\ndescription = \"A draft\"\n+++\n\nHello"})
        draft_issues = issues.select { |i| i.message.includes?("draft") && i.level == :info }
        draft_issues.size.should eq(1)
      end

      it "warns on image missing alt text" do
        issues = run_doctor(base_config, {"test.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n![](image.png)\n"})
        issues.any? { |i| i.message.includes?("alt text") }.should be_true
      end

      it "does not warn on image with alt text" do
        issues = run_doctor(base_config, {"test.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n![A photo](image.png)\n"})
        issues.any? { |i| i.message.includes?("alt text") }.should be_false
      end

      it "reports TOML frontmatter parse errors" do
        issues = run_doctor(base_config, {"bad.md" => "+++\ntitle = [invalid\n+++\n\nContent"})
        issues.any? { |i| i.level == :error && i.message.includes?("TOML frontmatter parse error") }.should be_true
      end

      it "handles YAML frontmatter" do
        issues = run_doctor(base_config, {"test.md" => "---\ntitle: \"My YAML Post\"\ndate: \"2024-01-01\"\ndescription: \"A post\"\n---\n\nHello"})
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.any? { |i| i.message.includes?("Missing title") }.should be_false
      end

      it "no issues for well-formed content" do
        issues = run_doctor(base_config, {"good.md" => "+++\ntitle = \"Good Post\"\ndate = \"2024-01-01\"\ndescription = \"A good post\"\n+++\n\n![Screenshot](img.png)\n"})
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.should be_empty
      end

      it "skips content check when content dir missing" do
        issues = run_doctor(base_config)
        content_issues = issues.select { |i| i.category == "content" }
        content_issues.should be_empty
      end

      it "warns on broken @/ internal link" do
        files = {
          "post.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n[Link](@/nonexistent/page.md)\n",
        }
        issues = run_doctor(base_config, files)
        issues.any? { |i| i.message.includes?("broken internal link") }.should be_true
      end

      it "does not warn on valid @/ internal link" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "about"))
          File.write(File.join(content_dir, "about", "_index.md"), "+++\ntitle = \"About\"\ndate = \"2024-01-01\"\ndescription = \"About\"\n+++\n")
          File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n[About](@/about/_index.md)\n")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path)
          issues = doctor.run
          issues.any? { |i| i.message.includes?("broken internal link") }.should be_false
        end
      end

      it "does not flag web path links as broken" do
        files = {
          "post.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n[CLI](/start/cli/#deploy)\n",
        }
        issues = run_doctor(base_config, files)
        issues.any? { |i| i.message.includes?("broken internal link") }.should be_false
      end

      it "does not flag @/ links inside code blocks" do
        files = {
          "post.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n```markdown\n[Link](@/nonexistent/page.md)\n```\n",
        }
        issues = run_doctor(base_config, files)
        issues.any? { |i| i.message.includes?("broken internal link") }.should be_false
      end

      it "does not flag images inside code blocks" do
        files = {
          "post.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n```markdown\n![](example.png)\n```\n",
        }
        issues = run_doctor(base_config, files)
        issues.any? { |i| i.message.includes?("alt text") }.should be_false
      end

      it "does not flag external links as broken" do
        files = {
          "post.md" => "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ndescription = \"A post\"\n+++\n\n[Google](https://google.com)\n",
        }
        issues = run_doctor(base_config, files)
        issues.any? { |i| i.message.includes?("broken internal link") }.should be_false
      end
    end

    describe "config — base_url format" do
      it "warns when base_url has no protocol" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "example.com"\n))
        issues.any? { |i| i.message.includes?("http://") }.should be_true
      end

      it "warns when base_url has trailing slash" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com/"\n))
        issues.any? { |i| i.message.includes?("trailing slash") }.should be_true
      end

      it "does not warn on proper base_url" do
        issues = run_doctor(base_config)
        issues.any? { |i| i.message.includes?("trailing slash") }.should be_false
        issues.any? { |i| i.message.includes?("http://") && i.message.includes?("https://") }.should be_false
      end
    end

    describe "template diagnostics" do
      it "warns when templates directory is missing" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          content_dir = File.join(dir, "content")

          doctor = Hwaro::Services::Doctor.new(content_dir: content_dir, config_path: config_path, templates_dir: File.join(dir, "templates"))
          issues = doctor.run
          issues.any? { |i| i.category == "template" && i.message.includes?("not found") }.should be_true
        end
      end

      it "warns when required template files are missing" do
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
          tpl_issues.any? { |i| i.message.includes?("section.html") }.should be_true
          tpl_issues.any? { |i| i.message.includes?("page.html") }.should be_false
        end
      end

      it "warns on unclosed template block tags" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          File.write(config_path, base_config)
          templates_dir = File.join(dir, "templates")
          FileUtils.mkdir_p(templates_dir)
          File.write(File.join(templates_dir, "page.html"), "{% if true %}hello")
          File.write(File.join(templates_dir, "section.html"), "<html></html>")

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path, templates_dir: templates_dir)
          issues = doctor.run
          issues.any? { |i| i.message.includes?("unclosed template block") }.should be_true
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
        messages.any? { |m| m.includes?("[pwa]") }.should be_true
        messages.any? { |m| m.includes?("[amp]") }.should be_true
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
        missing_issues.any? { |i| i.message.includes?("[og.auto_image]") }.should be_true
      end

      it "does not report og.auto_image when [og] itself is missing" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.none? { |i| i.message.includes?("[og.auto_image]") }.should be_true
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

        missing_issues.none? { |i| i.message.includes?("[pwa]") }.should be_true
        missing_issues.none? { |i| i.message.includes?("[amp]") }.should be_true
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

        missing_issues.none? { |i| i.message.includes?("[pwa]") }.should be_true
        missing_issues.none? { |i| i.message.includes?("[amp]") }.should be_true
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
        missing_issues.none? { |i| i.message.includes?("[og.auto_image]") }.should be_true
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
        missing_issues.none? { |i| i.message.includes?("[og.auto_image]") }.should be_true
      end

      it "suggests --fix in issue messages" do
        issues = run_doctor(%(title = "My Site"\nbase_url = "https://example.com"))
        missing_issues = issues.select { |i| i.category == "config_missing" }
        missing_issues.all? { |i| i.message.includes?("--fix") }.should be_true
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

      it "returns empty when nothing is missing" do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, "config.toml")
          # Write a config with all known sections
          sections = Hwaro::Services::Doctor::KNOWN_CONFIG_SECTIONS.keys.map { |k|
            "[#{k}]"
          }.join("\n")
          File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n#{sections}\n[og]\ndefault_image = "/img.png"\n[og.auto_image]\nenabled = false\n[image_processing.lqip]\nenabled = false\n))

          doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path)
          added = doctor.fix_config
          added.should be_empty
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
end
