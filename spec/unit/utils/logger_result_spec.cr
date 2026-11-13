require "../../spec_helper"
require "../../../src/utils/logger"

describe "Hwaro::Logger.result / to_stderr" do
  it "result prints under --quiet and restores the flag" do
    io = IO::Memory.new
    Hwaro::Logger.io = io
    Hwaro::Logger.quiet = true
    begin
      Hwaro::Logger.info "chatter"
      Hwaro::Logger.result "answer"
      Hwaro::Logger.result { Hwaro::Logger.item("row") }
      Hwaro::Logger.quiet?.should be_true
      io.to_s.should contain("answer")
      io.to_s.should contain("row")
      io.to_s.should_not contain("chatter")
    ensure
      Hwaro::Logger.quiet = false
    end
  end

  it "to_stderr sends result lines to err_io and is silent under --quiet" do
    out = IO::Memory.new
    err = IO::Memory.new
    Hwaro::Logger.io = out
    Hwaro::Logger.err_io = err
    begin
      Hwaro::Logger.to_stderr { Hwaro::Logger.result "usage" }
      out.to_s.should be_empty
      err.to_s.should contain("usage")
      Hwaro::Logger.quiet = true
      err.clear
      Hwaro::Logger.to_stderr { Hwaro::Logger.result "usage" }
      err.to_s.should be_empty
    ensure
      Hwaro::Logger.quiet = false
    end
  end
end
