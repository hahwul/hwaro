require "../spec_helper"

# `tool list` / `tool stats` used to call every non-draft file "published",
# while `hwaro build` also drops future-dated pages, expired pages, and pages
# a parent section marked draft via `[cascade]`. The two answers disagreed on
# exactly the files an author is most likely to be asking about.
describe "tool publication-state parity" do
  describe Hwaro::Services::ContentLister do
    it "reports a future-dated page as future, not published" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "future.md"), "+++\ntitle = \"Later\"\ndate = 2999-01-01\n+++\n\nBody\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        all = lister.list_content(Hwaro::Services::ContentFilter::All)
        all.size.should eq(1)
        all.first.status.should eq("future")
        all.first.published?.should be_false
        all.first.draft.should be_false

        lister.list_content(Hwaro::Services::ContentFilter::Published).should be_empty
      end
    end

    it "reports an expired page as expired, not published" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "old.md"),
          "+++\ntitle = \"Old\"\ndate = 2020-01-01\nexpires = 2021-01-01\n+++\n\nBody\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        all = lister.list_content(Hwaro::Services::ContentFilter::All)
        all.first.status.should eq("expired")
        lister.list_content(Hwaro::Services::ContentFilter::Published).should be_empty
      end
    end

    it "honours a section's [cascade] draft on its descendants but not on itself" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        section = File.join(content_dir, "hidden")
        FileUtils.mkdir_p(section)
        File.write(File.join(section, "_index.md"),
          "+++\ntitle = \"Hidden\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(section, "child.md"), "+++\ntitle = \"Child\"\n+++\n\nBody\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        by_path = lister.list_content(Hwaro::Services::ContentFilter::All).to_h { |i| {File.basename(i.path), i} }

        by_path["child.md"].draft.should be_true
        by_path["child.md"].status.should eq("draft")
        # A section's cascade never applies to its own `_index`.
        by_path["_index.md"].draft.should be_false
      end
    end

    it "lets a page's own draft key override an inherited cascade" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        section = File.join(content_dir, "hidden")
        FileUtils.mkdir_p(section)
        File.write(File.join(section, "_index.md"),
          "+++\ntitle = \"Hidden\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(section, "shown.md"), "+++\ntitle = \"Shown\"\ndraft = false\n+++\n\nBody\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        shown = lister.list_content(Hwaro::Services::ContentFilter::All).find! { |i| i.title == "Shown" }
        shown.draft.should be_false
        shown.published?.should be_true
      end
    end

    it "lets a nested section's cascade un-draft what an ancestor cascaded" do
      # `if value = cascade[...]?` dropped the retrieved `false`, so only
      # `true` ever won; the build merges per ancestor with deeper winning.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        blog = File.join(content_dir, "blog")
        FileUtils.mkdir_p(blog)
        File.write(File.join(content_dir, "_index.md"),
          "+++\ntitle = \"Home\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(blog, "_index.md"),
          "+++\ntitle = \"Blog\"\n[cascade]\ndraft = false\n+++\n")
        File.write(File.join(blog, "post.md"), "+++\ntitle = \"Post\"\n+++\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        post = lister.list_content(Hwaro::Services::ContentFilter::All).find! { |i| i.title == "Post" }
        post.draft.should be_false
        post.published?.should be_true
      end
    end

    it "matches a cascade on the page's language, not the default one" do
      # `merged_cascade_for` keys strictly on {dir, language}, so a `ko` page
      # never inherits a default-language section's cascade.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        blog = File.join(content_dir, "blog")
        FileUtils.mkdir_p(blog)
        File.write(File.join(blog, "_index.md"),
          "+++\ntitle = \"Blog\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(blog, "post.ko.md"), "+++\ntitle = \"KO\"\n+++\n")
        File.write(File.join(blog, "post.md"), "+++\ntitle = \"EN\"\n+++\n")

        by_title = Hwaro::Services::ContentLister.new(content_dir)
          .list_content(Hwaro::Services::ContentFilter::All).to_h { |i| {i.title, i} }
        by_title["EN"].draft.should be_true
        by_title["KO"].draft.should be_false
      end
    end

    it "buckets a file spelling the default language with an unsuffixed one" do
      # `about.en.md` on an `en` site is the same language as `about.md`, so
      # both must see the section's cascade.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        blog = File.join(content_dir, "blog")
        FileUtils.mkdir_p(blog)
        File.write(File.join(dir, "config.toml"), %(title = "S"\ndefault_language = "en"\n))
        File.write(File.join(blog, "_index.md"),
          "+++\ntitle = \"Blog\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(blog, "post.en.md"), "+++\ntitle = \"EN\"\n+++\n")

        post = Hwaro::Services::ContentLister.new(content_dir)
          .list_content(Hwaro::Services::ContentFilter::All).find! { |i| i.title == "EN" }
        post.draft.should be_true
      end
    end

    it "treats a declared but non-boolean draft key as shadowing the cascade" do
      # The build resolves cascades against DECLARED keys, so `draft = "true"`
      # (a string) still shadows the ancestor's cascade.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        section = File.join(content_dir, "hidden")
        FileUtils.mkdir_p(section)
        File.write(File.join(section, "_index.md"),
          "+++\ntitle = \"Hidden\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(section, "odd.md"), "+++\ntitle = \"Odd\"\ndraft = \"true\"\n+++\n")

        lister = Hwaro::Services::ContentLister.new(content_dir)
        odd = lister.list_content(Hwaro::Services::ContentFilter::All).find! { |i| i.title == "Odd" }
        odd.draft.should be_false
      end
    end

    it "keeps `status` in the JSON payload alongside the legacy draft flag" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "future.md"), "+++\ntitle = \"Later\"\ndate = 2999-01-01\n+++\n")

        json = Hwaro::Services::ContentLister.new(content_dir).list_all.to_json
        json.should contain(%("status":"future"))
        json.should contain(%("draft":false))
      end
    end
  end

  describe Hwaro::Services::ContentStats do
    it "counts future and expired files separately from published" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "pub.md"), "+++\ntitle = \"Pub\"\ndate = 2020-01-01\n+++\n\nhello there\n")
        File.write(File.join(content_dir, "future.md"), "+++\ntitle = \"Later\"\ndate = 2999-01-01\n+++\n\nx\n")
        File.write(File.join(content_dir, "old.md"),
          "+++\ntitle = \"Old\"\ndate = 2020-01-01\nexpires = 2021-01-01\n+++\n\nx\n")

        result = Hwaro::Services::ContentStats.new(content_dir).run
        result.total.should eq(3)
        result.published.should eq(1)
        result.future.should eq(1)
        result.expired.should eq(1)
        result.drafts.should eq(0)
      end
    end

    it "counts tags declared in a [taxonomies] table" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "post.md"),
          "+++\ntitle = \"Post\"\ndate = 2020-01-01\n[taxonomies]\ntags = [\"crystal\", \"ssg\"]\n+++\n\nbody\n")

        result = Hwaro::Services::ContentStats.new(content_dir).run
        result.tags.keys.sort!.should eq(["crystal", "ssg"])
      end
    end

    it "prefers a top-level tags list over the [taxonomies] table, like the build" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "post.md"),
          "+++\ntitle = \"Post\"\ndate = 2020-01-01\ntags = [\"top\"]\n[taxonomies]\ntags = [\"nested\"]\n+++\n\nbody\n")

        Hwaro::Services::ContentStats.new(content_dir).run.tags.keys.should eq(["top"])
      end
    end

    it "counts tags from JSON front matter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "post.md"),
          %({"title": "Post", "date": "2020-01-01", "tags": ["json"]}\n\nbody\n))

        Hwaro::Services::ContentStats.new(content_dir).run.tags.keys.should eq(["json"])
      end
    end
  end

  describe Hwaro::Services::ContentValidator do
    it "applies the tag-case convention to [taxonomies] tags" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "post.md"),
          "+++\ntitle = \"Post\"\ndescription = \"d\"\n[taxonomies]\ntags = [\"MixedCase\"]\n+++\n\nbody\n")

        issues = Hwaro::Services::ContentValidator.new(content_dir).run
        issues.map(&.id).should contain("content-tag-mixed-case")
      end
    end

    it "keeps a false boolean front-matter value instead of dropping it" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "post.md"),
          "---\ntitle: Post\ndescription: d\ndraft: false\n---\n\nbody\n")

        issues = Hwaro::Services::ContentValidator.new(content_dir).run
        # `draft: false` must not be reported as a draft, and it must reach
        # the checks at all (the old `elsif b = value.as_bool?` dropped it).
        issues.map(&.id).should_not contain("content-draft")
      end
    end
  end
end
