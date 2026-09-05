require "../../spec_helper"
require "../../../src/utils/output_guard"

# =============================================================================
# OutputGuard path normalization
#
# `File.expand_path` resolves `.`/`..` but PRESERVES a trailing separator, so
# an output directory typed as `public/` (what shell directory completion
# produces) used to compare against `…/public//` and reject every page —
# `hwaro build -o public/` published nothing and still exited 0.
# =============================================================================

describe Hwaro::Utils::OutputGuard do
  describe "trailing separator on the output directory" do
    it "accepts a page path when output_dir has a trailing slash" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/blog/index.html", "public/").should be_true
    end

    it "accepts the homepage when output_dir has a trailing slash" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/index.html", "public/").should be_true
    end

    it "accepts a page path when output_dir has repeated trailing slashes" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/blog/index.html", "public//").should be_true
    end

    it "returns the resolved path from safe_output_path with a trailing slash" do
      result = Hwaro::Utils::OutputGuard.safe_output_path("public/blog/index.html", "public/")
      result.should_not be_nil
      result.not_nil!.should end_with("/public/blog/index.html")
    end

    it "resolves to the same answer with and without the trailing slash" do
      with_slash = Hwaro::Utils::OutputGuard.safe_output_path("public/a/index.html", "public/")
      without = Hwaro::Utils::OutputGuard.safe_output_path("public/a/index.html", "public")
      with_slash.should eq(without)
    end

    it "still rejects an escaping path when output_dir has a trailing slash" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/../etc/passwd", "public/").should be_false
    end

    it "still rejects a prefix-sharing sibling when output_dir has a trailing slash" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public_extra/file.html", "public/").should be_false
    end
  end

  describe "dot segments" do
    it "accepts a path containing a `.` segment" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/./blog/index.html", "public").should be_true
    end

    it "accepts an output_dir containing a `.` segment" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/blog/index.html", "./public").should be_true
    end

    it "accepts a `..` that stays inside the output directory" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/a/../b/index.html", "public").should be_true
    end

    it "rejects a `..` that climbs out of the output directory" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/a/../../outside.html", "public").should be_false
    end

    it "accepts a path equal to the output directory written with a dot segment" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/.", "public").should be_true
    end
  end
end
