require "../../spec_helper"

# ext/dir_glob_handle_leak.cr — block-form `Dir.glob` and early exits.
private def open_fd_count : Int32
  Dir.children("/dev/fd").size
end

describe "Dir.glob with a block (ext/dir_glob_handle_leak)" do
  # Regression: the stdlib's recursive globber keeps one open `Dir` per
  # directory level and closes it only when that level is exhausted, so a
  # block that raised (a Sass compile error inside `compile_all`) leaked
  # every level it was inside. A `hwaro serve` session lost two descriptors
  # per failed `.scss` save and stopped working at the fd limit.
  it "closes its directory handles when the block raises, breaks or returns" do
    pending!("needs /dev/fd") unless Dir.exists?("/dev/fd")

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "a", "b", "c"))
      File.write(File.join(dir, "a", "b", "c", "deep.scss"), "x")
      pattern = File.join(dir, "**", "*.scss")

      # Once outside the measurement: the first call may open descriptors
      # that stay open for the process (not per call).
      Dir.glob(pattern) { }
      before = open_fd_count

      50.times do
        expect_raises(Exception, "boom") { Dir.glob(pattern) { raise "boom" } }
        Dir.glob(pattern) { break }
      end

      open_fd_count.should eq(before)
    end
  end

  it "yields the same paths, in the same order, as the array form" do
    Dir.mktmpdir do |dir|
      %w[b/two.md a/one.md a/.hidden.md c/d/three.md top.md].each do |rel|
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, rel)
      end
      match = File::MatchOptions.glob_default | File::MatchOptions::DotFiles

      [[File.join(dir, "**", "*")], [File.join(dir, "a", "*.md"), File.join(dir, "**", "*.md")]].each do |patterns|
        yielded = [] of String
        Dir.glob(patterns, match: match) { |path| yielded << path }
        yielded.should eq(Dir.glob(patterns, match: match))
        yielded.should_not be_empty
      end

      splatted = [] of String
      Dir.glob(File.join(dir, "a", "*.md"), File.join(dir, "top.md")) { |path| splatted << path }
      splatted.should eq(Dir.glob(File.join(dir, "a", "*.md"), File.join(dir, "top.md")))
      splatted.size.should eq(2)
    end
  end
end
