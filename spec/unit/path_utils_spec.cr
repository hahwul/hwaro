require "../spec_helper"
require "../../src/utils/path_utils"

describe Hwaro::Utils::PathUtils do
  describe ".sanitize_path" do
    it "sanitizes a normal path" do
      Hwaro::Utils::PathUtils.sanitize_path("/foo/bar").should eq("foo/bar")
    end

    it "removes parent directory references" do
      Hwaro::Utils::PathUtils.sanitize_path("/foo/../bar").should eq("foo/bar")
      Hwaro::Utils::PathUtils.sanitize_path("../foo").should eq("foo")
    end

    it "removes null bytes" do
      Hwaro::Utils::PathUtils.sanitize_path("/foo\0bar").should eq("foobar")
    end

    it "normalizes multiple slashes" do
      Hwaro::Utils::PathUtils.sanitize_path("/foo//bar").should eq("foo/bar")
      Hwaro::Utils::PathUtils.sanitize_path("foo///bar").should eq("foo/bar")
    end

    it "decodes encoded characters" do
      Hwaro::Utils::PathUtils.sanitize_path("%2Ffoo%2Fbar").should eq("foo/bar")
      Hwaro::Utils::PathUtils.sanitize_path("foo%2Fbar").should eq("foo/bar")
    end

    it "strips trailing slashes from decoded paths" do
      # This verifies the fix for the bug in the original regex implementation
      Hwaro::Utils::PathUtils.sanitize_path("/foo/").should eq("foo")
      Hwaro::Utils::PathUtils.sanitize_path("%2Ffoo%2F").should eq("foo")
    end

    it "handles paths with only slashes" do
      Hwaro::Utils::PathUtils.sanitize_path("///").should eq("")
    end

    it "handles empty string" do
      Hwaro::Utils::PathUtils.sanitize_path("").should eq("")
    end

    it "handles complex mixed cases" do
      # /foo/../bar//baz/ -> foo/bar/baz
      Hwaro::Utils::PathUtils.sanitize_path("/foo/../bar//baz/").should eq("foo/bar/baz")
    end

    it "prevents nested dot-dot bypass (....//)" do
      Hwaro::Utils::PathUtils.sanitize_path("....//etc/passwd").should eq("etc/passwd")
      Hwaro::Utils::PathUtils.sanitize_path("....//....//etc/passwd").should eq("etc/passwd")
    end

    it "prevents double-encoded traversal" do
      # %252F%252E%252E = double-encoded /../
      Hwaro::Utils::PathUtils.sanitize_path("%252E%252E%252Fetc%252Fpasswd").should eq("etc/passwd")
    end

    it "handles backslash traversal" do
      Hwaro::Utils::PathUtils.sanitize_path("..\\..\\etc\\passwd").should eq("etc/passwd")
    end

    it "rejects dot segments" do
      Hwaro::Utils::PathUtils.sanitize_path("/./foo/./bar").should eq("foo/bar")
    end

    it "handles Unicode paths" do
      Hwaro::Utils::PathUtils.sanitize_path("/한글/경로/파일").should eq("한글/경로/파일")
    end

    it "handles Unicode paths with traversal (drops .. segment)" do
      # sanitize_path drops ".." segments rather than resolving them
      Hwaro::Utils::PathUtils.sanitize_path("/한글/../비밀").should eq("한글/비밀")
    end

    it "handles path with only dots" do
      Hwaro::Utils::PathUtils.sanitize_path("..").should eq("")
    end

    it "handles triple-encoded traversal" do
      # %25252E%25252E = triple-encoded ..
      Hwaro::Utils::PathUtils.sanitize_path("%25252E%25252E%25252Fetc").should eq("etc")
    end

    it "handles mixed forward and backslash" do
      Hwaro::Utils::PathUtils.sanitize_path("foo\\bar/baz").should eq("foo/bar/baz")
    end

    it "handles path with spaces" do
      Hwaro::Utils::PathUtils.sanitize_path("/path with spaces/file").should eq("path with spaces/file")
    end

    it "handles percent-encoded spaces" do
      Hwaro::Utils::PathUtils.sanitize_path("/path%20with%20spaces/file").should eq("path with spaces/file")
    end

    it "handles single segment path" do
      Hwaro::Utils::PathUtils.sanitize_path("filename.txt").should eq("filename.txt")
    end

    it "strips dot-dot segments from deep paths" do
      Hwaro::Utils::PathUtils.sanitize_path("/a/b/c/../../d").should eq("a/b/c/d")
    end

    it "neutralizes percent-encoded overlong UTF-8 instead of raising" do
      # %C0%AE decodes to an overlong 2-byte "." — invalid UTF-8 that made
      # the PCRE2 segment split raise, letting a hostile archive entry or
      # importer path crash the CLI. It must neutralize, not raise, and an
      # overlong ".." must still not survive as a traversal.
      Hwaro::Utils::PathUtils.sanitize_path("%C0%AE%C0%AE/etc").should eq("����/etc")
      Hwaro::Utils::PathUtils.split_safe_segments("%2e%2e/z").should eq({["z"], true})
    end

    it "keeps raw invalid-UTF-8 bytes as ordinary segments" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("\xC0\xAE/z")
      segments.should eq(["\xC0\xAE", "z"])
      refused.should be_false
    end
  end

  describe ".resolves_within?" do
    it "accepts a plain file inside the root" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "asset.txt"), "x")
        Hwaro::Utils::PathUtils.resolves_within?(File.join(root, "asset.txt"), root).should be_true
      end
    end

    it "accepts a symlink pointing inside the root" do
      Dir.mktmpdir do |root|
        target = File.join(root, "real.txt")
        File.write(target, "x")
        link = File.join(root, "link.txt")
        File.symlink(target, link)
        Hwaro::Utils::PathUtils.resolves_within?(link, root).should be_true
      end
    end

    it "rejects a symlink whose target escapes the root" do
      Dir.mktmpdir do |outside|
        secret = File.join(outside, "secret.txt")
        File.write(secret, "leak")
        Dir.mktmpdir do |root|
          link = File.join(root, "leak.txt")
          File.symlink(secret, link)
          Hwaro::Utils::PathUtils.resolves_within?(link, root).should be_false
        end
      end
    end

    it "returns false for a dangling/unreadable path" do
      Dir.mktmpdir do |root|
        Hwaro::Utils::PathUtils.resolves_within?(File.join(root, "nope.txt"), root).should be_false
      end
    end

    it "accepts the root itself" do
      Dir.mktmpdir do |root|
        Hwaro::Utils::PathUtils.resolves_within?(root, root).should be_true
      end
    end

    it "returns false for a missing root rather than raising" do
      Dir.mktmpdir do |root|
        file = File.join(root, "a.txt")
        File.write(file, "x")
        Hwaro::Utils::PathUtils.resolves_within?(file, File.join(root, "nope")).should be_false
      end
    end

    # A sibling whose name merely starts with the root's name is outside it;
    # the check must compare on a separator boundary.
    it "rejects a sibling directory sharing the root's name prefix" do
      Dir.mktmpdir do |parent|
        root = File.join(parent, "site")
        sibling = File.join(parent, "site-backup")
        Dir.mkdir(root)
        Dir.mkdir(sibling)
        file = File.join(sibling, "a.txt")
        File.write(file, "x")
        Hwaro::Utils::PathUtils.resolves_within?(file, root).should be_false
      end
    end
  end

  # `split_safe_segments` is the shared predicate behind BOTH traversal
  # policies: neutralize-and-continue (`sanitize_path`) and refuse-outright
  # (the build's `url_output_path`). The `refused` flag is what lets the
  # writers refuse instead of silently RELOCATING a page onto whatever already
  # occupies the shortened path — that is how `content/a..b/` once overwrote
  # the site's index.html.
  describe ".split_safe_segments" do
    it "reports no refusal for an ordinary path" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("foo/bar/baz")
      segments.should eq(["foo", "bar", "baz"])
      refused.should be_false
    end

    it "flags a refusal when a traversal segment is dropped" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("foo/../bar")
      segments.should eq(["foo", "bar"])
      refused.should be_true
    end

    it "flags a refusal for percent-encoded traversal" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("%2e%2e/etc")
      segments.should eq(["etc"])
      refused.should be_true
    end

    it "flags a refusal for double-encoded traversal" do
      _, refused = Hwaro::Utils::PathUtils.split_safe_segments("%252e%252e/etc")
      refused.should be_true
    end

    # Newly REFUSED versus the pre-2026-08 rule, which let all-space segments
    # through.
    it "flags a refusal for an all-space segment" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("a/   /b")
      segments.should eq(["a", "b"])
      refused.should be_true
    end

    it "flags a refusal for the Windows dot/space collapse forms" do
      ["a/.. /b", "a/. /b", "a/.../b"].each do |path|
        _, refused = Hwaro::Utils::PathUtils.split_safe_segments(path)
        refused.should be_true
      end
    end

    # Newly KEPT versus the old "contains .." rule: these cannot traverse on
    # any supported platform, and refusing them would break ordinary slugs.
    it "keeps segments that merely contain dots without flagging a refusal" do
      ["notes/v1..v2", "a..b/c", "..foo/c", "lib.v1..2.js"].each do |path|
        _, refused = Hwaro::Utils::PathUtils.split_safe_segments(path)
        refused.should be_false
      end
    end

    # Only ASCII space and `.` are trimmed by Win32, so these stay distinct
    # filenames rather than traversal.
    it "keeps whitespace-suffixed dot forms other than ASCII space" do
      _, refused = Hwaro::Utils::PathUtils.split_safe_segments("a/..\t/b")
      refused.should be_false
    end

    it "does not flag a refusal for empty segments from repeated slashes" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("//foo///bar//")
      segments.should eq(["foo", "bar"])
      refused.should be_false
    end

    # Was "treats a backslash as a separator too". Splitting on `\` here gave
    # a content file named `a\b.md` — a perfectly legal POSIX filename — the
    # output path `posts/a/b/index.html`, which silently overwrote the page
    # that owns it. The writer cannot resolve the ambiguity (POSIX says one
    # segment, Windows says two, and browsers rewrite `\` to `/` in a URL
    # path), so it refuses. `sanitize_path` still normalizes it — see below.
    it "refuses a segment containing a backslash instead of splitting on it" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("foo\\bar")
      segments.should be_empty
      refused.should be_true
    end

    # The high-severity half of the same defect: a percent-encoded separator.
    # Decoding the whole path before splitting turned `%2f` into a real
    # directory level, so `posts/a%2fb.md` claimed `/posts/a%2fb/` but wrote
    # `posts/a/b/index.html` over the real `posts/a/b.md`.
    it "refuses a segment whose decoded form still contains a separator" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("posts/a%2fb")
      segments.should eq(["posts"])
      refused.should be_true

      _, double_refused = Hwaro::Utils::PathUtils.split_safe_segments("posts/a%252fb")
      double_refused.should be_true

      _, encoded_backslash_refused = Hwaro::Utils::PathUtils.split_safe_segments("posts/a%5cb")
      encoded_backslash_refused.should be_true
    end

    # Only separators are refused: any other escape still decodes to the
    # directory name the URL addresses, which is what keeps `page.url`'s
    # `%23` pointing at the `a#b` directory on disk.
    it "decodes a non-separator escape into the segment it names" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("posts/a%23b")
      segments.should eq(["posts", "a#b"])
      refused.should be_false
    end

    # The neutralize policy keeps normalizing separators — a Windows-authored
    # archive entry must still extract to the nested path it names.
    it "keeps sanitize_path normalizing separators the writer refuses" do
      Hwaro::Utils::PathUtils.sanitize_path("foo\\bar").should eq("foo/bar")
      Hwaro::Utils::PathUtils.sanitize_path("posts/a%2fb").should eq("posts/a/b")
    end

    it "strips null bytes without flagging a refusal" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("fo\u{0000}o/bar")
      segments.should eq(["foo", "bar"])
      refused.should be_false
    end

    it "returns no segments and no refusal for an empty path" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("")
      segments.should be_empty
      refused.should be_false
    end

    it "agrees with sanitize_path on the segments it keeps" do
      ["foo/../bar", "a/   /b", "notes/v1..v2", "%2e%2e/etc", "//a//b//"].each do |path|
        segments, _ = Hwaro::Utils::PathUtils.split_safe_segments(path)
        segments.join("/").should eq(Hwaro::Utils::PathUtils.sanitize_path(path))
      end
    end
  end

  # Collision keys for the Render phase. Two URL strings that name one file
  # must share a key, or the second page overwrites the first with no warning.
  #
  # Characterisation coverage: `output_file_key` / `output_fold_key` /
  # `case_folding_fs?` are introduced by this fix, so these examples cannot be
  # run against the pre-fix tree at all. The pre-fix proof for the defect they
  # serve is end-to-end in spec/functional/edge_cases_spec.cr ("does not
  # silently overwrite a page whose output path differs only in case"), which
  # fails without them.
  describe ".output_file_key" do
    it "maps URL spellings of one file onto one key" do
      key = Hwaro::Utils::PathUtils.output_file_key("/posts/a/b/")
      key.should eq("posts/a/b")
      Hwaro::Utils::PathUtils.output_file_key("/posts//a/b//").should eq(key)
      Hwaro::Utils::PathUtils.output_file_key("posts/a/b").should eq(key)
    end

    it "gives the site root an empty key" do
      Hwaro::Utils::PathUtils.output_file_key("/").should eq("")
    end

    it "returns nil for a URL that cannot be published at all" do
      Hwaro::Utils::PathUtils.output_file_key("/posts/a%2fb/").should be_nil
      Hwaro::Utils::PathUtils.output_file_key("/../etc/").should be_nil
    end
  end

  describe ".output_fold_key" do
    it "folds letter case" do
      upper = Hwaro::Utils::PathUtils.output_fold_key("Foo/Bar")
      upper.should eq(Hwaro::Utils::PathUtils.output_fold_key("foo/bar"))
    end

    it "folds NFD and NFC spellings of the same name together" do
      # "cafe" + COMBINING ACUTE ACCENT, built from the codepoint so the
      # decomposed form survives any editor that normalizes on save.
      nfd = "cafe" + 0x0301.chr
      nfc = nfd.unicode_normalize(:nfc)
      nfc.should_not eq(nfd)
      Hwaro::Utils::PathUtils.output_fold_key(nfc).should eq(Hwaro::Utils::PathUtils.output_fold_key(nfd))
    end
  end

  describe ".case_folding_fs?" do
    it "answers case-sensitive for a path with no ASCII letters to flip" do
      Hwaro::Utils::PathUtils.case_folding_fs?("/").should be_false
    end

    it "answers case-sensitive for an unreadable path rather than raising" do
      Dir.mktmpdir do |root|
        Hwaro::Utils::PathUtils.case_folding_fs?(File.join(root, "Nope")).should be_false
      end
    end

    # The answer itself is filesystem-dependent (true on a stock macOS/Windows
    # volume, false on ext4), so assert only that the probe is consistent with
    # what the filesystem actually does with the two spellings.
    it "agrees with the filesystem it probed" do
      Dir.mktmpdir do |root|
        dir = File.join(root, "CaseProbe")
        Dir.mkdir(dir)
        folded = File.exists?(File.join(root, "caseprobe"))
        Hwaro::Utils::PathUtils.case_folding_fs?(dir).should eq(folded)
      end
    end
  end

  # A single config typo must not crash a whole build or deploy.
  describe ".glob_match?" do
    it "matches a simple glob" do
      Hwaro::Utils::PathUtils.glob_match?("*.css", "style.css").should be_true
    end

    it "does not match a non-matching path" do
      Hwaro::Utils::PathUtils.glob_match?("*.css", "style.js").should be_false
    end

    it "matches a character class" do
      Hwaro::Utils::PathUtils.glob_match?("a[0-9].txt", "a1.txt").should be_true
    end

    it "returns false for a malformed glob instead of raising" do
      Hwaro::Utils::PathUtils.glob_match?("[", "a").should be_false
      Hwaro::Utils::PathUtils.glob_match?("a[0-", "a1").should be_false
    end

    it "returns false for an empty pattern" do
      Hwaro::Utils::PathUtils.glob_match?("", "a").should be_false
    end
  end
end
