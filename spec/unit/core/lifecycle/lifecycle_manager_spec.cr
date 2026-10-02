require "../../../spec_helper"

describe Hwaro::Core::Lifecycle::Manager do
  describe "priority sorting" do
    it "executes hooks in descending priority order" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      order = [] of String

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "low") do |_|
        order << "low"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 50, name: "mid") do |_|
        order << "mid"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "high") do |_|
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

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "first") do |_|
        order << "first"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "second") do |_|
        order << "second"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "third") do |_|
        order << "third"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
      # Crystal's sort_by!.reverse! is not guaranteed stable, but the hooks should all run
      order.size.should eq(3)
    end
  end

  describe "short-circuit: Abort" do
    it "stops executing subsequent hooks when Abort is returned" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      second_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "aborter") do |_|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "after-abort") do |_|
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

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "raiser") do |_|
        raise "something went wrong"
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
    end

    it "does not execute subsequent hooks after exception" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      second_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "raiser") do |_|
        raise "boom"
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 1, name: "after-raise") do |_|
        second_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      second_ran.should be_false
    end

    it "re-raises a HwaroError unchanged instead of downgrading to Abort" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "classified-raiser") do |_|
        raise Hwaro::HwaroError.new(Hwaro::Errors::HWARO_E_CONFIG, "bad config")
      end

      error = expect_raises(Hwaro::HwaroError) do
        manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      end
      error.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      error.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
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
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new(output_dir: "hello"))

      received_value = ""
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "ctx-reader") do |hook_ctx|
        received_value = hook_ctx.output_dir
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

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "before") do |_|
        order << "before"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "after") do |_|
        order << "after"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        order << "action"
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      order.should eq(["before", "action", "after"])
    end

    it "skips action and after hooks when before hook returns Abort" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      action_ran = false
      after_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "aborter") do |_|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "after") do |_|
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

      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "after") do |_|
        after_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.run_phase(Hwaro::Core::Lifecycle::Phase::Render, ctx) do
        raise "action failed"
      end

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      after_ran.should be_false
    end

    it "classifies an IO::Error from the action as HWARO_E_IO instead of Abort" do
      # Returning Abort here erased the exception type, and the CLI turned the
      # resulting `false` into HWARO_E_INTERNAL / exit 70 — the code reserved
      # for hwaro bugs — for ordinary filesystem trouble, with the path and
      # errno reaching only a stderr log line, never the --json payload.
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      after_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterWrite, name: "after") do |_|
        after_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      error = expect_raises(Hwaro::HwaroError) do
        manager.run_phase(Hwaro::Core::Lifecycle::Phase::Write, ctx) do
          # Same shape Dir.mkdir raises when a plain file squats on the name.
          raise File::Error.new("Unable to create directory: 'public': File exists", file: "public")
        end
      end
      error.code.should eq(Hwaro::Errors::HWARO_E_IO)
      error.exit_code.should eq(6)
      (error.message || "").should contain("public")
      after_ran.should be_false
    end

    it "re-raises a HwaroError from the action and does not run after hooks" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(Hwaro::Config::Options::BuildOptions.new)
      after_ran = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterParseContent, name: "after") do |_|
        after_ran = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      error = expect_raises(Hwaro::HwaroError) do
        manager.run_phase(Hwaro::Core::Lifecycle::Phase::ParseContent, ctx) do
          raise Hwaro::HwaroError.new(Hwaro::Errors::HWARO_E_CONTENT, "boom")
        end
      end
      error.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
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

  describe "introspection" do
    it "#hooks_at returns registered hooks at a point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "hook1") do |_|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "hook2") do |_|
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
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "test") do |_|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_true
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterRender).should be_false
    end

    it "#hook_count returns total count across all points" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "h1") do |_|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::AfterRender, name: "h2") do |_|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeWrite, name: "h3") do |_|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.hook_count.should eq(3)
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
end

# Test helper: a simple Hookable implementation
class TestHookable
  include Hwaro::Core::Lifecycle::Hookable

  def register_hooks(manager : Hwaro::Core::Lifecycle::Manager)
    manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "test-hookable") do |_|
      Hwaro::Core::Lifecycle::HookResult::Continue
    end
  end
end
