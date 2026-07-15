require "../../spec_helper"

describe Hwaro::Services::Exporters::JekyllExporter do
  describe "#run" do
    it "returns failure when no content files found" do
      exporter = Hwaro::Services::Exporters::JekyllExporter.new
      options = Hwaro::Config::Options::ExportOptions.new(
        target_type: "jekyll",
        content_dir: "/nonexistent/content",
        output_dir: "/tmp/export",
      )
      result = exporter.run(options)
      result.success.should be_false
    end

    it "exports with YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "post.md"), "+++\ntitle = \"My Post\"\ndate = \"2024-01-15\"\ndescription = \"A post\"\ntags = [\"crystal\"]\n+++\n\nHello world\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        result = exporter.run(options)

        result.success.should be_true
        result.exported_count.should eq(1)

        # Should be in _posts with date prefix
        posts_dir = File.join(output_dir, "_posts")
        Dir.exists?(posts_dir).should be_true

        files = Dir.glob(File.join(posts_dir, "*.md"))
        files.size.should eq(1)

        content = File.read(files.first)
        content.should contain("---")
        content.should contain("title:")
        content.should_not contain("+++")
      end
    end

    it "uses date-prefixed filenames for posts" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "my-post.md"), "+++\ntitle = \"My Post\"\ndate = \"2024-03-15\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        exporter.run(options)

        File.exists?(File.join(output_dir, "_posts", "2024-03-15-my-post.md")).should be_true
      end
    end

    it "converts draft to published: false" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\ndate = \"2024-01-01\"\n+++\n\nDraft content\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
          drafts: true,
        )
        exporter.run(options)

        # Drafts go to _drafts directory
        drafts_dir = File.join(output_dir, "_drafts")
        Dir.exists?(drafts_dir).should be_true
        files = Dir.glob(File.join(drafts_dir, "*.md"))
        files.size.should eq(1)

        content = File.read(files.first)
        content.should contain("published: false")
      end
    end

    it "skips drafts by default" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\n+++\n\nDraft\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
          drafts: false,
        )
        result = exporter.run(options)

        result.skipped_count.should eq(1)
        result.exported_count.should eq(0)
      end
    end

    it "exports section index files as pages" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "about"))

        File.write(File.join(content_dir, "about", "_index.md"), "+++\ntitle = \"About\"\n+++\n\nAbout page\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(
          target_type: "jekyll",
          content_dir: content_dir,
          output_dir: output_dir,
        )
        exporter.run(options)

        File.exists?(File.join(output_dir, "about", "index.md")).should be_true
      end
    end

    it "treats files without a date as plain Jekyll pages (root, not _posts)" do
      # Jekyll's `_posts/` is for dated blog posts. A non-dated file like
      # `about.md` is a regular page — putting it under `_posts/` would
      # bury it in the post feed and require Jekyll-side workarounds.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "about.md"), "+++\ntitle = \"About\"\n+++\n\nAbout page\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "about.md")).should be_true
        Dir.exists?(File.join(output_dir, "_posts")).should be_false
      end
    end

    it "treats short/invalid date strings as plain pages too" do
      # A `date = \"2024\"` isn't a valid ISO date, so we can't safely place
      # it under `_posts/<YYYY-MM-DD>-…`. Falling back to a plain page is
      # safer than emitting a malformed Jekyll filename.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "short-date.md"), "+++\ntitle = \"Post\"\ndate = \"2024\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)

        result.exported_count.should eq(1)
        File.exists?(File.join(output_dir, "short-date.md")).should be_true
      end
    end

    it "converts YAML frontmatter to YAML" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "yaml.md"), "---\ntitle: YAML Post\ndate: \"2024-05-20\"\ntags:\n  - ruby\n---\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)

        result.exported_count.should eq(1)
        content = File.read(File.join(output_dir, "_posts", "2024-05-20-yaml.md"))
        content.should contain("---")
        content.should contain("title:")
        content.should contain("- ruby")
      end
    end

    it "removes date prefix from draft filenames" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "draft.md"), "+++\ntitle = \"Draft\"\ndraft = true\ndate = \"2024-06-15\"\n+++\n\nDraft\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir, drafts: true)
        exporter.run(options)

        # Draft should not have date prefix
        File.exists?(File.join(output_dir, "_drafts", "draft.md")).should be_true
        File.exists?(File.join(output_dir, "_drafts", "2024-06-15-draft.md")).should be_false
      end
    end

    it "flattens dated posts from subdirectories into _posts/ root" do
      # Jekyll reads subdirectories under `_posts/` as category hints, so
      # nesting `content/posts/foo.md` under `_posts/posts/foo.md` would
      # spuriously tag every post with a `posts` category. We drop the
      # source subdir and write a flat `_posts/<date>-<slug>.md`.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "blog"))

        File.write(File.join(content_dir, "blog", "post.md"), "+++\ntitle = \"Blog Post\"\ndate = \"2024-03-10\"\n+++\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "_posts", "2024-03-10-post.md")).should be_true
        Dir.exists?(File.join(output_dir, "_posts", "blog")).should be_false
      end
    end

    it "rewrites @/ internal links" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\n+++\n\n[About](@/about/_index.md)\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        files = Dir.glob(File.join(output_dir, "_posts", "*.md"))
        content = File.read(files.first)
        content.should_not contain("@/")
      end
    end

    it "includes categories in YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "post.md"), "---\ntitle: Post\ndate: \"2024-01-01\"\ncategories:\n  - tech\n  - blog\n---\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        files = Dir.glob(File.join(output_dir, "_posts", "*.md"))
        content = File.read(files.first)
        content.should contain("categories:")
        content.should contain("- tech")
      end
    end

    it "preserves a scalar tags/categories shorthand as a single-item list" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        # `tags: crystal` (scalar, not a list) must not be silently dropped —
        # that would lose the post's taxonomy membership in the migration.
        File.write(File.join(content_dir, "posts", "post.md"), "---\ntitle: Post\ndate: \"2024-01-01\"\ntags: crystal\ncategories: news\n---\n\nBody\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)
        result.success.should be_true

        content = File.read(Dir.glob(File.join(output_dir, "_posts", "*.md")).first)
        content.should contain("tags:")
        content.should contain("- crystal")
        content.should contain("categories:")
        content.should contain("- news")
      end
    end

    it "includes authors in YAML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "post.md"), "---\ntitle: Post\ndate: \"2024-01-01\"\nauthors:\n  - Jane\n  - John\n---\n\nContent\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        files = Dir.glob(File.join(output_dir, "_posts", "*.md"))
        content = File.read(files.first)
        content.should contain("authors:")
        content.should contain("- Jane")
      end
    end

    it "keeps dated pages outside posts/blog sections as tree-preserved pages" do
      # Hwaro auto-stamps `date` on every `hwaro new` page, so a date alone
      # must not turn `about-us.md` or `team/engineering/deep-page.md` into
      # a flat `_posts/` entry — that discards their section identity.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "team", "engineering"))

        File.write(File.join(content_dir, "about-us.md"), "+++\ntitle = \"About Us\"\ndate = \"2024-01-01\"\n+++\n\nAbout\n")
        File.write(File.join(content_dir, "team", "engineering", "deep-page.md"), "+++\ntitle = \"Deep\"\ndate = \"2024-01-02\"\n+++\n\nDeep\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "about-us.md")).should be_true
        File.exists?(File.join(output_dir, "team", "engineering", "deep-page.md")).should be_true
        Dir.exists?(File.join(output_dir, "_posts")).should be_false
      end
    end

    it "uses the bundle directory as the slug for leaf-bundle posts" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts", "bundled-post"))

        File.write(File.join(content_dir, "posts", "bundled-post", "index.md"), "+++\ntitle = \"Bundled\"\ndate = \"2024-04-01\"\n+++\n\nBody\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "_posts", "2024-04-01-bundled-post.md")).should be_true
        File.exists?(File.join(output_dir, "_posts", "2024-04-01-index.md")).should be_false
      end
    end

    it "disambiguates colliding destinations instead of overwriting" do
      # Two same-day leaf bundles with identical directory names in nested
      # subsections both flatten to the same `_posts/<date>-<slug>.md` —
      # the second must not silently clobber the first.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts", "a", "launch"))
        FileUtils.mkdir_p(File.join(content_dir, "posts", "b", "launch"))

        File.write(File.join(content_dir, "posts", "a", "launch", "index.md"), "+++\ntitle = \"Launch A\"\ndate = \"2024-05-01\"\n+++\n\nA\n")
        File.write(File.join(content_dir, "posts", "b", "launch", "index.md"), "+++\ntitle = \"Launch B\"\ndate = \"2024-05-01\"\n+++\n\nB\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)

        result.exported_count.should eq(2)
        written = Dir.glob(File.join(output_dir, "_posts", "*.md")).sort
        written.size.should eq(2)
        contents = written.map { |f| File.read(f) }.join
        contents.should contain("Launch A")
        contents.should contain("Launch B")
      end
    end

    it "sends undated drafts in a posts section to _drafts" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "wip.md"), "+++\ntitle = \"WIP\"\ndraft = true\n+++\n\nWip\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir, drafts: true)
        exporter.run(options)

        File.exists?(File.join(output_dir, "_drafts", "wip.md")).should be_true
      end
    end

    it "maps the site root _index.md to index.md, not index/index.md" do
      # `index/index.md` is served at `/index/`, leaving the site root empty.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "_index.md"), "+++\ntitle = \"Home\"\n+++\n\nWelcome\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "index.md")).should be_true
        File.exists?(File.join(output_dir, "index", "index.md")).should be_false
      end
    end

    it "quotes list items and images that YAML would reinterpret" do
      # `- beta: gamma` reparses as a mapping and `- NO` as boolean false
      # under Jekyll's YAML 1.1 loader.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\ntags = [\"beta: gamma\", \"NO\", \"plain\"]\nimage = \"a: b.png\"\n+++\n\nBody\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        content = File.read(Dir.glob(File.join(output_dir, "_posts", "*.md")).first)
        content.should contain(%(- "beta: gamma"))
        content.should contain(%(- "NO"))
        content.should contain("- plain")
        content.should contain(%(image: "a: b.png"))

        # The emitted frontmatter must reparse to the original values.
        fm = content.match!(/\A---\n(.*?)\n---/m)[1]
        parsed = YAML.parse(fm)
        parsed["tags"].as_a.map(&.as_s).should eq(["beta: gamma", "NO", "plain"])
      end
    end

    it "passes through custom keys and nested extra instead of dropping them" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "post.md"), "+++\ntitle = \"Post\"\ndate = \"2024-01-01\"\nslug = \"custom-slug\"\nweight = 3\n[extra]\nsubtitle = \"hi\"\n+++\n\nBody\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        content = File.read(Dir.glob(File.join(output_dir, "_posts", "*.md")).first)
        fm = content.match!(/\A---\n(.*?)\n---/m)[1]
        parsed = YAML.parse(fm)
        parsed["slug"].should eq("custom-slug")
        parsed["weight"].should eq(3)
        parsed["extra"]["subtitle"].should eq("hi")
      end
    end

    it "does not double the date prefix for already-prefixed sources" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))

        File.write(File.join(content_dir, "posts", "2024-01-15-hello.md"), "+++\ntitle = \"Hello\"\ndate = \"2024-01-15\"\n+++\n\nBody\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        exporter.run(options)

        File.exists?(File.join(output_dir, "_posts", "2024-01-15-hello.md")).should be_true
        File.exists?(File.join(output_dir, "_posts", "2024-01-15-2024-01-15-hello.md")).should be_false
      end
    end

    it "counts files with malformed frontmatter as errors instead of stripping metadata" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad.md"), "+++\nnot valid toml = =\n+++\n\nBody\n")

        exporter = Hwaro::Services::Exporters::JekyllExporter.new
        options = Hwaro::Config::Options::ExportOptions.new(target_type: "jekyll", content_dir: content_dir, output_dir: output_dir)
        result = exporter.run(options)

        result.error_count.should eq(1)
        result.exported_count.should eq(0)
        Dir.glob(File.join(output_dir, "**", "*.md")).should be_empty
      end
    end
  end
end
