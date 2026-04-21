require "../spec_helper"
require "../../src/core/lifecycle/phases"

describe Hwaro::Core::Lifecycle do
  describe ".hook_points_for" do
    it "returns correct hook points for Initialize phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Initialize)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize)
    end

    it "returns correct hook points for ReadContent phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::ReadContent)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeReadContent)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent)
    end

    it "returns correct hook points for ParseContent phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::ParseContent)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeParseContent)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterParseContent)
    end

    it "returns correct hook points for Transform phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Transform)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeTransform)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterTransform)
    end

    it "returns correct hook points for Render phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Render)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeRender)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterRender)
    end

    it "returns correct hook points for Generate phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Generate)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterGenerate)
    end

    it "returns correct hook points for Write phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Write)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeWrite)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterWrite)
    end

    it "returns correct hook points for Finalize phase" do
      before, after = Hwaro::Core::Lifecycle.hook_points_for(Hwaro::Core::Lifecycle::Phase::Finalize)
      before.should eq(Hwaro::Core::Lifecycle::HookPoint::BeforeFinalize)
      after.should eq(Hwaro::Core::Lifecycle::HookPoint::AfterFinalize)
    end

    it "returns a tuple of two HookPoints for every phase" do
      Hwaro::Core::Lifecycle::Phase.each do |phase|
        before, after = Hwaro::Core::Lifecycle.hook_points_for(phase)
        before.should be_a(Hwaro::Core::Lifecycle::HookPoint)
        after.should be_a(Hwaro::Core::Lifecycle::HookPoint)
      end
    end

    it "before hook point name starts with Before" do
      Hwaro::Core::Lifecycle::Phase.each do |phase|
        before, _ = Hwaro::Core::Lifecycle.hook_points_for(phase)
        before.to_s.should start_with("Before")
      end
    end

    it "after hook point name starts with After" do
      Hwaro::Core::Lifecycle::Phase.each do |phase|
        _, after = Hwaro::Core::Lifecycle.hook_points_for(phase)
        after.to_s.should start_with("After")
      end
    end
  end

  describe "Phase enum" do
    it "has 8 phases" do
      Hwaro::Core::Lifecycle::Phase.values.size.should eq(8)
    end

    it "phases are in correct build order" do
      phases = Hwaro::Core::Lifecycle::Phase.values
      phases[0].should eq(Hwaro::Core::Lifecycle::Phase::Initialize)
      phases[1].should eq(Hwaro::Core::Lifecycle::Phase::ReadContent)
      phases[2].should eq(Hwaro::Core::Lifecycle::Phase::ParseContent)
      phases[3].should eq(Hwaro::Core::Lifecycle::Phase::Transform)
      phases[4].should eq(Hwaro::Core::Lifecycle::Phase::Render)
      phases[5].should eq(Hwaro::Core::Lifecycle::Phase::Generate)
      phases[6].should eq(Hwaro::Core::Lifecycle::Phase::Write)
      phases[7].should eq(Hwaro::Core::Lifecycle::Phase::Finalize)
    end
  end

  describe "HookPoint enum" do
    it "has 16 hook points (before/after for each phase)" do
      Hwaro::Core::Lifecycle::HookPoint.values.size.should eq(16)
    end

    it "has matching before/after pairs" do
      hook_points = Hwaro::Core::Lifecycle::HookPoint.values
      before_hooks = hook_points.select(&.to_s.starts_with?("Before"))
      after_hooks = hook_points.select(&.to_s.starts_with?("After"))

      before_hooks.size.should eq(8)
      after_hooks.size.should eq(8)
    end
  end
end
