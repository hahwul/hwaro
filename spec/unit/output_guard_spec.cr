require "../spec_helper"
require "../../src/utils/output_guard"

describe Hwaro::Utils::OutputGuard do
  describe ".safe_output_path" do
    it "returns path when within output directory" do
      result = Hwaro::Utils::OutputGuard.safe_output_path("public/blog/index.html", "public")
      result.should_not be_nil
      result.not_nil!.should end_with("/public/blog/index.html")
    end

    it "returns nil for path traversal attempt" do
      result = Hwaro::Utils::OutputGuard.safe_output_path("public/../etc/passwd", "public")
      result.should be_nil
    end

    it "returns path when it equals the output directory" do
      result = Hwaro::Utils::OutputGuard.safe_output_path("public", "public")
      result.should_not be_nil
    end

    it "returns nil for path outside output directory" do
      result = Hwaro::Utils::OutputGuard.safe_output_path("/tmp/evil", "public")
      result.should be_nil
    end

    it "handles nested subdirectories" do
      result = Hwaro::Utils::OutputGuard.safe_output_path("public/a/b/c/index.html", "public")
      result.should_not be_nil
    end
  end

  describe ".within_output_dir?" do
    it "returns true for path within output directory" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/blog/index.html", "public").should be_true
    end

    it "returns false for path traversal attempt" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/../etc/passwd", "public").should be_false
    end

    it "returns true when path equals the output directory" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public", "public").should be_true
    end

    it "returns false for path outside output directory" do
      Hwaro::Utils::OutputGuard.within_output_dir?("/tmp/evil", "public").should be_false
    end

    it "returns false for sibling directory with similar prefix" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public_extra/file.html", "public").should be_false
    end
  end
end
