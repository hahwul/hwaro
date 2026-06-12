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
  end
end
