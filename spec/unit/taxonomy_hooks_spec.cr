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
      # Priority 60 so it runs before seo:generate / pwa:generate (priority 50)
      # and the generated taxonomy pages are registered before the SEO
      # generators read ctx.all_pages.
      taxonomy_hook.not_nil!.priority.should eq(60)
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

        # Regression (#2): generated taxonomy pages must be registered into
        # ctx.sections so the SEO generators (sitemap/feeds/search/llms) can
        # see them. Without this, taxonomy.sitemap/feed had no effect.
        tax_sections = ctx.sections.select(&.generated)
        tax_urls = tax_sections.map(&.url)
        tax_urls.should contain("/tags/")
        tax_urls.should contain("/tags/crystal/")
        # in_sitemap reflects taxonomy.sitemap (defaults to true), so these
        # pages will be picked up by the sitemap generator.
        ctx.sections.find! { |s| s.url == "/tags/" }.in_sitemap.should be_true
        ctx.all_pages.map(&.url).should contain("/tags/crystal/")
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
