require "../../spec_helper"

describe "Fiber closure release (ext/fiber_closure_release)" do
  it "drops a finished fiber's block, so nothing it captured stays reachable through it" do
    payload = Array.new(16) { |i| "captured #{i}" }
    done = Channel(Int32).new(1)
    fiber = spawn { done.send(payload.size) }
    done.receive.should eq(16)
    # The send happens inside the block; the fiber still has to return and
    # run its ensure. Bounded: a fiber that never finishes fails the example.
    1000.times do
      break if fiber.dead?
      Fiber.yield
    end
    fiber.dead?.should be_true
    # The block captured `payload`/`done`; a dead fiber kept it (and through
    # it, e.g. a render worker's whole set of template variables) for as long
    # as a scheduler's run queue still held the fiber.
    fiber.@proc.closure?.should be_false
  end

  it "leaves a running fiber's block alone" do
    started = Channel(Nil).new(1)
    release = Channel(Nil).new(1)
    fiber = spawn do
      started.send(nil)
      release.receive
    end
    started.receive
    fiber.@proc.closure?.should be_true
    release.send(nil)
  end
end
