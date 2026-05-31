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

# Run a block with human-readable Logger output captured, returning everything
# written to the logger as a String. All global Logger state (io, level, quiet)
# is saved and restored so examples cannot leak state into one another.
def with_captured_log(&) : String
  previous_io = Hwaro::Logger.io
  previous_level = Hwaro::Logger.level
  previous_quiet = Hwaro::Logger.quiet?
  sink = IO::Memory.new
  Hwaro::Logger.io = sink
  Hwaro::Logger.level = Hwaro::Logger::Level::Info
  Hwaro::Logger.quiet = false
  begin
    yield
    sink.to_s
  ensure
    Hwaro::Logger.io = previous_io
    Hwaro::Logger.level = previous_level
    Hwaro::Logger.quiet = previous_quiet
  end
end
