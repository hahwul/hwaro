require "spec"
require "../src/hwaro"

# Suppress Logger output during tests
Hwaro::Logger.io = IO::Memory.new

# Helper for creating temp directories in tests
class Dir
  def self.mktmpdir(&)
    path = File.tempname("hwaro_test")
    FileUtils.mkdir_p(path)
    begin
      yield path
    ensure
      FileUtils.rm_rf(path)
    end
  end
end
