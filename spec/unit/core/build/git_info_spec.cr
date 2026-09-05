require "../../../spec_helper"

# =============================================================================
# `[git]` — the log parser (pure, fixture-driven) and the config table.
#
# The collector shells out exactly once per build with
# `--format=%x00%H%x00%aI%x00%an%x00%ae --name-only`; these fixtures are the
# byte shape git produces for that format so the parser is pinned to it.
# =============================================================================

private NUL = "\0"

private def header(hash : String, date : String, name : String = "Alice", email : String = "alice@example.com") : String
  "#{NUL}#{hash}#{NUL}#{date}#{NUL}#{name}#{NUL}#{email}\n\n"
end

describe Hwaro::Core::Build::GitInfo do
  describe ".parse_log" do
    it "keys entries by path with hash, author and both timestamps" do
      log = header("a" * 40, "2024-03-05T10:00:00+09:00") + "posts/a.md\nposts/b.md\n\n"
      info = Hwaro::Core::Build::GitInfo.parse_log(log)

      info.keys.sort!.should eq(["posts/a.md", "posts/b.md"])
      a = info["posts/a.md"]
      a.hash.should eq("a" * 40)
      a.short_hash.should eq("aaaaaaa")
      a.author_name.should eq("Alice")
      a.author_email.should eq("alice@example.com")
      a.lastmod.should eq(Time.parse_rfc3339("2024-03-05T10:00:00+09:00"))
      a.first_commit.should eq(a.lastmod)
      # The author's UTC offset is preserved, not normalized to UTC.
      a.lastmod.offset.should eq(9 * 3600)
    end

    it "takes lastmod/hash/author from the newest commit and first_commit from the oldest" do
      log = header("a" * 40, "2024-03-05T10:00:00+00:00", "Newer", "n@example.com") + "posts/a.md\n\n" +
            header("b" * 40, "2024-02-01T10:00:00+00:00", "Middle", "m@example.com") + "posts/a.md\nposts/b.md\n\n" +
            header("c" * 40, "2024-01-01T10:00:00+00:00", "Oldest", "o@example.com") + "posts/a.md\n\n"
      info = Hwaro::Core::Build::GitInfo.parse_log(log)

      a = info["posts/a.md"]
      a.hash.should eq("a" * 40)
      a.author_name.should eq("Newer")
      a.lastmod.should eq(Time.utc(2024, 3, 5, 10, 0, 0))
      a.first_commit.should eq(Time.utc(2024, 1, 1, 10, 0, 0))

      b = info["posts/b.md"]
      b.hash.should eq("b" * 40)
      b.lastmod.should eq(Time.utc(2024, 2, 1, 10, 0, 0))
      b.first_commit.should eq(b.lastmod)
    end

    it "uses the minimum author date for first_commit when history is out of walk order" do
      # A rebased/cherry-picked commit can carry an author date OLDER than
      # commits listed after it. first_commit must be the true minimum.
      log = header("a" * 40, "2024-03-05T10:00:00+00:00") + "posts/a.md\n\n" +
            header("b" * 40, "2023-06-01T10:00:00+00:00") + "posts/a.md\n\n" +
            header("c" * 40, "2024-01-01T10:00:00+00:00") + "posts/a.md\n\n"
      info = Hwaro::Core::Build::GitInfo.parse_log(log)
      info["posts/a.md"].first_commit.should eq(Time.utc(2023, 6, 1, 10, 0, 0))
      info["posts/a.md"].lastmod.should eq(Time.utc(2024, 3, 5, 10, 0, 0))
    end

    it "decodes C-quoted paths (non-ASCII forced into octal escapes, embedded quotes)" do
      log = header("a" * 40, "2024-03-05T10:00:00+00:00") +
            "\"posts/caf\\303\\251.md\"\n\"posts/say \\\"hi\\\".md\"\n\"posts/tab\\there.md\"\nposts/한글.md\n\n"
      info = Hwaro::Core::Build::GitInfo.parse_log(log)
      info.keys.sort!.should eq(["posts/café.md", "posts/say \"hi\".md", "posts/tab\there.md", "posts/한글.md"])
    end

    it "handles commits that list no files and blank lines" do
      log = header("a" * 40, "2024-03-05T10:00:00+00:00") + "\n" +
            header("b" * 40, "2024-01-05T10:00:00+00:00") + "posts/a.md\n\n\n"
      info = Hwaro::Core::Build::GitInfo.parse_log(log)
      info.size.should eq(1)
      info["posts/a.md"].hash.should eq("b" * 40)
    end

    it "skips file lines that follow a malformed header instead of misattributing them" do
      log = "#{NUL}#{"a" * 40}#{NUL}not-a-date#{NUL}Alice#{NUL}a@example.com\n\nposts/a.md\n\n" +
            header("b" * 40, "2024-01-05T10:00:00+00:00") + "posts/b.md\n\n"
      info = Hwaro::Core::Build::GitInfo.parse_log(log)
      info.keys.should eq(["posts/b.md"])
    end

    it "returns an empty map for empty output" do
      Hwaro::Core::Build::GitInfo.parse_log("").should be_empty
    end
  end

  describe ".unquote_path" do
    it "leaves unquoted paths untouched" do
      Hwaro::Core::Build::GitInfo.unquote_path("posts/plain.md").should eq("posts/plain.md")
    end

    it "strips the quotes when nothing inside is escaped" do
      Hwaro::Core::Build::GitInfo.unquote_path("\"posts/a b.md\"").should eq("posts/a b.md")
    end

    it "decodes backslash escapes and octal byte runs" do
      Hwaro::Core::Build::GitInfo.unquote_path("\"a\\\\b\\n\\303\\251\"").should eq("a\\b\né")
    end
  end
end

describe "[git] config" do
  it "is disabled by default with use_lastmod on and use_date off" do
    config = load_config("title = \"x\"")
    config.git.enabled.should be_false
    config.git.use_lastmod.should be_true
    config.git.use_date.should be_false
  end

  it "reads enabled / use_lastmod / use_date" do
    config = load_config(<<-TOML)
      [git]
      enabled = true
      use_lastmod = false
      use_date = true
      TOML
    config.git.enabled.should be_true
    config.git.use_lastmod.should be_false
    config.git.use_date.should be_true
  end

  it "does not warn about [git] as an unknown top-level key" do
    log = with_captured_log do
      load_config("[git]\nenabled = true")
    end
    log.should_not contain("Unknown key 'git'")
  end

  it "warns about an unknown key inside [git]" do
    log = with_captured_log do
      load_config("[git]\nenabled = true\nuse_lastmodd = true")
    end
    log.should contain("[git]: unknown key 'use_lastmodd'")
  end

  it "ships a doctor/config snippet for the section" do
    Hwaro::Services::ConfigSnippets::KNOWN_SECTIONS.has_key?("git").should be_true
    Hwaro::Services::ConfigSnippets.git(commented: true).should contain("# [git]")
    Hwaro::Services::ConfigSnippets.git(commented: false).should contain("[git]\nenabled = true")
    Hwaro::Services::Doctor::OPTIONAL_SECTIONS.includes?("git").should be_true
  end
end

describe Hwaro::Core::Build::CacheEntry do
  it "round-trips git_hash and defaults it to empty for legacy entries" do
    entry = Hwaro::Core::Build::CacheEntry.new(path: "content/a.md", mtime: 1_i64, hash: "h", output_path: "public/a/index.html", git_hash: "abc:1:2")
    parsed = Hwaro::Core::Build::CacheEntry.from_json(entry.to_json)
    parsed.git_hash.should eq("abc:1:2")

    legacy = Hwaro::Core::Build::CacheEntry.from_json(%({"path":"content/a.md","mtime":1,"hash":"h","output_path":"p"}))
    legacy.git_hash.should eq("")
  end
end
