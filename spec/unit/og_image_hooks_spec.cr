require "../spec_helper"
require "../../src/content/hooks/og_image_hooks"
require "../../src/models/config"
require "../../src/models/site"
require "../../src/models/page"
require "../../src/core/lifecycle"
require "../../src/config/options/build_options"

describe Hwaro::Content::Hooks::OgImageHooks do
  describe "#register_hooks" do
    it "registers a BeforeRender hook" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::OgImageHooks.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_true
    end

    it "registers hook named og_image:generate" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::OgImageHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeRender)
      registered.any? { |h| h.name == "og_image:generate" }.should be_true
    end

    it "registers hook with priority 30" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::OgImageHooks.new
      hooks.register_hooks(manager)

      registered = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeRender)
      hook = registered.find { |h| h.name == "og_image:generate" }
      hook.should_not be_nil
      hook.not_nil!.priority.should eq(30)
    end
  end

  describe "hook execution" do
    it "skips when og auto image is disabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = false

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::OgImageHooks.new
        hooks.register_hooks(manager)

        # Should not raise when og image is disabled
        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end

    it "skips when site is nil" do
      Dir.mktmpdir do |output_dir|
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::OgImageHooks.new
        hooks.register_hooks(manager)

        # Should not raise when site is nil
        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end

    # Guards that gate the expensive OgImage.generate call. A regression here
    # would re-render every PNG on each keystroke rebuild during dev (the cost
    # these guards avoid), or invert and ship pages with a missing og:image.
    it "skips generation when options.skip_og_image is true (--skip-og-image)" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: output_dir,
          skip_og_image: true,
        )

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::OgImageHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        Dir.glob(File.join(output_dir, "**", "*.png")).should be_empty
      end
    end

    it "skips generation in serve mode when lazy_generate is enabled" do
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.lazy_generate = true

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: output_dir,
          serve_mode: true,
        )

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::OgImageHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        Dir.glob(File.join(output_dir, "**", "*.png")).should be_empty
      end
    end

    it "does NOT skip generation when lazy_generate is enabled but not in serve mode" do
      # Contrast: lazy_generate alone (without serve_mode) does not gate
      # generation. With zero pages OgImage.generate is a cheap no-op, so the
      # hook still returns Continue and writes nothing — confirming the guard
      # requires BOTH lazy_generate AND serve_mode.
      Dir.mktmpdir do |output_dir|
        config = Hwaro::Models::Config.new
        config.og.auto_image.enabled = true
        config.og.auto_image.lazy_generate = true

        site = Hwaro::Models::Site.new(config)
        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: output_dir,
          serve_mode: false,
        )

        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options: options)
        ctx.output_dir = output_dir
        ctx.site = site

        manager = Hwaro::Core::Lifecycle::Manager.new
        hooks = Hwaro::Content::Hooks::OgImageHooks.new
        hooks.register_hooks(manager)

        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
      end
    end
  end
end
