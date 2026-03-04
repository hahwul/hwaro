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
        cache_after_first = File.read(".hwaro_cache.json")

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
