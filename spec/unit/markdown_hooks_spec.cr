require "../spec_helper"

describe Hwaro::Content::Hooks::MarkdownHooks do
  describe "hook registration" do
    it "registers parse and transform hooks" do
      hooks = Hwaro::Content::Hooks::MarkdownHooks.new
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks.register_hooks(manager)

      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent).should be_true
      manager.has_hooks?(Hwaro::Core::Lifecycle::HookPoint::BeforeRender).should be_true
    end
  end

  describe "markdown:parse hook" do
    it "parses front matter and calculates URLs" do
      Dir.mktmpdir do |tmpdir|
        content_dir = File.join(tmpdir, "content")
        FileUtils.mkdir_p(content_dir)

        file_path = File.join(content_dir, "test.md")
        File.write(file_path, "---\ntitle: Test Page\n---\n# Hello")

        Dir.cd(tmpdir) do
          manager = Hwaro::Core::Lifecycle::Manager.new
          hooks = Hwaro::Content::Hooks::MarkdownHooks.new
          hooks.register_hooks(manager)

          config = Hwaro::Config::Options::BuildOptions.new
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
          ctx.config = Hwaro::Models::Config.new

          page = Hwaro::Models::Page.new("test.md")
          ctx.pages << page

          manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent, ctx)

          page.title.should eq("Test Page")
          page.raw_content.should contain("# Hello")
          page.url.should eq("/test/")
        end
      end
    end

    it "filters drafts when drafts option is false" do
      Dir.mktmpdir do |tmpdir|
        content_dir = File.join(tmpdir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft\ndraft: true\n---\nContent")
        File.write(File.join(content_dir, "published.md"), "---\ntitle: Published\ndraft: false\n---\nContent")

        Dir.cd(tmpdir) do
          manager = Hwaro::Core::Lifecycle::Manager.new
          hooks = Hwaro::Content::Hooks::MarkdownHooks.new
          hooks.register_hooks(manager)

          config = Hwaro::Config::Options::BuildOptions.new(drafts: false)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
          ctx.config = Hwaro::Models::Config.new

          draft = Hwaro::Models::Page.new("draft.md")
          published = Hwaro::Models::Page.new("published.md")
          ctx.pages << draft
          ctx.pages << published

          manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent, ctx)

          ctx.pages.size.should eq(1)
          ctx.pages.first.title.should eq("Published")
        end
      end
    end

    it "keeps drafts when drafts option is true" do
      Dir.mktmpdir do |tmpdir|
        content_dir = File.join(tmpdir, "content")
        FileUtils.mkdir_p(content_dir)

        File.write(File.join(content_dir, "draft.md"), "---\ntitle: Draft\ndraft: true\n---\nContent")

        Dir.cd(tmpdir) do
          manager = Hwaro::Core::Lifecycle::Manager.new
          hooks = Hwaro::Content::Hooks::MarkdownHooks.new
          hooks.register_hooks(manager)

          config = Hwaro::Config::Options::BuildOptions.new(drafts: true)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
          ctx.config = Hwaro::Models::Config.new

          draft = Hwaro::Models::Page.new("draft.md")
          ctx.pages << draft

          manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent, ctx)

          ctx.pages.size.should eq(1)
        end
      end
    end

    it "parses sections" do
      Dir.mktmpdir do |tmpdir|
        content_dir = File.join(tmpdir, "content")
        FileUtils.mkdir_p(File.join(content_dir, "blog"))

        file_path = File.join(content_dir, "blog", "_index.md")
        File.write(file_path, "---\ntitle: Blog\ntransparent: true\n---\n# Blog Index")

        Dir.cd(tmpdir) do
          manager = Hwaro::Core::Lifecycle::Manager.new
          hooks = Hwaro::Content::Hooks::MarkdownHooks.new
          hooks.register_hooks(manager)

          config = Hwaro::Config::Options::BuildOptions.new
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
          ctx.config = Hwaro::Models::Config.new

          section = Hwaro::Models::Section.new("blog/_index.md")
          section.is_index = true
          ctx.sections << section

          manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent, ctx)

          section.title.should eq("Blog")
          section.transparent.should be_true
          section.url.should eq("/blog/")
        end
      end
    end

    it "parses redirect_to property" do
      Dir.mktmpdir do |tmpdir|
        content_dir = File.join(tmpdir, "content")
        FileUtils.mkdir_p(content_dir)

        file_path = File.join(content_dir, "redirect_test.md")
        File.write(file_path, "---\ntitle: Redirect Test\nredirect_to: /new-location/\n---\nRedirect me")

        Dir.cd(tmpdir) do
          manager = Hwaro::Core::Lifecycle::Manager.new
          hooks = Hwaro::Content::Hooks::MarkdownHooks.new
          hooks.register_hooks(manager)

          config = Hwaro::Config::Options::BuildOptions.new
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
          ctx.config = Hwaro::Models::Config.new

          page = Hwaro::Models::Page.new("redirect_test.md")
          ctx.pages << page

          manager.trigger(Hwaro::Core::Lifecycle::HookPoint::AfterReadContent, ctx)

          page.redirect_to.should eq("/new-location/")
          page.has_redirect?.should be_true
        end
      end
    end
  end

  describe "markdown:transform hook" do
    it "converts markdown to html" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::MarkdownHooks.new
      hooks.register_hooks(manager)

      config = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
      ctx.config = Hwaro::Models::Config.new

      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "# Hello World"
      page.render = true
      ctx.pages << page

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

      page.content.should contain("<h1 id=\"hello-world\">Hello World</h1>")
    end

    it "skips transform if render is false" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      hooks = Hwaro::Content::Hooks::MarkdownHooks.new
      hooks.register_hooks(manager)

      config = Hwaro::Config::Options::BuildOptions.new
      ctx = Hwaro::Core::Lifecycle::BuildContext.new(config)
      ctx.config = Hwaro::Models::Config.new

      page = Hwaro::Models::Page.new("test.md")
      page.raw_content = "# Hello World"
      page.render = false
      ctx.pages << page

      manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

      page.content.should be_empty
    end
  end
end
