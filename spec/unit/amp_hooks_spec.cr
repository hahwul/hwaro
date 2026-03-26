require "../spec_helper"
require "../../src/content/hooks/amp_hooks"
require "../../src/models/config"
require "../../src/models/site"
require "../../src/models/page"
require "../../src/core/lifecycle"
require "../../src/config/options/build_options"

describe Hwaro::Content::Hooks::AmpHooks do
  describe "#register_hooks" do
    it "registers an AfterRender hook" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AmpHooks.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterRender).should be_true
    end

    it "registers hook named amp:generate" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AmpHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::AfterRender)
      registered.any? { |h| h.name == "amp:generate" }.should be_true
    end

    it "registers hook with priority 40" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AmpHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::AfterRender)
      hook = registered.find { |h| h.name == "amp:generate" }
      hook.should_not be_nil
      hook.not_nil!.priority.should eq(40)
    end

    it "does not register hooks at other hook points" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AmpHooks.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_false
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate).should be_false
    end
  end

  describe "hook execution" do
    it "skips when amp is disabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.amp.enabled = false

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::AmpHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end

    it "skips when site is nil" do
      Dir.mktmpdir do |output_dir|
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::AmpHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end

    it "executes without error when amp is enabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.amp.enabled = true
        config.base_url = "https://example.com"

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::AmpHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end
  end
end
