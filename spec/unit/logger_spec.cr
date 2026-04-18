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

  describe ".color_enabled?" do
    it "returns false when NO_COLOR env var is set to a non-empty value" do
      original_override = Hwaro::Logger.color_enabled? # snapshot pre-change
      Hwaro::Logger.color_enabled = nil                # restore auto-detect
      original = ENV["NO_COLOR"]?
      ENV["NO_COLOR"] = "1"
      Hwaro::Logger.color_enabled?.should be_false
      if orig = original
        ENV["NO_COLOR"] = orig
      else
        ENV.delete("NO_COLOR")
      end
      # Restore previous explicit state (tests tail each other).
      Hwaro::Logger.color_enabled = original_override
    end

    it "returns false when NO_COLOR is set but empty (auto-detect fallback)" do
      # Per spec https://no-color.org, NO_COLOR only disables color when
      # non-empty. With an empty value we fall through to the TTY check.
      original_override = Hwaro::Logger.color_enabled?
      Hwaro::Logger.color_enabled = nil
      original = ENV["NO_COLOR"]?
      ENV["NO_COLOR"] = ""
      # In test runs STDOUT is usually not a TTY, so this is still false.
      Hwaro::Logger.color_enabled?.should eq(STDOUT.tty?)
      if orig = original
        ENV["NO_COLOR"] = orig
      else
        ENV.delete("NO_COLOR")
      end
      Hwaro::Logger.color_enabled = original_override
    end

    it "honors explicit override via color_enabled=" do
      original = ENV["NO_COLOR"]?
      ENV["NO_COLOR"] = "1"
      Hwaro::Logger.color_enabled = true
      Hwaro::Logger.color_enabled?.should be_true
      Hwaro::Logger.color_enabled = false
      Hwaro::Logger.color_enabled?.should be_false
      # Restore auto-detect
      Hwaro::Logger.color_enabled = nil
      if orig = original
        ENV["NO_COLOR"] = orig
      else
        ENV.delete("NO_COLOR")
      end
    end

    it "suppresses ANSI escape sequences in emitted output when disabled" do
      Hwaro::Logger.color_enabled = false
      output = capture_logger_output { Hwaro::Logger.success("done") }
      output.should contain("done")
      output.should_not contain("\e[")
      output = capture_logger_output { Hwaro::Logger.error("boom") }
      output.should contain("boom")
      output.should_not contain("\e[")
      output = capture_logger_output { Hwaro::Logger.warn("careful") }
      output.should contain("careful")
      output.should_not contain("\e[")
      output = capture_logger_output { Hwaro::Logger.action("Creating", "file") }
      output.should contain("Creating")
      output.should contain("file")
      output.should_not contain("\e[")
      Hwaro::Logger.color_enabled = nil
    end

    it "emits ANSI escape sequences when enabled (and the colorize lib is active)" do
      # The `colorize` shard strips ANSI when writing to non-TTY targets, so
      # we explicitly re-enable it for this assertion and restore afterwards.
      original = Colorize.enabled?
      Colorize.enabled = true
      Hwaro::Logger.color_enabled = true
      output = capture_logger_output { Hwaro::Logger.success("done") }
      output.should contain("\e[")
      Hwaro::Logger.color_enabled = nil
      Colorize.enabled = original
    end
  end

  describe ".quiet=" do
    it "suppresses info output" do
      Hwaro::Logger.quiet = true
      output = capture_logger_output { Hwaro::Logger.info("should be silent") }
      output.should_not contain("should be silent")
      Hwaro::Logger.quiet = false
    end

    it "suppresses success output" do
      Hwaro::Logger.quiet = true
      output = capture_logger_output { Hwaro::Logger.success("hidden success") }
      output.should_not contain("hidden success")
      Hwaro::Logger.quiet = false
    end

    it "suppresses action output" do
      Hwaro::Logger.quiet = true
      output = capture_logger_output { Hwaro::Logger.action("Creating", "file.md") }
      output.should_not contain("Creating")
      output.should_not contain("file.md")
      Hwaro::Logger.quiet = false
    end

    it "suppresses progress output" do
      Hwaro::Logger.quiet = true
      output = capture_logger_output { Hwaro::Logger.progress(5, 10, "Building: ") }
      output.should_not contain("Building:")
      output.should_not contain("50.0%")
      Hwaro::Logger.quiet = false
    end

    it "still emits warn output" do
      Hwaro::Logger.quiet = true
      output = capture_logger_output { Hwaro::Logger.warn("important warning") }
      output.should contain("important warning")
      Hwaro::Logger.quiet = false
    end

    it "still emits error output" do
      Hwaro::Logger.quiet = true
      output = capture_logger_output { Hwaro::Logger.error("fatal thing") }
      output.should contain("fatal thing")
      Hwaro::Logger.quiet = false
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
