require "../../spec_helper"
require "../../../src/utils/file_safe"

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

    # Regression: an output_dir that is a dangling symlink (`public ->
    # nowhere`) made `Dir.exists?` false — it resolves the link — while
    # `Dir.mkdir` still hit EEXIST on the link itself, so the wrapper re-raised
    # a bare `File::AlreadyExistsError` ("File exists") that never mentioned
    # the symlink.
    it "raises a classified error for a dangling symlink instead of raw EEXIST" do
      Dir.mktmpdir do |root|
        link = File.join(root, "public")
        target = File.join(root, "nowhere")
        File.symlink(target, link)

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Utils::FileSafe.mkdir_p(link)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        err.message.to_s.should contain("public")
        err.message.to_s.should contain("nowhere")
        # Never create (or otherwise touch) whatever the link points at.
        Dir.exists?(target).should be_false
        File.exists?(target).should be_false
      end
    end

    # Same failure one level up: the leaf is fine, but a parent component of
    # the path is the dangling link, which is what a build hits on the first
    # `public/<section>/` it creates.
    it "names the dangling symlink when it is a parent component" do
      Dir.mktmpdir do |root|
        link = File.join(root, "public")
        File.symlink(File.join(root, "nowhere"), link)

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Utils::FileSafe.mkdir_p(File.join(link, "blog"))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        err.message.to_s.should contain("public")
      end
    end

    # A symlink that DOES resolve to a directory is a legitimate output_dir
    # (`public -> /var/www/site`) and must keep working untouched.
    it "succeeds when the path is a symlink to an existing directory" do
      Dir.mktmpdir do |root|
        real = File.join(root, "real")
        Dir.mkdir_p(real)
        link = File.join(root, "public")
        File.symlink(real, link)

        Hwaro::Utils::FileSafe.mkdir_p(File.join(link, "blog"))
        Dir.exists?(File.join(real, "blog")).should be_true
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

  # Characterisation coverage: `atomic_copy` is introduced by this fix, so
  # these examples cannot be run against the pre-fix tree. The pre-fix proof
  # for the defect it serves (a reader seeing a half-written file) is
  # end-to-end in spec/functional/parallel_write_race_spec.cr and
  # spec/unit/phases_write_spec.cr, which fail without it.
  describe ".atomic_copy" do
    it "copies to a new destination" do
      Dir.mktmpdir do |root|
        src = File.join(root, "src.css")
        dest = File.join(root, "dest.css")
        File.write(src, "a{color:red}")

        Hwaro::Utils::FileSafe.atomic_copy(src, dest)
        File.read(dest).should eq("a{color:red}")
        Dir.glob(File.join(root, "*.tmp")).should be_empty
      end
    end

    # The race window itself is not deterministic in a spec, so the invariant
    # is asserted through the property that produces it: a reader holding the
    # destination open across a replacement must keep seeing one complete
    # revision. That holds for temp-file-plus-rename and fails for the
    # truncate-and-stream `FileUtils.cp` this replaces. Both revisions are the
    # same length so only atomicity can satisfy the assertion.
    it "replaces an existing destination without truncating it in place" do
      Dir.mktmpdir do |root|
        src = File.join(root, "src.css")
        dest = File.join(root, "dest.css")
        old_bytes = "a{color:red }" * 20_000
        new_bytes = "a{color:blue}" * 20_000
        File.write(src, old_bytes)
        Hwaro::Utils::FileSafe.atomic_copy(src, dest)

        reader = File.open(dest)
        begin
          File.write(src, new_bytes)
          Hwaro::Utils::FileSafe.atomic_copy(src, dest)

          reader.gets_to_end.should eq(old_bytes)
        ensure
          reader.close
        end

        File.read(dest).should eq(new_bytes)
        Dir.glob(File.join(root, "*.tmp")).should be_empty
      end
    end

    # Parity with `FileUtils.cp`, which copies INTO a directory of that name.
    it "copies into a destination directory" do
      Dir.mktmpdir do |root|
        src = File.join(root, "logo.png")
        dest_dir = File.join(root, "images")
        Dir.mkdir_p(dest_dir)
        File.write(src, "bytes")

        Hwaro::Utils::FileSafe.atomic_copy(src, dest_dir)
        File.read(File.join(dest_dir, "logo.png")).should eq("bytes")
      end
    end

    it "leaves the destination and no temp file behind when the source is missing" do
      Dir.mktmpdir do |root|
        dest = File.join(root, "dest.txt")
        File.write(dest, "old")

        expect_raises(File::NotFoundError) do
          Hwaro::Utils::FileSafe.atomic_copy(File.join(root, "missing.txt"), dest)
        end

        File.read(dest).should eq("old")
        Dir.glob(File.join(root, "*.tmp")).should be_empty
      end
    end
  end
end
