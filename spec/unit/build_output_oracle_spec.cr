require "../spec_helper"

# Issue #761: `hwaro doctor` and `hwaro tool check-links` accept paths that no
# source file explains by looking for them in a previous build's output_dir.
# Since #758 `hwaro serve` builds into `.hwaro/serve/`, so in a serve-only
# workflow that tree is absent (pipeline-emitted assets read as missing) or
# frozen at an old build (paths that no longer exist still validate). This is
# where both tools' "may I believe this tree?" answer lives.
describe Hwaro::Utils::BuildOutput do
  it "never uses a missing output directory as evidence, and says why" do
    Dir.mktmpdir do |dir|
      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")])

      oracle.state.should eq(Hwaro::Utils::BuildOutput::State::Missing)
      oracle.usable?.should be_false
      oracle.exists?("css/app.css").should be_false
      oracle.consulted?.should be_false
      oracle.hint.to_s.should contain("hwaro build")
      oracle.hint.to_s.should contain(".hwaro/serve")
    end
  end

  it "treats an output directory with nothing in it as missing" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public"))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [] of String)
      oracle.state.should eq(Hwaro::Utils::BuildOutput::State::Missing)
      oracle.usable?.should be_false
    end
  end

  # Same rule `hwaro deploy` applies: a tree stamped by serve carries dev URLs
  # and draft-inclusive routing, so it is not what a build would produce.
  it "refuses a tree carrying the dev marker even when it holds the file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      Hwaro::Utils::DevMarker.write(File.join(dir, "public"))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [] of String, tool: "check-links")
      oracle.state.should eq(Hwaro::Utils::BuildOutput::State::DevOutput)
      oracle.exists?("css/app.css").should be_false
      oracle.hint.to_s.should contain(Hwaro::Utils::DevMarker::FILENAME)
      oracle.hint.to_s.should contain("check-links")
    end
  end

  it "accepts a real build tree and stays quiet about it" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "content", "post.md"), "x")
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      File.touch(File.join(dir, "content", "post.md"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "public", "css", "app.css"), Time.utc(2026, 1, 2))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")])
      oracle.usable?.should be_true
      oracle.exists?("css/app.css").should be_true
      oracle.consulted?.should be_true
      oracle.hint.should be_nil
    end
  end

  it "flags a tree older than the newest source once it decided something" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      File.write(File.join(dir, "content", "post.md"), "x")
      File.touch(File.join(dir, "public", "css", "app.css"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content", "post.md"), Time.utc(2026, 2, 1))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")])
      oracle.exists?("css/app.css").should be_true
      oracle.hint.to_s.should contain("older than the newest source")
      oracle.hint.to_s.should contain("hwaro build")
    end
  end

  # Staleness is about evidence, not about the directory: a run that never
  # needed the tree has nothing to warn about, and paying for the source walk
  # would be pure cost.
  it "says nothing about a stale tree it never consulted" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public"))
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "public", "index.html"), "<html></html>")
      File.write(File.join(dir, "content", "post.md"), "x")
      File.touch(File.join(dir, "public", "index.html"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content", "post.md"), Time.utc(2026, 2, 1))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")])
      oracle.exists?("nothing/here.css").should be_false
      oracle.consulted?.should be_false
      oracle.hint.should be_nil
    end
  end

  # The false negative in #761: a deleted page leaves its route standing in
  # the output tree. Deleting only moves the PARENT directory's mtime, so a
  # file-only scan would call the tree fresh and validate a dead route.
  it "notices a deleted source through its parent directory's mtime" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public", "old"))
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "public", "old", "index.html"), "<html></html>")
      File.write(File.join(dir, "content", "keep.md"), "x")
      File.touch(File.join(dir, "public", "old", "index.html"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "content", "keep.md"), Time.utc(2026, 1, 1))
      # `content/old.md` was deleted after the build: only the directory moved.
      File.touch(File.join(dir, "content"), Time.utc(2026, 2, 1))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")])
      oracle.exists?("old/index.html").should be_true
      oracle.hint.to_s.should contain("older than the newest source")
    end
  end

  it "does not follow symlinks while scanning sources" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "public"))
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "public", "index.html"), "<html></html>")
      File.touch(File.join(dir, "public", "index.html"), Time.utc(2026, 1, 1))
      # A cycle: following it would recurse until the stack (or the budget)
      # gave out. Stamp the directory afterwards — creating an entry moves it.
      File.symlink(File.join(dir, "content"), File.join(dir, "content", "loop"))
      File.touch(File.join(dir, "content"), Time.utc(2026, 1, 1))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")])
      oracle.exists?("index.html").should be_true
      oracle.hint.should be_nil
    end
  end
end
