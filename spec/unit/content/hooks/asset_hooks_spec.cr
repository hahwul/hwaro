require "../../../spec_helper"
require "../../../../src/content/hooks/asset_hooks"
require "../../../../src/models/config"
require "../../../../src/models/site"
require "../../../../src/core/lifecycle"
require "../../../../src/config/options/build_options"

describe Hwaro::Content::Hooks::AssetHooks do
  describe "#register_hooks" do
    it "registers an AfterInitialize hook" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AssetHooks.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize).should be_true
    end

    it "registers hook named assets:process" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AssetHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize)
      registered.any? { |h| h.name == "assets:process" }.should be_true
    end

    it "registers hook with priority 40" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::AssetHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize)
      hook = registered.find { |h| h.name == "assets:process" }
      hook.should_not be_nil
      hook.not_nil!.priority.should eq(40)
    end
  end

  describe ".manifest" do
    it "returns an empty hash by default" do
      Hwaro::Content::Hooks::AssetHooks.manifest.should be_a(Hash(String, String))
    end
  end

  describe "hook execution" do
    it "skips when assets are disabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.assets.enabled = false

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.config = config

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::AssetHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end

    it "skips when config is nil" do
      Dir.mktmpdir do |output_dir|
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::AssetHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterInitialize, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end
  end
end
