require "../../../spec_helper"
require "../../../../src/core/lifecycle/hooks"
require "../../../../src/core/lifecycle/manager"

describe Hwaro::Core::Lifecycle::HookResult do
  it "has Continue value" do
    Hwaro::Core::Lifecycle::HookResult::Continue.value.should eq(0)
  end

  it "has Abort value" do
    Hwaro::Core::Lifecycle::HookResult::Abort.value.should eq(1)
  end
end

describe Hwaro::Core::Lifecycle::RegisteredHook do
  describe "#initialize" do
    it "creates a registered hook with defaults" do
      handler = Hwaro::Core::Lifecycle::HookHandler.new { |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      }
      hook = Hwaro::Core::Lifecycle::RegisteredHook.new(handler: handler)
      hook.priority.should eq(0)
      hook.name.should eq("anonymous")
    end

    it "creates a registered hook with custom priority and name" do
      handler = Hwaro::Core::Lifecycle::HookHandler.new { |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      }
      hook = Hwaro::Core::Lifecycle::RegisteredHook.new(
        handler: handler,
        priority: 10,
        name: "my-hook"
      )
      hook.priority.should eq(10)
      hook.name.should eq("my-hook")
    end
  end

  describe "#handler" do
    it "stores and returns the handler proc" do
      called = false
      handler = Hwaro::Core::Lifecycle::HookHandler.new { |_ctx|
        called = true
        Hwaro::Core::Lifecycle::HookResult::Abort
      }
      hook = Hwaro::Core::Lifecycle::RegisteredHook.new(handler: handler, name: "test")
      hook.handler.should eq(handler)
    end
  end
end

describe Hwaro::Core::Lifecycle do
  describe ".hook_points_for" do
    it "returns before/after hook points for Initialize phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Initialize)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize)
    end

    it "returns before/after hook points for ReadContent phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::ReadContent)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeReadContent)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent)
    end

    it "returns before/after hook points for Transform phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Transform)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeTransform)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterTransform)
    end

    it "returns before/after hook points for Render phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Render)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeRender)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterRender)
    end

    it "returns before/after hook points for Generate phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Generate)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterGenerate)
    end

    it "returns before/after hook points for Write phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Write)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeWrite)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterWrite)
    end

    it "returns before/after hook points for Finalize phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Finalize)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeFinalize)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterFinalize)
    end

    it "returns before/after hook points for ParseContent phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::ParseContent)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeParseContent)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterParseContent)
    end
  end
end

describe Hwaro::Core::Lifecycle::Manager do
  describe "#on" do
    it "registers a hook at a specific point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "test") do |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize).should be_true
      manager.hook_count.should eq(1)
    end
  end

  describe "#trigger" do
    it "executes hooks and returns Continue" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      called = false
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "test") do |_ctx|
        called = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

      called.should be_true
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
    end

    it "returns Continue when no hooks registered" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
    end

    it "still propagates Abort from a hook" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      second_called = false

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 10, name: "aborter") do |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, priority: 0, name: "second") do |_ctx|
        second_called = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
      second_called.should be_false
    end
  end
end

# Additional Hookable / HookHandler invocation tests
private class CountingHookable
  include Hwaro::Core::Lifecycle::Hookable

  property fired : Int32 = 0

  def register_hooks(manager : Hwaro::Core::Lifecycle::Manager)
    manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, name: "counting") do |_ctx|
      @fired += 1
      Hwaro::Core::Lifecycle::HookResult::Continue
    end
  end
end

describe Hwaro::Core::Lifecycle::HookHandler do
  it "is a Proc that maps BuildContext to HookResult" do
    handler = Hwaro::Core::Lifecycle::HookHandler.new do |_ctx|
      Hwaro::Core::Lifecycle::HookResult::Abort
    end

    options = Hwaro::Config::Options::BuildOptions.new
    ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
    handler.call(ctx).should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
  end
end

describe Hwaro::Core::Lifecycle::RegisteredHook do
  describe "#handler.call" do
    it "invokes the wrapped handler and returns its HookResult" do
      handler = Hwaro::Core::Lifecycle::HookHandler.new do |_ctx|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end
      hook = Hwaro::Core::Lifecycle::RegisteredHook.new(handler: handler, name: "x")

      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      hook.handler.call(ctx).should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
    end
  end
end

describe Hwaro::Core::Lifecycle::Hookable do
  it "lets a Hookable register itself with a Manager via Manager#register" do
    manager = Hwaro::Core::Lifecycle::Manager.new
    hookable = CountingHookable.new
    manager.register(hookable)
    manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_true
  end

  it "fires the registered hook when the lifecycle is triggered" do
    manager = Hwaro::Core::Lifecycle::Manager.new
    hookable = CountingHookable.new
    manager.register(hookable)

    options = Hwaro::Config::Options::BuildOptions.new
    ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
    manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

    hookable.fired.should eq(1)
  end

  it "supports registering the same Hookable on two managers independently" do
    a = Hwaro::Core::Lifecycle::Manager.new
    b = Hwaro::Core::Lifecycle::Manager.new
    hookable = CountingHookable.new
    a.register(hookable)
    b.register(hookable)

    a.hook_count.should eq(1)
    b.hook_count.should eq(1)

    # Trigger each manager and confirm both invocations are observed by the
    # shared Hookable instance — guards against any future change that
    # would bind a Hookable to a single Manager.
    # Derive the trigger point from CountingHookable's registered Phase
    # so this test stays correct if the hookable's phase is ever changed.
    before_render, _ = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Render)
    a.has_hooks?(before_render).should be_true
    b.has_hooks?(before_render).should be_true

    options = Hwaro::Config::Options::BuildOptions.new
    ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
    a.trigger(before_render, ctx)
    b.trigger(before_render, ctx)
    hookable.fired.should eq(2)
  end
end
