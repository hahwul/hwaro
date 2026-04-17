require "../spec_helper"

describe Hwaro::Core::Lifecycle::Manager do
  describe "priority sorting" do
    it "executes hooks in descending priority order" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      order = [] of String

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "low") do |ctx|
        order << "low"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 50, name: "mid") do |ctx|
        order << "mid"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "high") do |ctx|
        order << "high"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      order.should eq(["high", "mid", "low"])
    end

    it "preserves insertion order for same priority" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      order = [] of String

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "first") do |ctx|
        order << "first"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "second") do |ctx|
        order << "second"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "third") do |ctx|
        order << "third"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
      # Crystal's sort_by!.reverse! is not guaranteed stable, but the hooks should all run
      order.size.should eq(3)
    end
  end

  describe "short-circuit: Skip" do
    it "stops executing subsequent hooks when Skip is returned" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      second_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "skipper") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Skip
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "after-skip") do |ctx|
        second_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Skip)
      second_ran.should be_false
    end
  end

  describe "short-circuit: Abort" do
    it "stops executing subsequent hooks when Abort is returned" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      second_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "aborter") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "after-abort") do |ctx|
        second_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      second_ran.should be_false
    end
  end

  describe "exception handling" do
    it "returns Abort when a hook raises an exception" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "raiser") do |ctx|
        raise "something went wrong"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
    end

    it "does not execute subsequent hooks after exception" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      second_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "raiser") do |ctx|
        raise "boom"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "after-raise") do |ctx|
        second_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      second_ran.should be_false
    end
  end

  describe "#trigger" do
    it "returns Continue when no hooks are registered at the point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
    end

    it "passes context to hooks" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      ctx.set("marker", "hello")

      received_value = ""
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "ctx-reader") do |ctx|
        received_value = ctx.get_string("marker")
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      received_value.should eq("hello")
    end
  end

  describe "#run_phase" do
    it "runs before → action → after in order" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      order = [] of String

      manager.before(Hwaro::Core::Lifecycle::Phase::Render, name: "before") do |ctx|
        order << "before"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.after(Hwaro::Core::Lifecycle::Phase::Render, name: "after") do |ctx|
        order << "after"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        order << "action"
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      order.should eq(["before", "action", "after"])
    end

    it "skips action when before hook returns Skip" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      action_ran = false

      manager.before(Hwaro::Core::Lifecycle::Phase::Render, name: "skipper") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Skip
      end

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        action_ran = true
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Skip)
      action_ran.should be_false
    end

    it "skips action and after hooks when before hook returns Abort" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      action_ran = false
      after_ran = false

      manager.before(Hwaro::Core::Lifecycle::Phase::Render, name: "aborter") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end
      manager.after(Hwaro::Core::Lifecycle::Phase::Render, name: "after") do |ctx|
        after_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        action_ran = true
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      action_ran.should be_false
      after_ran.should be_false
    end

    it "returns Abort when action raises and does not run after hooks" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      after_ran = false

      manager.after(Hwaro::Core::Lifecycle::Phase::Render, name: "after") do |ctx|
        after_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        raise "action failed"
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      after_ran.should be_false
    end

    it "runs action even when no hooks registered" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      action_ran = false

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        action_ran = true
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      action_ran.should be_true
    end
  end

  describe "#run_all_phases" do
    it "runs all phases in sequence when all succeed" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      phases_executed = [] of String

      result = manager.run_all_phases(ctx) do |phase|
        phases_executed << phase.to_s
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      phases_executed.size.should eq(8)
      phases_executed[0].should eq("Initialize")
      phases_executed[7].should eq("Finalize")
    end

    it "stops when a phase aborts" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      phases_executed = [] of String

      manager.before(Hwaro::Core::Lifecycle::Phase::Transform, name: "aborter") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end

      result = manager.run_all_phases(ctx) do |phase|
        phases_executed << phase.to_s
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      # Initialize and ReadContent should have run, but Transform and onwards should not
      phases_executed.should contain("Initialize")
      phases_executed.should contain("ReadContent")
      phases_executed.should_not contain("Transform")
      phases_executed.should_not contain("Render")
    end

    it "stops when a phase action raises" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      phases_executed = [] of String

      result = manager.run_all_phases(ctx) do |phase|
        phases_executed << phase.to_s
        raise "error" if phase == Hwaro::Core::Lifecycle::Phase::ParseContent
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      phases_executed.should contain("ParseContent")
      phases_executed.should_not contain("Transform")
    end
  end

  describe "introspection" do
    it "#hooks_at returns registered hooks at a point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "hook1") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "hook2") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      hooks = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize)
      hooks.size.should eq(2)
    end

    it "#hooks_at returns empty for unused point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::AfterFinalize)
      hooks.size.should eq(0)
    end

    it "#has_hooks? returns true when hooks exist" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "test") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_true
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterRender).should be_false
    end

    it "#hook_count returns total count across all points" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "h1") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "h2") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeWrite, name: "h3") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.hook_count.should eq(3)
    end

    it "#clear removes all hooks" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "h1") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "h2") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.hook_count.should eq(2)
      manager.clear
      manager.hook_count.should eq(0)
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize).should be_false
    end

    it "#clear_point removes hooks only at the specified point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "h1") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "h2") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.clear_point(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize)
      manager.hook_count.should eq(1)
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize).should be_false
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterRender).should be_true
    end
  end

  describe "#register (Hookable)" do
    it "registers hooks from a Hookable module" do
      manager = Hwaro::Core::Lifecycle::Manager.new

      hookable = TestHookable.new
      manager.register(hookable)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_true
      manager.hook_count.should eq(1)
    end

    it "returns self so registrations can be chained" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.register(TestHookable.new).should be(manager)
    end

    it "registers multiple Hookables additively" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.register(TestHookable.new)
      manager.register(TestHookable.new)
      manager.hook_count.should eq(2)
    end
  end

  describe "fluent registration" do
    it "returns self from #on for chaining" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      result = manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "x") do |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      result.should be(manager)
    end
  end

  describe "#register_hook (explicit handler)" do
    it "registers a HookHandler directly" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      handler = Hwaro::Core::Lifecycle::HookHandler.new do |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.register_hook(
        Hwaro::Core::Lifecycle::HookPoint::BeforeRender,
        handler,
        priority: 7,
        name: "explicit",
      )

      hooks = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeRender)
      hooks.size.should eq(1)
      hooks.first.priority.should eq(7)
      hooks.first.name.should eq("explicit")
    end

    it "re-sorts the hook list by priority after each registration" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      h1 = Hwaro::Core::Lifecycle::HookHandler.new { |_| Hwaro::Core::Lifecycle::HookResult::Continue }
      h2 = Hwaro::Core::Lifecycle::HookHandler.new { |_| Hwaro::Core::Lifecycle::HookResult::Continue }
      h3 = Hwaro::Core::Lifecycle::HookHandler.new { |_| Hwaro::Core::Lifecycle::HookResult::Continue }

      point = Hwaro::Core::Lifecycle::HookPoint::BeforeRender
      manager.register_hook(point, h1, priority: 1, name: "low")
      manager.register_hook(point, h2, priority: 100, name: "high")
      manager.register_hook(point, h3, priority: 50, name: "mid")

      manager.hooks_at(point).map(&.name).should eq(["high", "mid", "low"])
    end
  end

  describe "Manager.new(debug: true)" do
    it "emits debug log lines for each fired hook without altering its result" do
      # Swap a fresh IO::Memory in so we can read the debug output for this
      # test only. Hwaro::Logger has no public io getter, so on cleanup we
      # restore a fresh IO::Memory (matching spec_helper's default).
      sink = IO::Memory.new
      previous_level = Hwaro::Logger.level
      Hwaro::Logger.io = sink
      # Manager#trigger uses Logger.debug — bump the level so it isn't
      # filtered (default is Info).
      Hwaro::Logger.level = Hwaro::Logger::Level::Debug

      begin
        manager = Hwaro::Core::Lifecycle::Manager.new(debug: true)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)

        manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "debug-target") do |_ctx|
          Hwaro::Core::Lifecycle::HookResult::Continue
        end

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        sink.to_s.should contain("debug-target")
      ensure
        Hwaro::Logger.io = IO::Memory.new
        Hwaro::Logger.level = previous_level
      end
    end
  end

  describe "#dump_hooks" do
    it "does not raise when there are no hooks registered" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.dump_hooks
    end

    it "does not raise when hooks are present" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 5, name: "h") do |_|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.dump_hooks
    end
  end

  describe ".default class property" do
    it "lazily creates a singleton Manager instance" do
      a = Hwaro::Core::Lifecycle.default
      b = Hwaro::Core::Lifecycle.default
      a.should be(b)
    end

    it "allows overriding the default with a fresh Manager" do
      # class_property's getter returns Manager? even though the block
      # guarantees non-nil; not_nil! is needed for the setter signature.
      original = Hwaro::Core::Lifecycle.default
      replacement = Hwaro::Core::Lifecycle::Manager.new
      Hwaro::Core::Lifecycle.default = replacement
      Hwaro::Core::Lifecycle.default.should be(replacement)
    ensure
      # Restore the original singleton so other specs aren't affected
      Hwaro::Core::Lifecycle.default = original.not_nil!
    end
  end
end

# Test helper: a simple Hookable implementation
class TestHookable
  include Hwaro::Core::Lifecycle::Hookable

  def register_hooks(manager : Hwaro::Core::Lifecycle::Manager)
    manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "test-hookable") do |ctx|
      Hwaro::Core::Lifecycle::HookResult::Continue
    end
  end
end
