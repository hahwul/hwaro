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
  end
end
