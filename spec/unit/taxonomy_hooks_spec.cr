require "../spec_helper"
require "../../src/content/hooks/taxonomy_hooks"
require "../../src/models/config"
require "../../src/models/site"
require "../../src/models/page"
require "../../src/config/options/build_options"

describe Hwaro::Content::Hooks::TaxonomyHooks do
  describe "#register_hooks" do
    it "registers the taxonomy:generate hook at BeforeGenerate phase" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hook = Hwaro::Content::Hooks::TaxonomyHooks.new
      hook.register_hooks(manager)

      hooks = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate)
      hooks.should_not be_empty

      taxonomy_hook = hooks.find { |h| h.name == "taxonomy:generate" }
      taxonomy_hook.should_not be_nil
      taxonomy_hook.not_nil!.priority.should eq(40)
    end
  end

  describe "execution" do
    it "generates taxonomies when hook is triggered" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hook = Hwaro::Content::Hooks::TaxonomyHooks.new
      hook.register_hooks(manager)

      # Setup context
      config = Hwaro::Models::Config.new
      taxonomy_config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.taxonomies = [taxonomy_config]

      site = Hwaro::Models::Site.new(config)
      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.tags = ["crystal"]
      page.draft = false
      page.generated = false
      site.pages = [page]

      Dir.mktmpdir do |output_dir|
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: output_dir)
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.site = site
        ctx.templates = {
          "taxonomy"      => "<html>{{ content }}</html>",
          "taxonomy_term" => "<html>{{ content }}</html>",
        }

        # Trigger hook manually
        result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)

        # Verify output
        File.exists?(File.join(output_dir, "tags", "index.html")).should be_true
        File.exists?(File.join(output_dir, "tags", "crystal", "index.html")).should be_true
      end
    end

    it "handles missing site context gracefully" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hook = Hwaro::Content::Hooks::TaxonomyHooks.new
      hook.register_hooks(manager)

      options = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
      # ctx.site is nil by default

      result = manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeGenerate, ctx)
      result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
    end
  end
end
