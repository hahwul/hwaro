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
  end
end
