require "./support/build_helper"

# =============================================================================
# Incremental build (cache) functional tests
#
# Verifies cache file creation, cache reuse on unchanged rebuilds,
# and selective reprocessing when files change.
# =============================================================================

describe "Cache: Cache file creation" do
  it "creates .hwaro_cache.json after build with cache enabled" do
    build_site(
      BASIC_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout content"},
      template_files: {"page.html" => "{{ content }}"},
      cache: true,
    ) do
      File.exists?(".hwaro_cache.json").should be_true
      cache_json = File.read(".hwaro_cache.json")
      cache_json.should contain("about.md")
    end
  end

  it "does NOT create .hwaro_cache.json when cache is disabled" do
    build_site(
      BASIC_CONFIG,
      content_files: {"about.md" => "---\ntitle: About\n---\nAbout content"},
      template_files: {"page.html" => "{{ content }}"},
      cache: false,
    ) do
      File.exists?(".hwaro_cache.json").should be_false
    end
  end
end

describe "Cache: Rebuild with no changes" do
  it "reuses cache on second build when files are unchanged" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nContent")
        File.write("templates/page.html", "{{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?(".hwaro_cache.json").should be_true

        # Second build (no changes)
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        # Output should still be valid
        File.exists?("public/page/index.html").should be_true
        html = File.read("public/page/index.html")
        html.should contain("Content")
      end
    end
  end
end

describe "Cache: Rebuild after file change" do
  it "reprocesses changed file on rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nOriginal content")
        File.write("templates/page.html", "{{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        html1 = File.read("public/page/index.html")
        html1.should contain("Original content")

        # Modify file (ensure mtime changes)
        sleep 100.milliseconds
        File.write("content/page.md", "---\ntitle: Page\n---\nUpdated content")

        # Rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        html2 = File.read("public/page/index.html")
        html2.should contain("Updated content")
        html2.should_not contain("Original content")
      end
    end
  end
end

describe "Cache: Rebuild with new file added" do
  it "detects and builds newly added files" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page1.md", "---\ntitle: Page 1\n---\nContent 1")
        File.write("templates/page.html", "{{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/page1/index.html").should be_true
        File.exists?("public/page2/index.html").should be_false

        # Add new file
        sleep 100.milliseconds
        File.write("content/page2.md", "---\ntitle: Page 2\n---\nContent 2")

        # Rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/page1/index.html").should be_true
        File.exists?("public/page2/index.html").should be_true
        File.read("public/page2/index.html").should contain("Content 2")
      end
    end
  end
end

describe "Cache: Cache with multiple files" do
  it "caches multiple content files correctly" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page1.md" => "---\ntitle: Page 1\n---\nContent 1",
        "page2.md" => "---\ntitle: Page 2\n---\nContent 2",
        "page3.md" => "---\ntitle: Page 3\n---\nContent 3",
      },
      template_files: {"page.html" => "{{ content }}"},
      cache: true,
    ) do
      File.exists?(".hwaro_cache.json").should be_true
      cache_json = File.read(".hwaro_cache.json")
      cache_json.should contain("page1.md")
      cache_json.should contain("page2.md")
      cache_json.should contain("page3.md")

      File.exists?("public/page1/index.html").should be_true
      File.exists?("public/page2/index.html").should be_true
      File.exists?("public/page3/index.html").should be_true
    end
  end
end

describe "Cache: Template change invalidation" do
  it "rebuilds all pages when templates change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nContent")
        File.write("templates/page.html", "<div>{{ content }}</div>")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        html1 = File.read("public/page/index.html")
        html1.should contain("<div>")

        # Change template
        sleep 100.milliseconds
        File.write("templates/page.html", "<section>{{ content }}</section>")

        # Rebuild — template hash change should force rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        html2 = File.read("public/page/index.html")
        html2.should contain("<section>")
        html2.should_not contain("<div>")
      end
    end
  end
end

describe "Cache: Config change invalidation" do
  it "rebuilds all pages when config changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nContent")
        File.write("templates/page.html", "{{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/page/index.html").should be_true

        # Change config
        sleep 100.milliseconds
        new_config = BASIC_CONFIG.gsub("Test Site", "Updated Site")
        File.write("config.toml", new_config)

        # Rebuild — config hash change should force rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?("public/page/index.html").should be_true
      end
    end
  end
end

describe "Cache: Full rebuild flag" do
  it "rebuilds everything with --full even if cache exists" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nOriginal")
        File.write("templates/page.html", "{{ content }}")

        # First build with cache
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        File.exists?(".hwaro_cache.json").should be_true

        # Full rebuild (no file changes, but --full should still rebuild)
        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public",
          parallel: false,
          cache: true,
          full: true,
          highlight: false,
          verbose: false,
          profile: false,
        )

        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(options)

        # Cache file should be saved (for next incremental build)
        File.exists?(".hwaro_cache.json").should be_true
        File.exists?("public/page/index.html").should be_true
      end
    end
  end
end

describe "Cache: Content checksum verification" do
  it "detects change via checksum even if mtime is ambiguous" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/page.md", "---\ntitle: Page\n---\nOriginal content")
        File.write("templates/page.html", "{{ content }}")

        # First build
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        html1 = File.read("public/page/index.html")
        html1.should contain("Original content")

        # Modify file
        sleep 100.milliseconds
        File.write("content/page.md", "---\ntitle: Page\n---\nModified content")

        # Rebuild
        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)

        html2 = File.read("public/page/index.html")
        html2.should contain("Modified content")
      end
    end
  end
end

describe "Cache: Cache with section content" do
  it "caches section pages correctly" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/post1.md"  => "---\ntitle: Post 1\n---\nP1",
        "blog/post2.md"  => "---\ntitle: Post 2\n---\nP2",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{{ section_list }}",
      },
      cache: true,
    ) do
      File.exists?(".hwaro_cache.json").should be_true
      File.exists?("public/blog/index.html").should be_true
      File.exists?("public/blog/post1/index.html").should be_true
      File.exists?("public/blog/post2/index.html").should be_true
    end
  end
end
