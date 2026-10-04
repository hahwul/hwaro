require "../../spec_helper"

describe Hwaro::WindowsPaths do
  describe ".to_slash" do
    it "turns backslashes into forward slashes" do
      Hwaro::WindowsPaths.to_slash("C:\\site\\content\\post.md").should eq("C:/site/content/post.md")
    end

    it "leaves extended-length paths alone" do
      Hwaro::WindowsPaths.to_slash("\\\\?\\C:\\site\\x").should eq("\\\\?\\C:\\site\\x")
    end
  end

  {% if flag?(:windows) %}
    it "makes the stdlib path builders return / paths" do
      File.join("a", "b", "c").should eq("a/b/c")
      File.expand_path("x").should_not contain('\\')
      Dir.current.should_not contain('\\')
      Path["content\\blog\\post.md"].relative_to("content").to_s.should eq("blog/post.md")
    end

    it "resolves a symlinked directory in the middle of a path" do
      Dir.mktmpdir do |dir|
        outside = File.join(dir, "outside")
        Dir.mkdir_p(outside)
        File.write(File.join(outside, "secret.txt"), "x")
        project = File.join(dir, "project")
        Dir.mkdir_p(project)
        File.symlink(outside, File.join(project, "vendor"))

        File.realpath(File.join(project, "vendor", "secret.txt"))
          .should eq(File.join(File.realpath(outside), "secret.txt"))
        # The fallback for volumes GetFinalPathNameByHandleW can't name. It
        # keeps 8.3 short names, so compare it with itself.
        Hwaro::WindowsPaths.walk_realpath(File.join(project, "vendor", "secret.txt"))
          .should eq(Hwaro::WindowsPaths.walk_realpath(File.join(outside, "secret.txt")))
      end
    end

    it "raises File::Error for a missing path" do
      expect_raises(File::Error) { File.realpath(File.join(Dir.tempdir, "hwaro-missing-#{Random.rand(1_000_000)}")) }
    end
  {% end %}
end
