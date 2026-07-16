require "../spec_helper"
require "../../src/utils/file_safe"

describe Hwaro::Utils::FileSafe do
  describe ".mkdir_p" do
    it "creates a nested directory" do
      Dir.mktmpdir do |root|
        target = File.join(root, "a", "b", "c")
        Hwaro::Utils::FileSafe.mkdir_p(target)
        Dir.exists?(target).should be_true
      end
    end

    it "is a no-op when the directory already exists" do
      Dir.mktmpdir do |root|
        target = File.join(root, "exists")
        Dir.mkdir_p(target)
        Hwaro::Utils::FileSafe.mkdir_p(target)
        Dir.exists?(target).should be_true
      end
    end

    it "raises when the path exists as a file" do
      Dir.mktmpdir do |root|
        path = File.join(root, "file")
        File.write(path, "hi")
        expect_raises(File::AlreadyExistsError) do
          Hwaro::Utils::FileSafe.mkdir_p(path)
        end
      end
    end

    # Drives many fibers at the same shared parent so the per-component race
    # window is exercised. Pre-fix, EEXIST on a shared parent surfaced as
    # "Unable to create directory: '…': File exists" because the wrapper's
    # whole-call retry could re-race and the leaf-only fallback check was
    # false.
    #
    # Note: meaningful only under `-Dpreview_mt`. In ST mode the syscalls
    # serialize and the race window never opens, so this test still asserts
    # the post-conditions but cannot catch an MT regression.
    it "tolerates concurrent creation of siblings under a shared parent" do
      Dir.mktmpdir do |root|
        # Multiple shared parents (deep tree) amplify the cascading race
        # that the single-retry implementation could not absorb.
        base = File.join(root, "ko", "development")

        worker_count = 32
        done = Channel(Exception?).new(worker_count)

        worker_count.times do |i|
          spawn do
            Hwaro::Utils::FileSafe.mkdir_p(File.join(base, "page_#{i}"))
            done.send(nil)
          rescue ex
            done.send(ex)
          end
        end

        errors = [] of Exception
        worker_count.times do
          if err = done.receive
            errors << err
          end
        end

        errors.should be_empty
        worker_count.times do |i|
          Dir.exists?(File.join(base, "page_#{i}")).should be_true
        end
      end
    end
  end

  describe ".atomic_write" do
    it "writes content to a new file" do
      Dir.mktmpdir do |root|
        path = File.join(root, "index.html")
        Hwaro::Utils::FileSafe.atomic_write(path, "<p>hello</p>")
        File.read(path).should eq("<p>hello</p>")
      end
    end

    it "replaces an existing file's content" do
      Dir.mktmpdir do |root|
        path = File.join(root, "index.html")
        File.write(path, "old bytes")
        Hwaro::Utils::FileSafe.atomic_write(path, "new bytes")
        File.read(path).should eq("new bytes")
      end
    end

    it "leaves no temp-file siblings behind" do
      Dir.mktmpdir do |root|
        path = File.join(root, "index.html")
        Hwaro::Utils::FileSafe.atomic_write(path, "content")
        Dir.glob(File.join(root, "*.tmp")).should be_empty
        Dir.children(root).should eq(["index.html"])
      end
    end
  end
end
