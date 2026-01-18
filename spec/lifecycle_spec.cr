require "./spec_helper"

describe Hwaro::Core::Lifecycle do
  describe Hwaro::Core::Lifecycle::Phase do
    it "has all required phases" do
      Hwaro::Core::Lifecycle::Phase::Initialize.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::ReadContent.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::ParseContent.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::Transform.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::Render.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::Generate.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::Write.should_not be_nil
      Hwaro::Core::Lifecycle::Phase::Finalize.should_not be_nil
    end
  end

  describe Hwaro::Core::Lifecycle::HookPoint do
    it "has before/after points for each phase" do
      Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize.should_not be_nil
      Hwaro::Core::Lifecycle::HookPoint::AfterInitialize.should_not be_nil
      Hwaro::Core::Lifecycle::HookPoint::BeforeRender.should_not be_nil
      Hwaro::Core::Lifecycle::HookPoint::AfterRender.should_not be_nil
    end
  end

  describe Hwaro::Core::Lifecycle::Manager do
    it "initializes with empty hooks" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.hook_count.should eq(0)
    end

    it "can register hooks at specific points" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "test") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.hook_count.should eq(1)
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize).should be_true
    end

    it "can register hooks using before/after helpers" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.before(Hwaro::Core::Lifecycle::Phase::Render, name: "before-render") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.after(Hwaro::Core::Lifecycle::Phase::Render, name: "after-render") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.hook_count.should eq(2)
    end

    it "triggers hooks and returns Continue by default" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      triggered = false
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "test") do |ctx|
        triggered = true
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      triggered.should be_true
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
    end

    it "respects hook priority (higher runs first)" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      order = [] of String

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 10, name: "low") do |ctx|
        order << "low"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, priority: 100, name: "high") do |ctx|
        order << "high"
        Hwaro::Core::Lifecycle::HookResult::Continue
      end

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      order.should eq(["high", "low"])
    end

    it "can clear hooks" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "test") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Continue
      end
      manager.hook_count.should eq(1)
      manager.clear
      manager.hook_count.should eq(0)
    end

    it "handles HookResult::Skip" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "skipper") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Skip
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Skip)
    end

    it "handles HookResult::Abort" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      manager.on(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, name: "aborter") do |ctx|
        Hwaro::Core::Lifecycle::HookResult::Abort
      end

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeInitialize, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Abort)
    end
  end

  describe Hwaro::Core::Lifecycle::BuildContext do
    it "initializes with build options" do
      options = Hwaro::Config::Options::BuildOptions.new(output_dir: "dist")
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.output_dir.should eq("dist")
      ctx.pages.should be_empty
      ctx.sections.should be_empty
      ctx.templates.should be_empty
    end

    it "provides all_pages helper" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      page = Hwaro::Models::Page.new("test.md")
      section = Hwaro::Models::Section.new("index.md")

      ctx.pages << page
      ctx.sections << section

      ctx.all_pages.size.should eq(2)
    end

    it "tracks build statistics" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.stats.pages_read.should eq(0)
      ctx.stats.pages_rendered.should eq(0)
      ctx.stats.cache_hits.should eq(0)
    end

    it "supports metadata storage" do
      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)

      ctx.set("key", "value")
      ctx.set("count", 42)
      ctx.set("enabled", true)

      ctx.get_string("key").should eq("value")
      ctx.get_int("count").should eq(42)
      ctx.get_bool("enabled").should eq(true)
      ctx.get_string("missing", "default").should eq("default")
    end
  end
end
