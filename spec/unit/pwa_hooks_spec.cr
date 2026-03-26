require "../spec_helper"
require "../../src/content/hooks/pwa_hooks"
require "../../src/models/config"
require "../../src/models/site"
require "../../src/core/lifecycle"
require "../../src/config/options/build_options"

describe Hwaro::Content::Hooks::PwaHooks do
  describe "#register_hooks" do
    it "registers a BeforeGenerate hook" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::PwaHooks.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate).should be_true
    end

    it "registers hook named pwa:generate" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::PwaHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate)
      registered.any? { |h| h.name == "pwa:generate" }.should be_true
    end

    it "registers hook with priority 50" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::PwaHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate)
      hook = registered.find { |h| h.name == "pwa:generate" }
      hook.should_not be_nil
      hook.not_nil!.priority.should eq(50)
    end

    it "does not register hooks at other hook points" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::PwaHooks.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterRender).should be_false
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_false
    end
  end

  describe "hook execution" do
    it "skips when site is nil" do
      Dir.mktmpdir do |output_dir|
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::PwaHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end

    it "executes without error when site exists and pwa is enabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.pwa.enabled = true
        config.title = "Test Site"
        config.base_url = "https://example.com"

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::PwaHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)

        # PWA manifest should be generated
        File.exists?(File.join(output_dir, "manifest.json")).should be_true
      end
    end

    it "executes without error when site exists and pwa is disabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.pwa.enabled = false

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::PwaHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)

        # PWA manifest should NOT be generated when disabled
        File.exists?(File.join(output_dir, "manifest.json")).should be_false
      end
    end
  end
end
