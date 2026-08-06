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

    it "treats a backslash as a separator too" do
      segments, refused = Hwaro::Utils::PathUtils.split_safe_segments("foo\\bar")
      segments.should eq(["foo", "bar"])
      refused.should be_false
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
