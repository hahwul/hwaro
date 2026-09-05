require "../../spec_helper"

# =============================================================================
# Sharded search index: `[search] shards`, `single_file`, `content_max_length`.
#
# Contract: with `shards = "none"` (default) the generator emits exactly what
# it always did — `search.json` and no `search/` directory. Any other mode
# adds `search/index.json` (manifest) plus one `search/<id>.json` per shard,
# each carrying the same entry schema as `search.json`.
# =============================================================================

private def shard_config(shards : String = "section", fields = ["title", "content", "section"]) : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.search.enabled = true
  config.search.fields = fields
  config.search.shards = shards
  config
end

private def shard_page(path : String, title : String, url : String, section : String, body : String = "Body text", language : String? = nil) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.title = title
  page.url = url
  page.section = section
  page.draft = false
  page.raw_content = body
  page.language = language
  page
end

private def sample_pages : Array(Hwaro::Models::Page)
  [
    shard_page("blog/second.md", "Second", "/blog/second/", "blog"),
    shard_page("about.md", "About", "/about/", ""),
    shard_page("blog/news/first.md", "First", "/blog/news/first/", "blog/news"),
    shard_page("docs/intro.md", "Intro", "/docs/intro/", "docs"),
  ]
end

private def load_search_config(toml : String) : Hwaro::Models::Config
  Dir.mktmpdir do |dir|
    path = File.join(dir, "config.toml")
    File.write(path, toml)
    return Hwaro::Models::Config.load(path)
  end
  raise "unreachable"
end

private def read_manifest(output_dir : String) : JSON::Any
  JSON.parse(File.read(File.join(output_dir, "search", "index.json")))
end

private def multilingual_config(shards : String) : Hwaro::Models::Config
  config = shard_config(shards)
  config.default_language = "en"
  config.languages["en"] = Hwaro::Models::LanguageConfig.new("en")
  config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
  config
end

private def multilingual_pages : Array(Hwaro::Models::Page)
  [
    shard_page("blog/post.md", "Post", "/blog/post/", "blog"),
    shard_page("blog/post.ko.md", "포스트", "/ko/blog/post/", "blog", language: "ko"),
    shard_page("index.md", "Home", "/", ""),
    shard_page("index.ko.md", "홈", "/ko/", "", language: "ko"),
  ]
end

describe "Hwaro::Content::Search shards" do
  describe "shards = \"none\" (default)" do
    it "emits only the classic search.json and no search/ directory" do
      config = shard_config("none")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        File.exists?(File.join(odir, "search.json")).should be_true
        Dir.exists?(File.join(odir, "search")).should be_false
      end
    end

    it "ignores single_file = false when sharding is off" do
      config = shard_config("none")
      config.search.single_file = false
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        File.exists?(File.join(odir, "search.json")).should be_true
      end
    end
  end

  describe "shards = \"section\"" do
    it "writes one shard per top-level section, root pages to _root, plus a manifest" do
      config = shard_config("section")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)

        Dir.glob(File.join(odir, "search", "**", "*.json")).map { |p| p[(odir.size + 1)..] }.sort!.should eq([
          "search/_root.json", "search/blog.json", "search/docs.json", "search/index.json",
        ])

        # Nested `blog/news` folds into the top-level `blog` shard, in the
        # same order search.json lists the pages.
        blog = JSON.parse(File.read(File.join(odir, "search", "blog.json"))).as_a
        blog.map(&.["title"].as_s).should eq(["Second", "First"])
        blog.each(&.["url"].as_s.should(start_with("/blog/")))
        JSON.parse(File.read(File.join(odir, "search", "_root.json"))).as_a.map(&.["url"].as_s).should eq(["/about/"])

        manifest = read_manifest(odir)
        manifest["version"].as_i.should eq(1)
        manifest["fields"].as_a.map(&.as_s).should eq(["title", "content", "section", "url", "lang"])
        shards = manifest["shards"].as_a
        shards.map(&.["id"].as_s).should eq(["_root", "blog", "docs"])
        shards.map(&.["url"].as_s).should eq(["/search/_root.json", "/search/blog.json", "/search/docs.json"])
        shards.map(&.["count"].as_i).should eq([1, 2, 1])
        shards.map(&.["section"].as_s).should eq(["", "blog", "docs"])
        shards.each(&.["language"].raw.should(be_nil))
        shards.each do |s|
          s["bytes"].as_i.should eq(File.size(File.join(odir, "search", "#{s["id"].as_s}.json")))
        end
      end
    end

    it "keeps the classic search.json alongside the shards by default" do
      config = shard_config("section")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        classic = JSON.parse(File.read(File.join(odir, "search.json"))).as_a
        classic.size.should eq(4)
        # Shard entries carry exactly the same schema as the classic file.
        shard_entry = JSON.parse(File.read(File.join(odir, "search", "docs.json"))).as_a.first
        classic.find! { |e| e["url"].as_s == "/docs/intro/" }.should eq(shard_entry)
      end
    end

    it "drops search.json when single_file = false" do
      config = shard_config("section")
      config.search.single_file = false
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        File.exists?(File.join(odir, "search.json")).should be_false
        File.exists?(File.join(odir, "search", "index.json")).should be_true
      end
    end

    it "applies the same eligibility and exclude filters as search.json" do
      config = shard_config("section")
      config.search.exclude = ["/docs"]
      pages = sample_pages
      draft = shard_page("blog/draft.md", "Draft", "/blog/draft/", "blog")
      draft.draft = true
      opted_out = shard_page("blog/private.md", "Private", "/blog/private/", "blog")
      opted_out.in_search_index = false
      pages << draft << opted_out
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(pages, config, odir)
        manifest = read_manifest(odir)
        manifest["shards"].as_a.map(&.["id"].as_s).should eq(["_root", "blog"])
        blog = File.read(File.join(odir, "search", "blog.json"))
        blog.should_not contain("Draft")
        blog.should_not contain("Private")
      end
    end

    it "prefixes manifest URLs with base_path on subpath deploys" do
      config = shard_config("section")
      config.base_url = "https://example.com/sub"
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        urls = read_manifest(odir)["shards"].as_a.map(&.["url"].as_s)
        urls.should eq(["/sub/search/_root.json", "/sub/search/blog.json", "/sub/search/docs.json"])
        # Entry URLs inside the shards are prefixed too (same as search.json).
        JSON.parse(File.read(File.join(odir, "search", "blog.json"))).as_a.first["url"].as_s.should eq("/sub/blog/second/")
        # But the files stay at their un-prefixed output paths.
        File.exists?(File.join(odir, "search", "blog.json")).should be_true
      end
    end

    it "percent-encodes a section name in the manifest URL but not the file path" do
      config = shard_config("section")
      pages = [shard_page("my docs/a.md", "A", "/my-docs/a/", "my docs")]
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(pages, config, odir)
        File.exists?(File.join(odir, "search", "my docs.json")).should be_true
        read_manifest(odir)["shards"].as_a.first["url"].as_s.should eq("/search/my%20docs.json")
      end
    end

    it "is deterministic across runs and page order" do
      config = shard_config("section")
      Dir.mktmpdir do |a|
        Dir.mktmpdir do |b|
          Hwaro::Content::Search.generate(sample_pages, config, a)
          Hwaro::Content::Search.generate(sample_pages.reverse, config, b)
          # The manifest never depends on the page order the build hands over.
          File.read(File.join(a, "search", "index.json")).should eq(File.read(File.join(b, "search", "index.json")))
          Hwaro::Content::Search.generate(sample_pages, config, b)
          Dir.glob(File.join(a, "search", "**", "*.json")).each do |path|
            File.read(path).should eq(File.read(path.sub(a, b)))
          end
        end
      end
    end

    it "prunes shards listed by the previous manifest that this build did not write" do
      config = shard_config("section")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        File.exists?(File.join(odir, "search", "docs.json")).should be_true
        # A user file under search/ that our manifest never listed survives.
        File.write(File.join(odir, "search", "custom.json"), "{}")

        Hwaro::Content::Search.generate(sample_pages.reject { |p| p.section == "docs" }, config, odir)
        File.exists?(File.join(odir, "search", "docs.json")).should be_false
        File.exists?(File.join(odir, "search", "custom.json")).should be_true
        read_manifest(odir)["shards"].as_a.map(&.["id"].as_s).should eq(["_root", "blog"])
      end
    end

    it "writes an empty manifest and prunes stale shards when no page is eligible" do
      config = shard_config("section")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        Hwaro::Content::Search.generate([] of Hwaro::Models::Page, config, odir)
        read_manifest(odir)["shards"].as_a.should be_empty
        Dir.glob(File.join(odir, "search", "*.json")).map { |p| File.basename(p) }.should eq(["index.json"])
      end
    end

    it "honors skip_if_unchanged only when every expected file is present" do
      config = shard_config("section")
      Dir.mktmpdir do |odir|
        # Classic file present but no manifest yet → must generate the shards.
        File.write(File.join(odir, "search.json"), "[]")
        Hwaro::Content::Search.generate(sample_pages, config, odir, skip_if_unchanged: true)
        File.exists?(File.join(odir, "search", "index.json")).should be_true
        File.read(File.join(odir, "search.json")).should_not eq("[]")

        # Everything present → skipped (the sentinel survives).
        File.write(File.join(odir, "search.json"), "[]")
        Hwaro::Content::Search.generate(sample_pages, config, odir, skip_if_unchanged: true)
        File.read(File.join(odir, "search.json")).should eq("[]")
      end
    end

    it "emits plain JSON shards even for the *_javascript formats" do
      config = shard_config("section")
      config.search.format = "fuse_javascript"
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(sample_pages, config, odir)
        File.read(File.join(odir, "search.json")).should start_with("var searchData = ")
        File.read(File.join(odir, "search", "blog.json")).should start_with("[{")
      end
    end
  end

  describe "shards = \"language\"" do
    it "writes one shard per language, default language pages under its code" do
      config = multilingual_config("language")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(multilingual_pages, config, odir)
        shards = read_manifest(odir)["shards"].as_a
        shards.map(&.["id"].as_s).should eq(["en", "ko"])
        shards.map(&.["language"].as_s).should eq(["en", "ko"])
        shards.each(&.["section"].raw.should(be_nil))
        shards.map(&.["count"].as_i).should eq([2, 2])
        JSON.parse(File.read(File.join(odir, "search", "ko.json"))).as_a.each(&.["lang"].as_s.should(eq("ko")))
        JSON.parse(File.read(File.join(odir, "search", "en.json"))).as_a.each(&.["lang"].as_s.should(eq("en")))
      end
    end

    it "excludes a language that opted odir via build_search_index = false" do
      config = multilingual_config("language")
      config.languages["ko"].build_search_index = false
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(multilingual_pages, config, odir)
        read_manifest(odir)["shards"].as_a.map(&.["id"].as_s).should eq(["en"])
        File.exists?(File.join(odir, "search", "ko.json")).should be_false
        File.read(File.join(odir, "search.json")).should_not contain("/ko/")
      end
    end
  end

  describe "shards = \"section-language\"" do
    it "nests section shards under the language code" do
      config = multilingual_config("section-language")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(multilingual_pages, config, odir)
        shards = read_manifest(odir)["shards"].as_a
        shards.map(&.["id"].as_s).should eq(["en/_root", "en/blog", "ko/_root", "ko/blog"])
        shards.map(&.["url"].as_s).should eq(["/search/en/_root.json", "/search/en/blog.json", "/search/ko/_root.json", "/search/ko/blog.json"])
        shards.map { |s| {s["language"].as_s, s["section"].as_s} }.should eq([{"en", ""}, {"en", "blog"}, {"ko", ""}, {"ko", "blog"}])
        File.exists?(File.join(odir, "search", "ko", "blog.json")).should be_true
        JSON.parse(File.read(File.join(odir, "search", "ko", "blog.json"))).as_a.map(&.["title"].as_s).should eq(["포스트"])
      end
    end

    it "removes an emptied nested id directory when a language shard goes away" do
      config = multilingual_config("section-language")
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(multilingual_pages, config, odir)
        Dir.exists?(File.join(odir, "search", "ko")).should be_true
        Hwaro::Content::Search.generate(multilingual_pages.reject { |p| p.language == "ko" }, config, odir)
        Dir.exists?(File.join(odir, "search", "ko")).should be_false
        read_manifest(odir)["shards"].as_a.map(&.["id"].as_s).should eq(["en/_root", "en/blog"])
      end
    end
  end

  describe "content_max_length" do
    it "leaves content untouched at 0" do
      config = shard_config("none")
      pages = [shard_page("a.md", "A", "/a/", "", body: "one two three four five six")]
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(pages, config, odir)
        JSON.parse(File.read(File.join(odir, "search.json"))).as_a.first["content"].as_s.should eq("one two three four five six")
      end
    end

    it "truncates content at a word boundary in search.json and in every shard" do
      config = shard_config("section")
      config.search.content_max_length = 12
      pages = [shard_page("blog/a.md", "A", "/blog/a/", "blog", body: "one two three four five six")]
      Dir.mktmpdir do |odir|
        Hwaro::Content::Search.generate(pages, config, odir)
        JSON.parse(File.read(File.join(odir, "search.json"))).as_a.first["content"].as_s.should eq("one two")
        JSON.parse(File.read(File.join(odir, "search", "blog.json"))).as_a.first["content"].as_s.should eq("one two")
      end
    end

    it "does not truncate a content field already within the limit" do
      Hwaro::Content::Search.truncate_words("short text", 10).should eq("short text")
      Hwaro::Content::Search.truncate_words("short text", 100).should eq("short text")
    end

    it "cuts hard when the prefix holds no whitespace" do
      Hwaro::Content::Search.truncate_words("abcdefghijklmnop", 5).should eq("abcde")
      Hwaro::Content::Search.truncate_words("abcdefghij klm", 5).should eq("abcde")
    end

    it "keeps a word that ends exactly at the limit" do
      Hwaro::Content::Search.truncate_words("hello world", 5).should eq("hello")
      Hwaro::Content::Search.truncate_words("hello world", 6).should eq("hello")
    end

    it "counts characters, not bytes" do
      Hwaro::Content::Search.truncate_words("한국어 검색 인덱스", 6).should eq("한국어 검색")
    end
  end

  describe "config loading" do
    it "defaults to shards = none, single_file = true, content_max_length = 0" do
      config = load_search_config("title = \"T\"\nbase_url = \"http://x\"\n[search]\nenabled = true\n")
      config.search.shards.should eq("none")
      config.search.sharded?.should be_false
      config.search.single_file.should be_true
      config.search.content_max_length.should eq(0)
    end

    it "reads every shard mode plus single_file and content_max_length" do
      %w[section language section-language].each do |mode|
        config = load_search_config("title = \"T\"\nbase_url = \"http://x\"\n[search]\nenabled = true\nshards = \"#{mode}\"\nsingle_file = false\ncontent_max_length = 200\n")
        config.search.shards.should eq(mode)
        config.search.sharded?.should be_true
        config.search.single_file.should be_false
        config.search.content_max_length.should eq(200)
      end
    end

    it "falls back to none on an unknown shards value and to 0 on a negative length" do
      config = load_search_config("title = \"T\"\nbase_url = \"http://x\"\n[search]\nenabled = true\nshards = \"sections\"\ncontent_max_length = -5\n")
      config.search.shards.should eq("none")
      config.search.content_max_length.should eq(0)
    end
  end
end
