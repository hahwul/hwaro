require "../../spec_helper"
require "../../../src/utils/path_utils"

# =============================================================================
# PathUtils.sanitize_path — traversal neutralization contract.
#
# This is a SHARED sink: untrusted importer section names
# (services/importers/base.cr), untrusted remote-scaffold archive paths
# (services/scaffolds/remote.cr), and SEO/feed output directories all pass
# through it. Its reject rule changed from "segment contains .." to "segment
# is nothing but dots and spaces", because the old rule DISCARDED ordinary
# names like `v1..v2` and silently relocated whatever they addressed.
#
# The traversal guarantee must remain at least as strong. Every form below was
# neutralized before and must stay neutralized.
# =============================================================================

private def sanitized(path : String)
  Hwaro::Utils::PathUtils.sanitize_path(path)
end

describe Hwaro::Utils::PathUtils do
  describe ".sanitize_path traversal neutralization" do
    it "strips plain parent references" do
      sanitized("../etc/passwd").should eq("etc/passwd")
      sanitized("../../etc/passwd").should eq("etc/passwd")
      sanitized("foo/../../etc").should eq("foo/etc")
      sanitized("..").should eq("")
      sanitized("../..").should eq("")
    end

    it "strips current-directory references" do
      sanitized("./foo").should eq("foo")
      sanitized("foo/./bar").should eq("foo/bar")
      sanitized(".").should eq("")
    end

    it "strips runs of dots used as bypass attempts" do
      sanitized("....//etc/passwd").should eq("etc/passwd")
      sanitized(".../foo").should eq("foo")
      sanitized("...././foo").should eq("foo")
    end

    it "strips dot segments padded with spaces (Windows normalizes these)" do
      # Windows drops trailing dots and spaces, so all of these name `.`/`..`
      # there. The previous rule let ". " through as a literal segment.
      sanitized(". /foo").should eq("foo")
      sanitized(".. /foo").should eq("foo")
      sanitized("foo/. /bar").should eq("foo/bar")
    end

    it "strips percent-encoded parent references" do
      sanitized("%2e%2e/etc").should eq("etc")
      sanitized("%2E%2E%2Fetc").should eq("etc")
      sanitized("foo/%2e%2e/bar").should eq("foo/bar")
    end

    it "strips double-encoded parent references" do
      sanitized("%252e%252e/etc").should eq("etc")
      sanitized("%252E%252E%252Fetc").should eq("etc")
    end

    it "strips backslash-separated parent references" do
      sanitized("..\\etc\\passwd").should eq("etc/passwd")
      sanitized("foo\\..\\bar").should eq("foo/bar")
      sanitized("%2e%2e\\etc").should eq("etc")
    end

    it "strips mixed separator and encoding forms" do
      sanitized("..%2f..%5cetc").should eq("etc")
      sanitized("foo/..\\..%2fbar").should eq("foo/bar")
    end

    it "removes null bytes" do
      sanitized("foo\u0000bar").should eq("foobar")
      sanitized("..\u0000/etc").should eq("etc")
    end

    it "never returns a path with a parent reference in it" do
      [
        "../etc", "..", "....//x", "%2e%2e/x", "%252e%252e/x",
        "..\\x", "..%2f..%5cx", ". /x", ".. /x", "a/../../b",
      ].each do |input|
        result = sanitized(input)
        result.should_not start_with("/")
        next if result.empty? # everything was neutralized away — the safest outcome
        # Every surviving segment must be a real name, not a dots/spaces run
        # that Win32 would trim back into `.` or `..`.
        result.split('/').each do |segment|
          segment.should_not be_empty
          segment.rstrip(". ").should_not be_empty
        end
      end
    end
  end

  describe ".sanitize_path preserves ordinary names containing dots" do
    it "keeps a segment that merely contains .." do
      sanitized("notes/v1..v2").should eq("notes/v1..v2")
      sanitized("a..b").should eq("a..b")
      sanitized("no..tes/page").should eq("no..tes/page")
    end

    it "keeps leading- and trailing-dot names" do
      sanitized("..foo").should eq("..foo")
      sanitized("foo..").should eq("foo..")
      sanitized(".hidden").should eq(".hidden")
    end

    # Newly KEPT relative to the pre-2026-08 rule. Win32 trims trailing ASCII
    # space and `.` only, so a tab / NBSP suffix leaves a distinct filename
    # that cannot name the parent on any supported platform.
    it "keeps dot runs suffixed with non-trimmed whitespace" do
      sanitized("..\t").should eq("..\t")
      sanitized("..\u00a0").should eq("..\u00a0")
      sanitized("foo/..\t/bar").should eq("foo/..\t/bar")
    end

    it "keeps versioned and ranged directory names" do
      sanitized("docs/1.0..2.0/notes").should eq("docs/1.0..2.0/notes")
    end

    it "still collapses separators and trims edges around them" do
      sanitized("/a..b/").should eq("a..b")
      sanitized("//a..b//c..d//").should eq("a..b/c..d")
    end
  end
end
