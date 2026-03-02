require "../spec_helper"
require "../../src/core/lifecycle/hooks"

describe Hwaro::Core::Lifecycle::HookResult do
  it "has Continue value" do
    Hwaro::Core::Lifecycle::HookResult::Continue.value.should eq(0)
  end

  it "has Skip value" do
    Hwaro::Core::Lifecycle::HookResult::Skip.value.should eq(1)
  end

  it "has Abort value" do
    Hwaro::Core::Lifecycle::HookResult::Abort.value.should eq(2)
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
        Hwaro::Core::Lifecycle::HookResult::Skip
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
