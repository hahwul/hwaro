require "../spec_helper"
require "../../src/services/server/server"

# Every serve prune deletes only what nothing in the current output still
# claims: a page output, an alias stub, a static or content-file copy, a
# generated output, or any file this pass wrote. The prunes used to guard
# against page outputs alone, and compared paths byte-for-byte while the
# filesystem (APFS, NTFS) folds case.

private def keep_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def keep_builder : Hwaro::Core::Build::Builder
  Hwaro::Services::Server.new.@builder
end

private def write_keep_site(taxonomy_name : String = "tags")
  File.write("config.toml", <<-TOML
    title = "Keep"
    base_url = "https://example.com"

    [[taxonomies]]
    name = "#{taxonomy_name}"
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
  File.write("templates/taxonomy.html", "<html><body>index</body></html>")
  File.write("templates/taxonomy_term.html", "<html><body>term</body></html>")
  File.write("content/posts/keep.md", "---\ntitle: Keep\n#{taxonomy_name}: [shared]\n---\nkeep")
  File.write("content/posts/tips.md", "---\ntitle: Tips\n#{taxonomy_name}: [shared, tips]\n---\ntips")
end

private def case_insensitive_fs? : Bool
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, "probe"), "")
    File.exists?(File.join(dir, "PROBE"))
  end
end

private def redirect_stub?(path : String) : Bool
  File.exists?(path) && File.read(path).includes?("/posts/tips/")
end

describe "serve prune keep-set" do
  it "keeps an alias stub that takes over a pruned term page (incremental)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_keep_site
        builder = keep_builder
        options = keep_options
        builder.run(options).should be_true
        File.exists?("public/tags/tips/index.html").should be_true

        File.write("content/posts/tips.md", "---\ntitle: Tips\ntags: [shared, howto]\naliases: [/tags/tips/]\n---\ntips")
        builder.run_incremental(["content/posts/tips.md"], options).should be_true

        redirect_stub?("public/tags/tips/index.html").should be_true
      end
    end
  end

  it "keeps an alias stub that takes over a pruned term page (full rebuild)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_keep_site
        builder = keep_builder
        options = keep_options
        builder.run(options).should be_true

        File.write("content/posts/tips.md", "---\ntitle: Tips\ntags: [shared, howto]\naliases: [/tags/tips/]\n---\ntips")
        builder.run(options).should be_true

        redirect_stub?("public/tags/tips/index.html").should be_true
      end
    end
  end

  it "keeps the static file a pruned term page was shadowing" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_keep_site
        FileUtils.mkdir_p("static/tags/tips")
        File.write("static/tags/tips/index.html", "STATIC")
        builder = keep_builder
        options = keep_options
        builder.run(options).should be_true

        File.write("content/posts/tips.md", "---\ntitle: Tips\ntags: [shared]\n---\ntips")
        builder.run_incremental(["content/posts/tips.md"], options).should be_true
        File.read("public/tags/tips/index.html").should eq("STATIC")

        File.write("content/posts/keep.md", "---\ntitle: Keep again\ntags: [shared]\n---\nkeep")
        builder.run(options).should be_true
        File.read("public/tags/tips/index.html").should eq("STATIC")
      end
    end
  end

  it "keeps the static file a page that stopped rendering was shadowing" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_keep_site
        FileUtils.mkdir_p("static/posts/keep")
        File.write("static/posts/keep/index.html", "STATIC")
        builder = keep_builder
        options = keep_options
        builder.run(options).should be_true
        File.read("public/posts/keep/index.html").should_not eq("STATIC")

        File.write("content/posts/keep.md", "---\ntitle: Keep\nrender: false\ntags: [shared]\n---\nkeep")
        builder.run_incremental(["content/posts/keep.md"], options).should be_true

        File.read("public/posts/keep/index.html").should eq("STATIC")
      end
    end
  end

  it "keeps an alias whose case changed (case-insensitive filesystems)" do
    pending!("case-sensitive filesystem") unless case_insensitive_fs?
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_keep_site
        File.write("content/posts/tips.md", "---\ntitle: Tips\ntags: [shared]\naliases: [/Old/]\n---\ntips")
        builder = keep_builder
        options = keep_options
        builder.run(options).should be_true

        File.write("content/posts/tips.md", "---\ntitle: Tips\ntags: [shared]\naliases: [/old/]\n---\ntips")
        builder.run_incremental(["content/posts/tips.md"], options).should be_true
        redirect_stub?("public/old/index.html").should be_true

        File.write("content/posts/tips.md", "---\ntitle: Tips\ntags: [shared]\naliases: [/OLD/]\n---\ntips")
        builder.run(options).should be_true
        redirect_stub?("public/OLD/index.html").should be_true
      end
    end
  end

  it "keeps the term pages of a taxonomy whose name changed case (case-insensitive filesystems)" do
    pending!("case-sensitive filesystem") unless case_insensitive_fs?
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_keep_site("Tags")
        builder = keep_builder
        options = keep_options
        builder.run(options).should be_true

        write_keep_site("tags")
        builder.run(options).should be_true
        File.exists?("public/tags/shared/index.html").should be_true
        File.exists?("public/tags/index.html").should be_true
      end
    end
  end
end
