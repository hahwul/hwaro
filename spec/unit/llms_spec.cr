require "../spec_helper"

describe Hwaro::Content::Seo::Llms do
  describe ".generate (config-only)" do
    it "does not generate llms.txt when disabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)
        File.exists?(File.join(output_dir, "llms.txt")).should be_false
      end
    end

    it "generates llms.txt when enabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "This is a test site for AI crawlers."

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        file_path = File.join(output_dir, "llms.txt")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("This is a test site for AI crawlers.")
      end
    end

    it "uses default filename llms.txt" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "Instructions"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)
        File.exists?(File.join(output_dir, "llms.txt")).should be_true
      end
    end

    it "uses custom filename when configured" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.filename = "custom-llms.txt"
      config.llms.instructions = "Custom instructions"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)
        File.exists?(File.join(output_dir, "custom-llms.txt")).should be_true
      end
    end

    it "generates empty file when instructions are empty" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = ""

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        file_path = File.join(output_dir, "llms.txt")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should eq("")
      end
    end

    it "appends newline at end when content does not end with one" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "No trailing newline"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        content = File.read(File.join(output_dir, "llms.txt"))
        content.should end_with("\n")
      end
    end

    it "does not double-add newline when content already ends with one" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "Already has newline\n"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        content = File.read(File.join(output_dir, "llms.txt"))
        content.should eq("Already has newline\n")
      end
    end

    it "handles multi-line instructions" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.instructions = "Line 1\nLine 2\nLine 3"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, output_dir)

        content = File.read(File.join(output_dir, "llms.txt"))
        content.should contain("Line 1")
        content.should contain("Line 2")
        content.should contain("Line 3")
      end
    end
  end

  describe ".generate (with pages)" do
    it "generates both llms.txt and llms-full.txt when full_enabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.llms.instructions = "Site instructions"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Test content body"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)

        File.exists?(File.join(output_dir, "llms.txt")).should be_true
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_true
      end
    end

    it "does not generate llms-full.txt when full_enabled is false" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = false
      config.llms.instructions = "Instructions"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)

        File.exists?(File.join(output_dir, "llms.txt")).should be_true
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_false
      end
    end

    it "does not generate any files when llms is disabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = false
      config.llms.full_enabled = true

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)

        File.exists?(File.join(output_dir, "llms.txt")).should be_false
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_false
      end
    end

    it "uses custom full filename when configured" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.llms.full_filename = "ai-full.txt"
      config.llms.instructions = "Instructions"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)
        File.exists?(File.join(output_dir, "ai-full.txt")).should be_true
      end
    end

    it "defaults full filename to llms-full.txt when empty" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.llms.full_filename = ""
      config.llms.instructions = "Instructions"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate(config, [page], output_dir)
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_true
      end
    end
  end

  describe ".generate_full" do
    it "includes site title as heading" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "My Awesome Site"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("about.md")
      page.title = "About"
      page.url = "/about/"
      page.render = true
      page.raw_content = "About page content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should start_with("# My Awesome Site\n")
      end
    end

    it "includes site description when present" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.description = "A great testing site"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("A great testing site")
      end
    end

    it "includes base URL when present" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.base_url = "https://example.com"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Base URL: https://example.com")
      end
    end

    it "includes instructions when present" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = "Please respect the site's content policies."

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Please respect the site's content policies.")
      end
    end

    it "includes page title and content for each page" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page1 = Hwaro::Models::Page.new("about.md")
      page1.title = "About Us"
      page1.url = "/about/"
      page1.render = true
      page1.raw_content = "We are a test company."

      page2 = Hwaro::Models::Page.new("blog/post.md")
      page2.title = "First Blog Post"
      page2.url = "/blog/post/"
      page2.render = true
      page2.raw_content = "This is our first blog post."

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Title: About Us")
        content.should contain("We are a test company.")
        content.should contain("Title: First Blog Post")
        content.should contain("This is our first blog post.")
      end
    end

    it "includes source path for each page" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("blog/hello.md")
      page.title = "Hello"
      page.url = "/blog/hello/"
      page.render = true
      page.raw_content = "Hello content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Source: content/blog/hello.md")
      end
    end

    it "generates absolute URLs with base_url" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.base_url = "https://example.com"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("about.md")
      page.title = "About"
      page.url = "/about/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("URL: https://example.com/about/")
      end
    end

    it "handles base_url with trailing slash" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.base_url = "https://example.com/"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("about.md")
      page.title = "About"
      page.url = "/about/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("URL: https://example.com/about/")
      end
    end

    it "uses relative URL when base_url is empty" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.base_url = ""
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("about.md")
      page.title = "About"
      page.url = "/about/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("URL: /about/")
      end
    end

    it "excludes pages with render=false" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page1 = Hwaro::Models::Page.new("visible.md")
      page1.title = "Visible"
      page1.url = "/visible/"
      page1.render = true
      page1.raw_content = "Visible content"

      page2 = Hwaro::Models::Page.new("hidden.md")
      page2.title = "Hidden"
      page2.url = "/hidden/"
      page2.render = false
      page2.raw_content = "Hidden content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Title: Visible")
        content.should_not contain("Title: Hidden")
      end
    end

    it "excludes pages with empty raw_content" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page1 = Hwaro::Models::Page.new("with_content.md")
      page1.title = "With Content"
      page1.url = "/with-content/"
      page1.render = true
      page1.raw_content = "Has content"

      page2 = Hwaro::Models::Page.new("empty.md")
      page2.title = "Empty"
      page2.url = "/empty/"
      page2.render = true
      page2.raw_content = ""

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Title: With Content")
        content.should_not contain("Title: Empty")
      end
    end

    it "sorts pages by URL" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page_z = Hwaro::Models::Page.new("z.md")
      page_z.title = "Z Page"
      page_z.url = "/z/"
      page_z.render = true
      page_z.raw_content = "Z content"

      page_a = Hwaro::Models::Page.new("a.md")
      page_a.title = "A Page"
      page_a.url = "/a/"
      page_a.render = true
      page_a.raw_content = "A content"

      page_m = Hwaro::Models::Page.new("m.md")
      page_m.title = "M Page"
      page_m.url = "/m/"
      page_m.render = true
      page_m.raw_content = "M content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page_z, page_a, page_m], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        a_pos = content.index("Title: A Page").not_nil!
        m_pos = content.index("Title: M Page").not_nil!
        z_pos = content.index("Title: Z Page").not_nil!
        a_pos.should be < m_pos
        m_pos.should be < z_pos
      end
    end

    it "separates pages with --- delimiter" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page1 = Hwaro::Models::Page.new("first.md")
      page1.title = "First"
      page1.url = "/first/"
      page1.render = true
      page1.raw_content = "First content"

      page2 = Hwaro::Models::Page.new("second.md")
      page2.title = "Second"
      page2.url = "/second/"
      page2.render = true
      page2.raw_content = "Second content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page1, page2], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("---")
      end
    end

    it "ends with a trailing newline" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Test Site"
      config.llms.instructions = ""

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should end_with("\n")
      end
    end

    it "does not generate when disabled" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = false
      config.llms.full_enabled = true

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_false
      end
    end

    it "does not generate when full_enabled is false" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = false

      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.url = "/test/"
      page.render = true
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)
        File.exists?(File.join(output_dir, "llms-full.txt")).should be_false
      end
    end

    it "handles empty pages array" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Empty Site"
      config.llms.instructions = ""

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([] of Hwaro::Models::Page, config, output_dir)

        file_path = File.join(output_dir, "llms-full.txt")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("# Empty Site")
        content.should_not contain("Title:")
      end
    end

    it "includes language label for multilingual sites" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Multilingual Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.llms.instructions = ""

      page_en = Hwaro::Models::Page.new("about.md")
      page_en.title = "About"
      page_en.url = "/about/"
      page_en.language = "en"
      page_en.render = true
      page_en.raw_content = "English content"

      page_ko = Hwaro::Models::Page.new("about.ko.md")
      page_ko.title = "소개"
      page_ko.url = "/ko/about/"
      page_ko.language = "ko"
      page_ko.render = true
      page_ko.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page_en, page_ko], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should contain("Language: en")
        content.should contain("Language: ko")
      end
    end

    it "does not include language label for non-multilingual sites" do
      config = Hwaro::Models::Config.new
      config.llms.enabled = true
      config.llms.full_enabled = true
      config.title = "Single Language Site"
      config.default_language = "en"
      config.llms.instructions = ""
      # No additional languages configured

      page = Hwaro::Models::Page.new("about.md")
      page.title = "About"
      page.url = "/about/"
      page.render = true
      page.raw_content = "English content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Llms.generate_full([page], config, output_dir)

        content = File.read(File.join(output_dir, "llms-full.txt"))
        content.should_not contain("Language:")
      end
    end
  end
end

describe Hwaro::Models::LlmsConfig do
  it "has default values" do
    config = Hwaro::Models::LlmsConfig.new
    config.enabled.should eq(true)
    config.filename.should eq("llms.txt")
    config.instructions.should eq("")
    config.full_enabled.should eq(false)
    config.full_filename.should eq("llms-full.txt")
  end

  it "allows setting enabled" do
    config = Hwaro::Models::LlmsConfig.new
    config.enabled = true
    config.enabled.should eq(true)
  end

  it "allows setting custom filename" do
    config = Hwaro::Models::LlmsConfig.new
    config.filename = "custom.txt"
    config.filename.should eq("custom.txt")
  end

  it "allows setting instructions" do
    config = Hwaro::Models::LlmsConfig.new
    config.instructions = "Do not crawl private pages."
    config.instructions.should eq("Do not crawl private pages.")
  end

  it "allows setting full_enabled" do
    config = Hwaro::Models::LlmsConfig.new
    config.full_enabled = true
    config.full_enabled.should eq(true)
  end

  it "allows setting full_filename" do
    config = Hwaro::Models::LlmsConfig.new
    config.full_filename = "all-content.txt"
    config.full_filename.should eq("all-content.txt")
  end
end
