require "../../../spec_helper"

# Doctor answers "will the build do what this site expects?", so every check
# has to resolve things the way the build does. Each example below is a case
# where it did not: doctor failed a site the build handles, or passed one the
# build gets wrong. Each was reproduced against `hwaro build` first.
private def parity_doctor(dir : String) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    static_dir: File.join(dir, "static"),
  )
end

private def parity_site(dir : String, config_extra : String = "")
  %w[content templates static].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n#{config_extra}))
  File.write(File.join(dir, "templates", "page.html"), "{{ content }}")
  File.write(File.join(dir, "templates", "section.html"), "{{ content }}")
end

private def write_file(dir : String, relative : String, body : String = "")
  path = File.join(dir, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
end

private def ids_for(dir : String) : Array(String)
  parity_doctor(dir).run.map(&.id)
end

private def issues_with(dir : String, id : String) : Array(Hwaro::Services::Issue)
  parity_doctor(dir).run.select { |i| i.id == id }
end

private MULTILINGUAL = <<-TOML
  default_language = "en"

  [[menus.main]]
  name = "Home"
  url = "/"

  [languages.en]
  language_name = "English"

  [languages.ko]
  language_name = "Korean"

  [[languages.ko.menus.footer]]
  name = "Home"
  url = "/"
  TOML

describe Hwaro::Services::Doctor do
  describe "required templates" do
    # `load_templates` copies `default` into an absent `page` slot.
    it "accepts default.html in place of page.html" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        File.rename(File.join(dir, "templates", "page.html"), File.join(dir, "templates", "default.html"))

        ids_for(dir).should_not contain("template-required-missing")
      end
    end

    # Sections render through `page` when `section` is absent, so the build
    # is fine; an error here failed CI for sites with no sections at all and
    # could not be ignored.
    it "reports a missing section.html as an ignorable warning" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        File.delete(File.join(dir, "templates", "section.html"))

        issues = parity_doctor(dir).run
        issues.map(&.id).should_not contain("template-required-missing")
        issues.find! { |i| i.id == "template-section-missing" }.level.should eq(:warning)

        File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n[doctor]\nignore = ["template-section-missing"]\n))
        ids_for(dir).should_not contain("template-section-missing")
      end
    end
  end

  describe "content file discovery" do
    # ReadContent compares the extension case-insensitively, so `Bad.MD`
    # is published — and its broken front matter fails the build.
    it "parses front matter in upper-case .MD files" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "content/Bad.MD", "+++\ntitle = \n+++\nbody\n")

        issues_with(dir, "content-frontmatter-invalid").map(&.file).should eq([File.join(dir, "content", "Bad.MD")])
      end
    end

    it "treats a directory of .MD pages as a section" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "content/blog/one.MD", "+++\ntitle = \"1\"\n+++\n")
        write_file(dir, "content/blog/nested/two.MD", "+++\ntitle = \"2\"\n+++\n")

        issues_with(dir, "structure-missing-index").map(&.file).should contain(File.join(dir, "content", "blog"))
      end
    end
  end

  describe "front matter menus per language" do
    # `[languages.ko]` declares its own menus, which REPLACE the global set
    # for Korean pages (Content::Menus.build_for_language).
    it "checks a translated page against its language's menus" do
      Dir.mktmpdir do |dir|
        parity_site(dir, MULTILINGUAL)
        write_file(dir, "content/about.ko.md", "+++\ntitle = \"a\"\nmenus = [\"footer\"]\n+++\n")
        write_file(dir, "content/stray.ko.md", "+++\ntitle = \"s\"\nmenus = [\"main\"]\n+++\n")
        write_file(dir, "content/about.md", "+++\ntitle = \"a\"\nmenus = [\"main\"]\n+++\n")

        flagged = issues_with(dir, "menu-undeclared")
        flagged.map { |i| File.basename(i.file.to_s) }.should eq(["stray.ko.md"])
        flagged.first.message.should contain("[[languages.ko.menus.main]]")
      end
    end

    it "checks default-language pages against the global menus" do
      Dir.mktmpdir do |dir|
        parity_site(dir, MULTILINGUAL)
        write_file(dir, "content/about.md", "+++\ntitle = \"a\"\nmenus = [\"footer\"]\n+++\n")
        write_file(dir, "content/about.en.md", "+++\ntitle = \"a\"\nmenus = [\"footer\"]\n+++\n")

        issues_with(dir, "menu-undeclared").size.should eq(2)
      end
    end
  end

  describe "front matter template references" do
    it "reports a template or page_template that matches no file" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "content/post.md", "+++\ntitle = \"p\"\ntemplate = \"nope.html\"\n+++\n")
        write_file(dir, "content/blog/_index.md", "+++\ntitle = \"b\"\npage_template = \"article\"\n+++\n")

        issues = issues_with(dir, "content-template-missing")
        issues.map { |i| File.basename(i.file.to_s) }.sort!.should eq(["_index.md", "post.md"])
        issues.all? { |i| i.level == :warning }.should be_true
      end
    end

    it "accepts names the loader resolves, with or without an extension" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "templates/post.jinja", "{{ content }}")
        write_file(dir, "content/a.md", "+++\ntitle = \"a\"\ntemplate = \"post.html\"\n+++\n")
        write_file(dir, "content/b.md", "+++\ntitle = \"b\"\ntemplate = \"post\"\n+++\n")
        write_file(dir, "content/blog/_index.md", "+++\ntitle = \"b\"\npage_template = \"post\"\n+++\n")

        ids_for(dir).should_not contain("content-template-missing")
      end
    end

    # The build ignores `page_template` anywhere but a section index.
    it "ignores page_template outside a section index" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "content/a.md", "+++\ntitle = \"a\"\npage_template = \"nope\"\n+++\n")

        ids_for(dir).should_not contain("content-template-missing")
      end
    end

    # ReadContent only reads a language suffix on a multilingual site, so on
    # a single-language site `_index.en.md` is an ordinary page.
    it "does not treat _index.<default>.md as a section index on a single-language site" do
      Dir.mktmpdir do |dir|
        parity_site(dir, %(default_language = "en"\n))
        write_file(dir, "content/blog/_index.en.md", "+++\ntitle = \"b\"\npage_template = \"nope\"\n+++\n")

        ids_for(dir).should_not contain("content-template-missing")
      end
    end

    it "checks a section's cascade template" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "content/blog/_index.md", "+++\ntitle = \"b\"\n[cascade]\ntemplate = \"psot\"\n+++\n")

        issues_with(dir, "content-template-missing").first.message.should contain("cascade.template")
      end
    end

    # The build normalizes ".html" to "" and warns that it is not found.
    it "reports a template name that is only an extension" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        write_file(dir, "content/a.md", "+++\ntitle = \"a\"\ntemplate = \".html\"\n+++\n")

        issues_with(dir, "content-template-missing").size.should eq(1)
      end
    end

    it "resolves page via default.html" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        File.rename(File.join(dir, "templates", "page.html"), File.join(dir, "templates", "default.html"))
        write_file(dir, "content/a.md", "+++\ntitle = \"a\"\ntemplate = \"page\"\n+++\n")

        ids_for(dir).should_not contain("content-template-missing")
      end
    end
  end

  describe "byte order mark in config.toml" do
    # Config.load strips the BOM, so the site builds and doctor's own config
    # checks pass; the raw-text scans must agree.
    bom = "﻿"

    it "still reports missing config sections" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        File.write(File.join(dir, "config.toml"), %(#{bom}title = "Site"\nbase_url = "https://example.com"\n))

        parity_doctor(dir).missing_config_sections.should contain("sitemap")
      end
    end

    it "lets --fix rewrite the file and keeps the mark" do
      Dir.mktmpdir do |dir|
        parity_site(dir)
        config_path = File.join(dir, "config.toml")
        File.write(config_path, %(#{bom}base_url = "https://example.com/"\ntitle = "Site"\n))

        summary = parity_doctor(dir).fix_config(apply_value_fixes: true)
        summary.value_fixes.map(&.field).should eq(["base_url"])
        File.read(config_path).should eq(%(#{bom}base_url = "https://example.com"\ntitle = "Site"\n))
      end
    end
  end

  describe "sitemap.priority" do
    # TOML accepts `inf`/`nan`; the loader swaps in the default without a word.
    it "reports a non-finite priority" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[sitemap]\npriority = inf\n")

        issues_with(dir, "sitemap-priority-range").first.message.should contain("not a finite number")
      end
    end

    it "lets --fix clear inf and nan without changing the built value" do
      # The loader builds with the default for every non-finite value, so
      # that is what --fix writes; clamping inf to 1.0 would change output.
      {"inf" => "0.5", "-inf" => "0.5", "nan" => "0.5", "7" => "1.0", "-2" => "0.0"}.each do |raw, fixed|
        Dir.mktmpdir do |dir|
          parity_site(dir, "[sitemap]\npriority = #{raw} # note\n")

          parity_doctor(dir).fix_config(apply_value_fixes: true)
          File.read(File.join(dir, "config.toml")).should contain("priority = #{fixed} # note")
        end
      end
    end
  end

  describe "language codes" do
    it "reports codes that differ only in case" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[languages.en]\nlanguage_name = \"E\"\n[languages.EN]\nlanguage_name = \"E\"\n")

        issues_with(dir, "language-duplicate").size.should eq(1)
      end
    end

    it "counts default_language among the codes" do
      Dir.mktmpdir do |dir|
        parity_site(dir, %(default_language = "en"\n[languages.EN]\nlanguage_name = "E"\n[languages.ko]\nlanguage_name = "K"\n))

        issues_with(dir, "language-duplicate").size.should eq(1)
      end
    end
  end

  describe "[auto_includes] dirs" do
    # The build globs `static/<dir>` only.
    it "reports a directory that exists only outside static/" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[auto_includes]\nenabled = true\ndirs = [\"assets/css\", \"js\"]\n")
        write_file(dir, "assets/css/site.css", "a{}")
        write_file(dir, "static/js/site.js", "")

        Dir.cd(dir) do
          messages = issues_with(dir, "config-dir-missing").map(&.message)
          messages.size.should eq(1)
          messages.first.should contain("assets/css")
        end
      end
    end
  end

  describe "URL-valued config paths" do
    it "reports a static/-prefixed og default_image (it publishes without the prefix)" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[og]\ndefault_image = \"static/img/og.png\"\n")
        write_file(dir, "static/img/og.png")

        Dir.cd(dir) do
          issues = issues_with(dir, "config-path-missing")
          issues.size.should eq(1)
          issues.first.message.should contain("drop the static/ prefix")
        end
      end
    end

    it "reports an og default_image that only exists outside static/" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[og]\ndefault_image = \"og.png\"\n")
        write_file(dir, "og.png")

        Dir.cd(dir) { issues_with(dir, "config-path-missing").size.should eq(1) }
      end
    end

    # A content/ file reaches the site at the same path only when
    # [content.files] publishes it.
    it "accepts a content/ image only when [content.files] publishes it" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[og]\ndefault_image = \"/og.png\"\n")
        write_file(dir, "content/og.png")
        Dir.cd(dir) { issues_with(dir, "config-path-missing").size.should eq(1) }

        File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n[og]\ndefault_image = "/og.png"\n[content.files]\nallow_extensions = ["png"]\n))
        Dir.cd(dir) { ids_for(dir).should_not contain("config-path-missing") }
      end
    end

    it "accepts published spellings" do
      Dir.mktmpdir do |dir|
        parity_site(dir, <<-TOML)
          [og]
          default_image = "/img/og.png?v=2"

          [pwa]
          enabled = true
          icons = ["static/icons/i-192.png", "/icons/i-192.png", "icons/i-192.png"]
          TOML
        write_file(dir, "static/img/og.png")
        write_file(dir, "static/icons/i-192.png")

        Dir.cd(dir) { ids_for(dir).should_not contain("config-path-missing") }
      end
    end

    # `/myindex.html` lost its `index.html` suffix and resolved against
    # `content/my.md`.
    it "does not treat a file ending in index.html as an index route" do
      Dir.mktmpdir do |dir|
        parity_site(dir, "[pwa]\nenabled = true\noffline_page = \"/myindex.html\"\n")
        write_file(dir, "content/my.md", "+++\ntitle = \"m\"\n+++\n")

        Dir.cd(dir) { issues_with(dir, "config-path-missing").size.should eq(1) }
      end
    end
  end
end
