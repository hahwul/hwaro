require "../spec_helper"

describe Hwaro::Profiler do
  describe "#initialize" do
    it "creates a disabled profiler by default" do
      profiler = Hwaro::Profiler.new
      profiler.enabled?.should be_false
    end

    it "creates an enabled profiler when specified" do
      profiler = Hwaro::Profiler.new(enabled: true)
      profiler.enabled?.should be_true
    end
  end

  describe "#start_phase and #end_phase" do
    it "records phase timing when enabled" do
      profiler = Hwaro::Profiler.new(enabled: true)
      profiler.start

      profiler.start_phase("TestPhase")
      # Simulate some work
      sleep 10.milliseconds
      profiler.end_phase

      # The profiler should have recorded this phase
      output = IO::Memory.new
      profiler.report(output)
      output.to_s.should contain("TestPhase")
    end

    it "does nothing when profiler is disabled" do
      profiler = Hwaro::Profiler.new(enabled: false)
      profiler.start

      profiler.start_phase("TestPhase")
      sleep 10.milliseconds
      profiler.end_phase

      # Report should be empty when disabled
      output = IO::Memory.new
      profiler.report(output)
      output.to_s.should eq("")
    end
  end

  describe "#report" do
    it "outputs profile information when enabled and has phases" do
      profiler = Hwaro::Profiler.new(enabled: true)
      profiler.start

      profiler.start_phase("Initialize")
      profiler.end_phase

      profiler.start_phase("Render")
      sleep 10.milliseconds
      profiler.end_phase

      output = IO::Memory.new
      profiler.report(output)
      result = output.to_s

      result.should contain("Build Profile")
      result.should contain("Initialize")
      result.should contain("Render")
      result.should contain("Total")
    end

    it "does nothing when disabled" do
      profiler = Hwaro::Profiler.new(enabled: false)
      output = IO::Memory.new
      profiler.report(output)
      output.to_s.should eq("")
    end
  end

  describe "#total_elapsed" do
    it "returns 0 if not started" do
      profiler = Hwaro::Profiler.new(enabled: true)
      profiler.total_elapsed.should eq(0.0)
    end

    it "returns elapsed time after start" do
      profiler = Hwaro::Profiler.new(enabled: true)
      profiler.start
      sleep 10.milliseconds
      profiler.total_elapsed.should be > 0.0
    end
  end
end
