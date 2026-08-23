require "../spec_helper"

describe Hwaro::Services::ContentStats do
  describe "#run" do
    it "raises a classified content error when the content directory does not exist" do
      # A missing directory must be distinguishable from "no content": a
      # zeroed report and exit 0 hid a mistyped --content-dir entirely.
      stats = Hwaro::Services::ContentStats.new("/nonexistent/path/content")
      error = expect_raises(Hwaro::HwaroError) { stats.run }
      error.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
    end

    it "counts total, drafts, and published correctly" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "pub1.md"), "---\ntitle: Post 1\ndraft: false\n---\n\nHello world\n")
        File.write(File.join(content_dir, "pub2.md"), "---\ntitle: Post 2\n---\n\nAnother post\n")
        File.write(File.join(content_dir, "draft1.md"), "---\ntitle: Draft 1\ndraft: true\n---\n\nDraft content\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.total.should eq(3)
        result.drafts.should eq(1)
        result.published.should eq(2)
      end
    end

    it "computes word count statistics" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "short.md"), "---\ntitle: Short\n---\n\nOne two three\n")
        File.write(File.join(content_dir, "long.md"), "---\ntitle: Long\n---\n\nOne two three four five six seven eight nine ten\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.words_min.should eq(3)
        result.words_max.should eq(10)
        result.words_total.should eq(13)
      end
    end

    it "aggregates tags" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post1.md"), "---\ntitle: Post 1\ntags:\n  - crystal\n  - web\n---\n\nContent\n")
        File.write(File.join(content_dir, "post2.md"), "---\ntitle: Post 2\ntags:\n  - crystal\n  - cli\n---\n\nContent\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.tags["crystal"].should eq(2)
        result.tags["web"].should eq(1)
        result.tags["cli"].should eq(1)
      end
    end

    # Regression for gh#528 (C): word counts, tags, and monthly buckets
    # used to include drafts even though `hwaro build` skips them. Stats
    # now reflect what would actually publish.
    it "excludes drafts from word counts, tags, and monthly buckets (gh#528)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(
          File.join(content_dir, "pub.md"),
          "---\ntitle: Pub\ndate: 2024-01-10\ntags:\n  - kept\n---\n\none two three\n",
        )
        File.write(
          File.join(content_dir, "draft.md"),
          "---\ntitle: Draft\ndraft: true\ndate: 2024-02-10\ntags:\n  - dropped\n---\n\nfour five six seven eight\n",
        )

        result = Hwaro::Services::ContentStats.new(content_dir).run

        # Bucket counts still reflect the whole content set.
        result.total.should eq(2)
        result.drafts.should eq(1)
        result.published.should eq(1)

        # Word stats reflect only the published item ("one two three" = 3).
        result.words_total.should eq(3)
        result.words_min.should eq(3)
        result.words_max.should eq(3)

        # Draft tags don't appear in the chart, draft month doesn't either.
        result.tags.has_key?("dropped").should be_false
        result.tags["kept"].should eq(1)
        result.monthly.has_key?("2024-02").should be_false
        result.monthly["2024-01"].should eq(1)
      end
    end

    it "aggregates monthly publishing frequency" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "jan1.md"), "---\ntitle: Jan 1\ndate: 2024-01-15\n---\n\nContent\n")
        File.write(File.join(content_dir, "jan2.md"), "---\ntitle: Jan 2\ndate: 2024-01-20\n---\n\nContent\n")
        File.write(File.join(content_dir, "feb1.md"), "---\ntitle: Feb 1\ndate: 2024-02-10\n---\n\nContent\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.monthly["2024-01"].should eq(2)
        result.monthly["2024-02"].should eq(1)
      end
    end

    it "buckets monthly frequency from TOML native and string dates" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        # Unquoted TOML date parses to a native Time value (distinct branch
        # from quoted/string dates).
        File.write(File.join(content_dir, "native.md"), "+++\ntitle = \"X\"\ndate = 2024-03-15T10:00:00Z\ntags = [\"a\"]\n+++\n\nword word\n")
        File.write(File.join(content_dir, "string.md"), "+++\ntitle = \"Y\"\ndate = \"2024-04-01\"\n+++\n\nword word\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.monthly["2024-03"].should eq(1)
        result.monthly["2024-04"].should eq(1)
      end
    end

    it "works with TOML frontmatter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "toml.md"), "+++\ntitle = \"TOML Post\"\ntags = [\"crystal\", \"toml\"]\n+++\n\nSome content here\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.total.should eq(1)
        result.tags["crystal"].should eq(1)
        result.tags["toml"].should eq(1)
      end
    end

    it "returns empty tags when no tags present" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-tags.md"), "---\ntitle: No Tags\n---\n\nContent\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.tags.should be_empty
      end
    end

    it "serializes to JSON" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\ntags:\n  - test\n---\n\nWord\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run
        json = JSON.parse(result.to_json)

        json["total"].as_i.should eq(1)
        json["tags"]["test"].as_i.should eq(1)
      end
    end

    it "handles single file correctly for min/max" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "only.md"), "---\ntitle: Only\n---\n\nOne two three four five\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.words_min.should eq(5)
        result.words_max.should eq(5)
        result.words_avg.should eq(5)
      end
    end

    it "handles files with only frontmatter and no body" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "empty-body.md"), "---\ntitle: Empty\n---\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.total.should eq(1)
        result.words_min.should eq(0)
      end
    end

    it "counts fenced code blocks exactly like the build's page.word_count" do
      # Expectation changed: stats used to strip fenced code blocks, but the
      # build's `page.word_count` (the source of truth) does not — the two
      # numbers drifted on any page with a code block.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        body = "\nReal words here\n\n```crystal\nputs \"not counted\"\nvar = 123\n```\n"
        File.write(File.join(content_dir, "code.md"), "---\ntitle: Code\n---\n#{body}")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.words_total.should eq(Hwaro::Utils::TextUtils.count_words(body))
        # The fenced words are counted, not stripped.
        result.words_total.should be > 3
      end
    end

    it "sorts tags by count descending" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "p1.md"), "---\ntitle: P1\ntags:\n  - rare\n  - common\n---\n\nA\n")
        File.write(File.join(content_dir, "p2.md"), "---\ntitle: P2\ntags:\n  - common\n---\n\nA\n")
        File.write(File.join(content_dir, "p3.md"), "---\ntitle: P3\ntags:\n  - common\n---\n\nA\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.tags.keys.first.should eq("common")
      end
    end

    it "sorts monthly by date ascending" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "dec.md"), "---\ntitle: Dec\ndate: 2024-12-01\n---\n\nA\n")
        File.write(File.join(content_dir, "jan.md"), "---\ntitle: Jan\ndate: 2024-01-01\n---\n\nA\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.monthly.keys.first.should eq("2024-01")
        result.monthly.keys.last.should eq("2024-12")
      end
    end

    it "handles files without date for monthly" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "no-date.md"), "---\ntitle: No Date\n---\n\nContent\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.monthly.should be_empty
      end
    end

    it "handles empty tags array" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "empty-tags.md"), "+++\ntitle = \"Post\"\ntags = []\n+++\n\nWord\n")

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.tags.should be_empty
      end
    end

    # Regression: `TOML.parse` builds the date eagerly, so an out-of-range but
    # syntactically valid date raised Crystal's `ArgumentError("Invalid time")`
    # — which the `rescue TOML::ParseException` did not catch. One typo aborted
    # the whole report ("Error: Invalid time", exit 1) without naming the file,
    # while every sibling command (`tool list`, `tool validate`) survived the
    # same tree.
    it "survives an out-of-range TOML date and still reports the other files" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "good.md"),
          "+++\ntitle = \"Good\"\ndate = 2024-01-01\ntags = [\"kept\"]\n+++\n\nhello world\n")
        File.write(File.join(content_dir, "bad.md"),
          "+++\ntitle = \"Typo\"\ndate = 2024-02-30\n+++\n\nhello\n")

        result = Hwaro::Services::ContentStats.new(content_dir).run

        result.total.should eq(2)
        result.words_total.should eq(3)
        result.tags["kept"].should eq(1)
        result.monthly["2024-01"].should eq(1)
      end
    end

    it "names the file whose front matter could not be parsed" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "bad.md"),
          "+++\ntitle = \"Typo\"\ndate = 2024-02-30\n+++\n\nhello\n")

        output = with_captured_log do
          Hwaro::Services::ContentStats.new(content_dir).run
        end

        output.should contain("bad.md")
        output.should contain("Invalid time")
      end
    end

    it "excludes JSON frontmatter from word count (regression)" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "json-words.md"), %({"title": "Post", "description": "This is a very long description with many words"}\n\nOnlyOneWord\n))

        stats = Hwaro::Services::ContentStats.new(content_dir)
        result = stats.run

        result.words_total.should eq(1)
      end
    end
  end
end
