require "../../spec_helper"
require "../../../src/utils/hwaro_dir"

# `.hwaro/` self-ignore: the workspace directory (serve output, remote-data
# cache) writes a one-line `*` .gitignore into itself so none of it ever
# shows up in `git status` — including in repositories whose top-level
# .gitignore predates the directory.
describe Hwaro::Utils::HwaroDir do
  describe ".ensure_self_ignore" do
    it "writes a self-ignoring .gitignore into a .hwaro directory" do
      Dir.mktmpdir do |dir|
        hwaro_dir = File.join(dir, ".hwaro")
        Dir.mkdir_p(hwaro_dir)

        Hwaro::Utils::HwaroDir.ensure_self_ignore(hwaro_dir)

        File.read(File.join(hwaro_dir, ".gitignore")).should eq("*\n")
      end
    end

    it "never overwrites an existing .gitignore" do
      # A user who deliberately un-ignored parts of `.hwaro/` keeps their
      # file — hygiene must not fight the user.
      Dir.mktmpdir do |dir|
        hwaro_dir = File.join(dir, ".hwaro")
        Dir.mkdir_p(hwaro_dir)
        custom = "*\n!serve/\n"
        File.write(File.join(hwaro_dir, ".gitignore"), custom)

        Hwaro::Utils::HwaroDir.ensure_self_ignore(hwaro_dir)

        File.read(File.join(hwaro_dir, ".gitignore")).should eq(custom)
      end
    end

    it "refuses any directory not named .hwaro" do
      # The guard that keeps a custom remote-data cache_dir (or a spec tmp
      # dir) from getting .gitignore files sprinkled into the user's tree.
      Dir.mktmpdir do |dir|
        other = File.join(dir, "cache")
        Dir.mkdir_p(other)

        Hwaro::Utils::HwaroDir.ensure_self_ignore(other)
        Hwaro::Utils::HwaroDir.ensure_self_ignore(dir)

        File.exists?(File.join(other, ".gitignore")).should be_false
        File.exists?(File.join(dir, ".gitignore")).should be_false
      end
    end

    it "is a no-op when the directory does not exist" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, ".hwaro")

        Hwaro::Utils::HwaroDir.ensure_self_ignore(missing)

        Dir.exists?(missing).should be_false
      end
    end
  end
end
