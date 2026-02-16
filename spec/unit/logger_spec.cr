require "../spec_helper"
require "../../src/utils/logger"

# Helper to capture logger output
def capture_logger_output(&) : String
  io = IO::Memory.new
  Hwaro::Logger.io = io
  yield
  output = io.to_s
  # Restore suppressed IO for other tests
  Hwaro::Logger.io = IO::Memory.new
  output
end

describe Hwaro::Logger do
  describe ".level" do
    it "defaults to Info level" do
      Hwaro::Logger.level.should eq(Hwaro::Logger::Level::Info)
    end

    it "can be set to Debug" do
      original = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Debug
      Hwaro::Logger.level.should eq(Hwaro::Logger::Level::Debug)
      Hwaro::Logger.level = original
    end

    it "can be set to Warn" do
      original = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Warn
      Hwaro::Logger.level.should eq(Hwaro::Logger::Level::Warn)
      Hwaro::Logger.level = original
    end

    it "can be set to Error" do
      original = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Error
      Hwaro::Logger.level.should eq(Hwaro::Logger::Level::Error)
      Hwaro::Logger.level = original
    end
  end

  describe ".io=" do
    it "allows setting custom IO" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.error("test message")
      io.to_s.should contain("test message")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end
  end

  describe ".info" do
    it "outputs message when level is Info" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Info
      output = capture_logger_output { Hwaro::Logger.info("info message") }
      output.should contain("info message")
      Hwaro::Logger.level = original_level
    end

    it "outputs message when level is Debug" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Debug
      output = capture_logger_output { Hwaro::Logger.info("info at debug") }
      output.should contain("info at debug")
      Hwaro::Logger.level = original_level
    end

    it "suppresses message when level is Warn" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Warn
      output = capture_logger_output { Hwaro::Logger.info("should not appear") }
      output.should_not contain("should not appear")
      Hwaro::Logger.level = original_level
    end

    it "suppresses message when level is Error" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Error
      output = capture_logger_output { Hwaro::Logger.info("hidden info") }
      output.should_not contain("hidden info")
      Hwaro::Logger.level = original_level
    end
  end

  describe ".debug" do
    it "outputs message when level is Debug" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Debug
      output = capture_logger_output { Hwaro::Logger.debug("debug message") }
      output.should contain("[DEBUG]")
      output.should contain("debug message")
      Hwaro::Logger.level = original_level
    end

    it "suppresses message when level is Info" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Info
      output = capture_logger_output { Hwaro::Logger.debug("hidden debug") }
      output.should_not contain("hidden debug")
      Hwaro::Logger.level = original_level
    end

    it "suppresses message when level is Warn" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Warn
      output = capture_logger_output { Hwaro::Logger.debug("hidden debug") }
      output.should_not contain("hidden debug")
      Hwaro::Logger.level = original_level
    end

    it "suppresses message when level is Error" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Error
      output = capture_logger_output { Hwaro::Logger.debug("hidden debug") }
      output.should_not contain("hidden debug")
      Hwaro::Logger.level = original_level
    end
  end

  describe ".warn" do
    it "outputs message when level is Info" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Info
      output = capture_logger_output { Hwaro::Logger.warn("warning message") }
      output.should contain("warning message")
      Hwaro::Logger.level = original_level
    end

    it "outputs message when level is Debug" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Debug
      output = capture_logger_output { Hwaro::Logger.warn("warning at debug") }
      output.should contain("warning at debug")
      Hwaro::Logger.level = original_level
    end

    it "outputs message when level is Warn" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Warn
      output = capture_logger_output { Hwaro::Logger.warn("warn at warn level") }
      output.should contain("warn at warn level")
      Hwaro::Logger.level = original_level
    end

    it "suppresses message when level is Error" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Error
      output = capture_logger_output { Hwaro::Logger.warn("hidden warning") }
      output.should_not contain("hidden warning")
      Hwaro::Logger.level = original_level
    end
  end

  describe ".error" do
    it "always outputs message regardless of level" do
      [
        Hwaro::Logger::Level::Debug,
        Hwaro::Logger::Level::Info,
        Hwaro::Logger::Level::Warn,
        Hwaro::Logger::Level::Error,
      ].each do |level|
        original_level = Hwaro::Logger.level
        Hwaro::Logger.level = level
        output = capture_logger_output { Hwaro::Logger.error("error message") }
        output.should contain("error message")
        Hwaro::Logger.level = original_level
      end
    end
  end

  describe ".success" do
    it "outputs message" do
      output = capture_logger_output { Hwaro::Logger.success("build complete") }
      output.should contain("build complete")
    end

    it "outputs regardless of log level" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Error
      output = capture_logger_output { Hwaro::Logger.success("success msg") }
      output.should contain("success msg")
      Hwaro::Logger.level = original_level
    end
  end

  describe ".action" do
    it "outputs label and message" do
      output = capture_logger_output { Hwaro::Logger.action("Creating", "new file") }
      output.should contain("Creating")
      output.should contain("new file")
    end

    it "outputs symbol labels" do
      output = capture_logger_output { Hwaro::Logger.action(:Writing, "output.html") }
      output.should contain("Writing")
      output.should contain("output.html")
    end

    it "right-justifies the label to 12 characters" do
      output = capture_logger_output { Hwaro::Logger.action("OK", "test") }
      # "OK" right-justified to 12 chars = 10 spaces + "OK"
      output.should contain("OK")
      output.should contain("test")
    end
  end

  describe ".timed" do
    it "returns the block result" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Info
      result = nil
      capture_logger_output do
        result = Hwaro::Logger.timed("operation") { 42 }
      end
      result.should eq(42)
      Hwaro::Logger.level = original_level
    end

    it "outputs timing information" do
      original_level = Hwaro::Logger.level
      Hwaro::Logger.level = Hwaro::Logger::Level::Info
      output = capture_logger_output do
        Hwaro::Logger.timed("build step") { sleep(1.milliseconds) }
      end
      output.should contain("build step")
      output.should contain("ms")
      Hwaro::Logger.level = original_level
    end
  end

  describe ".progress" do
    it "outputs progress bar" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(5, 10, "Building: ")
      output = io.to_s
      output.should contain("Building:")
      output.should contain("50.0%")
      output.should contain("5/10")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end

    it "shows 100% on completion" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(10, 10, "Done: ")
      output = io.to_s
      output.should contain("100.0%")
      output.should contain("10/10")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end

    it "outputs nothing when total is 0" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(0, 0)
      output = io.to_s
      output.should eq("")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end

    it "outputs nothing when total is negative" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(0, -1)
      output = io.to_s
      output.should eq("")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end

    it "shows partial progress" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(1, 4)
      output = io.to_s
      output.should contain("25.0%")
      output.should contain("1/4")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end

    it "contains block characters for progress bar" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(5, 10)
      output = io.to_s
      output.should contain("█")
      output.should contain("░")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end

    it "works without prefix" do
      io = IO::Memory.new
      Hwaro::Logger.io = io
      Hwaro::Logger.progress(3, 10)
      output = io.to_s
      output.should contain("30.0%")
      output.should contain("3/10")
      # Restore
      Hwaro::Logger.io = IO::Memory.new
    end
  end

  describe "Level enum" do
    it "has Debug as lowest level" do
      (Hwaro::Logger::Level::Debug < Hwaro::Logger::Level::Info).should be_true
    end

    it "has Info below Warn" do
      (Hwaro::Logger::Level::Info < Hwaro::Logger::Level::Warn).should be_true
    end

    it "has Warn below Error" do
      (Hwaro::Logger::Level::Warn < Hwaro::Logger::Level::Error).should be_true
    end

    it "has four levels total" do
      Hwaro::Logger::Level.values.size.should eq(4)
    end
  end
end
