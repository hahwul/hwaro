require "../../spec_helper"

describe Hwaro::Utils::OutputOwnership do
  describe ".clearable?" do
    it "treats a confirmed serve marker as owned" do
      Dir.mktmpdir do |dir|
        Hwaro::Utils::DevMarker.write(dir)
        Hwaro::Utils::OutputOwnership.clearable?("shared", dir, dir).should be_true
      end
    end

    it "does not treat an unreadable .hwaro-dev as owned" do
      posix_only!("chmod can't make a file unreadable on Windows")
      Dir.mktmpdir do |dir|
        marker = File.join(dir, Hwaro::Utils::DevMarker::FILENAME)
        File.write(marker, Hwaro::Utils::DevMarker::CONTENT)
        File.chmod(marker, 0o000)
        begin
          Hwaro::Utils::DevMarker.present?(dir).should be_true
          Hwaro::Utils::DevMarker.present?(dir, fail_closed: false).should be_false
          Hwaro::Utils::OutputOwnership.clearable?("shared", dir, dir).should be_false
        ensure
          File.chmod(marker, 0o644)
        end
      end
    end

    it "keeps owning an in-project output directory after the project moves" do
      Dir.mktmpdir do |base|
        real = ->(p : String) { Hwaro::Utils::PathUtils.resolved_real_path(p) }
        old_root = File.join(base, "a")
        Dir.mkdir_p(File.join(old_root, "dist"))
        Hwaro::Utils::OutputOwnership.record(real.call(File.join(old_root, "dist")), real.call(old_root))

        new_root = File.join(base, "b")
        File.rename(old_root, new_root)
        Hwaro::Utils::OutputOwnership.clearable?("dist", real.call(File.join(new_root, "dist")), real.call(new_root)).should be_true
        # An output outside the project stays recorded by its absolute path.
        Hwaro::Utils::OutputOwnership.clearable?("x", real.call(File.join(base, "x")), real.call(new_root)).should be_false
      end
    end
  end
end
