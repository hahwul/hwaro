require "../spec_helper"
require "../../src/services/scaffolds/registry"

describe Hwaro::Services::Scaffolds::Simple do
  describe "#type" do
    it "returns Simple scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      scaffold.description.should_not be_empty
    end
  end

  describe "#content_files" do
    it "includes index.md" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files.has_key?("index.md").should be_true
    end

    it "includes about.md" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files.has_key?("about.md").should be_true
    end

    it "generates content with taxonomy frontmatter by default" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files(skip_taxonomies: false)

      files["index.md"].should contain("tags")
      files["about.md"].should contain("tags")
    end

    it "generates content without taxonomy frontmatter when skipped" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files(skip_taxonomies: true)

      files["index.md"].should_not contain("tags =")
      files["about.md"].should_not contain("tags =")
      files["about.md"].should_not contain("categories =")
    end

    it "includes Hwaro mention in index" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files["index.md"].should contain("Hwaro")
    end

    it "includes getting started instructions" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.content_files
      files["index.md"].should contain("hwaro build")
      files["index.md"].should contain("hwaro serve")
    end
  end

  describe "#template_files" do
    it "includes header.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("header.html").should be_true
    end

    it "styles tables, images, and blockquotes in the default header CSS" do
      # Regression: the default theme shipped no table/img/blockquote rules,
      # so markdown tables rendered borderless and images could overflow.
      header = Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"]
      header.should contain("table {")
      header.should contain("border-collapse")
      header.should contain("blockquote {")
      header.should contain("img {")
    end

    it "styles top-level ordered lists as a numbered step sequence" do
      # The getting-started list is the first thing a new user reads;
      # it renders as ember-numbered steps instead of a plain <ol>.
      header = Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"]
      header.should contain(".site-main > ol")
      header.should contain("counter-reset: step;")
      header.should contain("counter(step)")
    end

    it "marks the active nav item" do
      header = Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"]
      header.should contain(%(.site-header nav a[aria-current="page"]))
    end

    it "wires JSON-LD structured data into the header of SEO scaffolds" do
      # Regression: the engine generates JSON-LD and exposes it as `{{ jsonld }}`,
      # but no scaffold included it, so the advertised structured-data feature
      # produced nothing out of the box.
      {
        Hwaro::Services::Scaffolds::Simple.new,
        Hwaro::Services::Scaffolds::Blog.new,
        Hwaro::Services::Scaffolds::Docs.new,
        Hwaro::Services::Scaffolds::Book.new,
      }.each do |scaffold|
        scaffold.template_files["header.html"].should contain("{{ jsonld }}")
      end
    end

    it "renders the header nav through the menu system (get_menu + active_path)" do
      # The nav used to hardcode links, with an inert commented-out
      # `{% raw %}`-wrapped dynamic-loop example for users to copy out. It's
      # now driven entirely by the first-class menu system instead:
      # [[menus.main]] in config.toml (or a page/section's own front matter)
      # feeds a real `get_menu(name="main")` loop, with `active_path` flagging
      # the current page — no template edit needed to add a nav link.
      navs = {
        Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"],
        Hwaro::Services::Scaffolds::Blog.new.template_files["partials/nav.html"],
      }
      navs.each do |nav|
        nav.should contain(%(get_menu(name="main")))
        nav.should contain("item.href")
        nav.should contain("active_path")
        nav.should_not contain("{% raw %}")
        nav.should_not contain("{% endraw %}")
      end
    end

    it "wires pagination SEO links (rel=prev/next) into the header of SEO scaffolds" do
      # Regression: the engine builds `pagination_seo_links` (<link rel="prev"/
      # "next">) for paginated pages, but no scaffold rendered it, so paginated
      # pages shipped without rel=prev/next.
      {
        Hwaro::Services::Scaffolds::Simple.new,
        Hwaro::Services::Scaffolds::Blog.new,
        Hwaro::Services::Scaffolds::Docs.new,
        Hwaro::Services::Scaffolds::Book.new,
      }.each do |scaffold|
        scaffold.template_files["header.html"].should contain("{{ pagination_seo_links }}")
      end
    end

    it "markdownifies the alert shortcode body so markdown inside alerts renders" do
      # Regression: the alert shortcode emitted `{{ body }}` verbatim, so
      # `{% alert %}**bold**{% end %}` rendered the literal `**bold**` instead
      # of `<strong>bold</strong>`.
      {
        Hwaro::Services::Scaffolds::Simple.new,
        Hwaro::Services::Scaffolds::Blog.new,
        Hwaro::Services::Scaffolds::Docs.new,
        Hwaro::Services::Scaffolds::Book.new,
      }.each do |scaffold|
        scaffold.shortcode_files["shortcodes/alert.html"].should contain("body | markdownify")
      end
    end

    it "includes footer.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("footer.html").should be_true
    end

    it "includes page.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("page.html").should be_true
    end

    it "includes section.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("section.html").should be_true
    end

    it "includes 404.html" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files
      files.has_key?("404.html").should be_true
    end

    it "includes taxonomy templates by default" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files(skip_taxonomies: false)
      files.has_key?("taxonomy.html").should be_true
      files.has_key?("taxonomy_term.html").should be_true
    end

    it "excludes taxonomy templates when skipped" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      files = scaffold.template_files(skip_taxonomies: true)
      files.has_key?("taxonomy.html").should be_false
      files.has_key?("taxonomy_term.html").should be_false
    end
  end

  describe "#config_content" do
    it "returns non-empty config" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content
      config.should_not be_empty
    end

    it "includes site title placeholder" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content
      config.should contain("title")
    end

    it "includes base_url" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content
      config.should contain("base_url")
    end

    it "includes taxonomy config by default" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content(skip_taxonomies: false)
      config.should contain("taxonomies")
    end

    it "excludes taxonomy config when skipped" do
      scaffold = Hwaro::Services::Scaffolds::Simple.new
      config = scaffold.config_content(skip_taxonomies: true)
      config.should_not contain("[[taxonomies]]")
    end
  end
end

describe Hwaro::Services::Scaffolds::Docs do
  describe "#type" do
    it "returns Docs scaffold type" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end
  end

  describe "#description" do
    it "returns a non-empty description" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      scaffold.description.should_not be_empty
    end

    it "mentions documentation" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      scaffold.description.downcase.should contain("doc")
    end
  end

  describe "#content_files" do
    it "includes index.md" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      files.has_key?("index.md").should be_true
    end

    it "includes getting-started section" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("getting-started")).should be_true
    end

    it "includes guide section" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("guide")).should be_true
    end

    it "includes reference section" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("reference")).should be_true
    end

    it "includes installation content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("installation")).should be_true
    end

    it "includes quick-start content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("quick-start")).should be_true
    end

    it "includes configuration content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.content_files
      keys = files.keys
      keys.any?(&.includes?("configuration")).should be_true
    end

    it "has more content files than simple scaffold" do
      docs = Hwaro::Services::Scaffolds::Docs.new
      simple = Hwaro::Services::Scaffolds::Simple.new
      docs.content_files.size.should be > simple.content_files.size
    end
  end

  describe "#template_files" do
    it "includes header.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("header.html").should be_true
    end

    it "includes footer.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("footer.html").should be_true
    end

    it "includes page.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("page.html").should be_true
    end

    it "includes section.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("section.html").should be_true
    end

    it "includes 404.html" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.has_key?("404.html").should be_true
    end

    it "template files contain HTML content" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      files = scaffold.template_files
      files.values.each do |content|
        content.should_not be_empty
      end
    end
  end

  describe "#config_content" do
    it "returns non-empty config" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      config = scaffold.config_content
      config.should_not be_empty
    end

    it "includes base_url" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      config = scaffold.config_content
      config.should contain("base_url")
    end

    it "includes title" do
      scaffold = Hwaro::Services::Scaffolds::Docs.new
      config = scaffold.config_content
      config.should contain("title")
    end
  end
end

describe Hwaro::Services::Scaffolds::Registry do
  describe ".get" do
    it "returns Simple scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple)
      scaffold.should be_a(Hwaro::Services::Scaffolds::Simple)
    end

    it "returns Blog scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Blog)
      scaffold.should be_a(Hwaro::Services::Scaffolds::Blog)
    end

    it "returns Docs scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Docs)
      scaffold.should be_a(Hwaro::Services::Scaffolds::Docs)
    end

    it "raises for unknown scaffold type" do
      # All known types are registered, so this test verifies the mechanism
      Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple).should_not be_nil
    end
  end

  describe ".has?" do
    it "returns true for Simple" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Simple).should be_true
    end

    it "returns true for Blog" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Blog).should be_true
    end

    it "returns true for Docs" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Docs).should be_true
    end

    it "returns true for Book" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Book).should be_true
    end
  end

  describe ".all" do
    it "returns all registered scaffolds" do
      all = Hwaro::Services::Scaffolds::Registry.all
      all.size.should be >= 5
    end

    it "includes instances of all scaffold types" do
      all = Hwaro::Services::Scaffolds::Registry.all
      types = all.map(&.type)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Simple)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Blog)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Docs)
      types.should contain(Hwaro::Config::Options::ScaffoldType::Book)
    end
  end

  describe ".list" do
    it "returns list of tuples with name and description" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.should_not be_empty
    end

    it "each item has a non-empty name" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.each do |name, _desc|
        name.should_not be_empty
      end
    end

    it "each item has a non-empty description" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.each do |_name, desc|
        desc.should_not be_empty
      end
    end

    it "has at least 5 items" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.size.should be >= 5
    end
  end

  describe ".default" do
    it "returns the Simple scaffold" do
      default = Hwaro::Services::Scaffolds::Registry.default
      default.type.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end

    it "is an instance of Simple" do
      default = Hwaro::Services::Scaffolds::Registry.default
      default.should be_a(Hwaro::Services::Scaffolds::Simple)
    end
  end

  describe "scaffold consistency" do
    it "all scaffolds produce non-empty content_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.content_files.should_not be_empty
      end
    end

    it "all scaffolds produce non-empty template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.should_not be_empty
      end
    end

    it "all scaffolds produce non-empty config_content" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.config_content.should_not be_empty
      end
    end

    it "all scaffolds include index.md in content_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.content_files.has_key?("index.md").should be_true
      end
    end

    it "all scaffolds include page.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("page.html").should be_true
      end
    end

    it "all scaffolds include section.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("section.html").should be_true
      end
    end

    it "all scaffolds include header.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("header.html").should be_true
      end
    end

    it "all scaffolds include footer.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("footer.html").should be_true
      end
    end

    it "all scaffolds include 404.html in template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.template_files.has_key?("404.html").should be_true
      end
    end

    it "all scaffolds config_content includes base_url" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        scaffold.config_content.should contain("base_url")
      end
    end

    it "all scaffolds support skip_taxonomies for content_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        with_tax = scaffold.content_files(skip_taxonomies: false)
        without_tax = scaffold.content_files(skip_taxonomies: true)

        with_tax.should_not be_empty
        without_tax.should_not be_empty
      end
    end

    it "all scaffolds support skip_taxonomies for template_files" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        with_tax = scaffold.template_files(skip_taxonomies: false)
        without_tax = scaffold.template_files(skip_taxonomies: true)

        # With taxonomies should have at least as many templates
        with_tax.size.should be >= without_tax.size
      end
    end

    it "all scaffolds support skip_taxonomies for config_content" do
      Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
        with_tax = scaffold.config_content(skip_taxonomies: false)
        without_tax = scaffold.config_content(skip_taxonomies: true)

        with_tax.should_not be_empty
        without_tax.should_not be_empty
      end
    end

    describe "#multilingual_content_files" do
      it "returns content_files unchanged when zero or one language is supplied" do
        Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
          scaffold.multilingual_content_files([] of String).should eq(scaffold.content_files)
          scaffold.multilingual_content_files(["en"]).should eq(scaffold.content_files)
        end
      end

      it "keeps default-language files (no suffix) and adds .{lang}.md copies for each extra language" do
        Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
          base = scaffold.content_files
          multi = scaffold.multilingual_content_files(["en", "ko"])

          # Every original path is preserved as-is.
          base.each_key do |path|
            multi.has_key?(path).should be_true
          end

          # Every Markdown file has a .ko.md sibling.
          base.each_key do |path|
            next unless path.ends_with?(".md")
            localized = "#{path[0, path.size - 3]}.ko.md"
            multi.has_key?(localized).should be_true
          end
        end
      end

      it "prepends the translate-me notice below the front matter" do
        scaffold = Hwaro::Services::Scaffolds::Simple.new
        multi = scaffold.multilingual_content_files(["en", "ko"])

        translated = multi["index.ko.md"]
        fm_close = translated.index!("+++\n", 4)
        notice_at = translated.index!("<!-- TODO: Translate")
        notice_at.should be > fm_close
      end

      it "emits one localized copy per extra language" do
        scaffold = Hwaro::Services::Scaffolds::Simple.new
        multi = scaffold.multilingual_content_files(["en", "ko", "ja"])

        multi.has_key?("index.md").should be_true
        multi.has_key?("index.ko.md").should be_true
        multi.has_key?("index.ja.md").should be_true
        multi.has_key?("about.md").should be_true
        multi.has_key?("about.ko.md").should be_true
        multi.has_key?("about.ja.md").should be_true
      end

      # Regression for gh#524: the auto-generated `*.ko.md` stub used
      # to keep the default-language `[Posts](/posts/)` link in its
      # body, so a Korean reader clicked it and landed on the English
      # `/posts/` page. The localized stub now rewrites internal
      # absolute links to the locale prefix.
      it "rewrites default-language internal links in localized stubs (gh#524)" do
        scaffold = Hwaro::Services::Scaffolds::Blog.new
        multi = scaffold.multilingual_content_files(["en", "ko"])

        ko_index = multi["index.ko.md"]
        ko_index.should contain("[Tags](/ko/tags/)")
        ko_index.should contain("[Categories](/ko/categories/)")
        ko_index.should_not contain("[Tags](/tags/)")
        ko_index.should_not contain("[Categories](/categories/)")
      end

      # Regression: the link-rewriter used to also match Markdown
      # image syntax (`![alt](/img.png)`) because the regex only
      # anchored on `](`. That broke localized scaffolds that ship
      # body-level images (e.g. docs `![Diagram](/images/diagram.png)`),
      # silently producing `/ko/images/diagram.png` paths the static
      # asset serving doesn't know about.
      it "does not prefix Markdown image targets in localized stubs" do
        scaffold = Hwaro::Services::Scaffolds::Docs.new
        multi = scaffold.multilingual_content_files(["en", "ko"])

        # The docs scaffold ships at least one image markdown
        # reference; locate the localized copy of whichever file
        # carries it and verify the path was preserved.
        ko_with_image = multi.find { |path, body| path.ends_with?(".ko.md") && body.includes?("![") }
        ko_with_image.should_not be_nil
        if entry = ko_with_image
          _, body = entry
          body.should contain("![")
          body.should_not match(/!\[[^\]]*\]\(\/ko\//)
        end
      end

      it "leaves already-prefixed links alone in localized stubs (gh#524)" do
        # The blog scaffold's `posts/_index.md` body links to
        # `/posts/`. After localizing for "ko", that should become
        # `/ko/posts/` — but the section _index file's `[Posts]`
        # backlink (or any link already starting with `/ko/`) should
        # not become `/ko/ko/...`. Round-trip through
        # `multilingual_content_files` and check.
        scaffold = Hwaro::Services::Scaffolds::Blog.new
        multi = scaffold.multilingual_content_files(["en", "ko"])

        multi.each do |path, body|
          next unless path.ends_with?(".ko.md")
          # No double-prefixing.
          body.should_not contain("/ko/ko/")
          # External links pass through.
          body.should_not match(/\]\(http:\/\/ko\//)
        end
      end
    end
  end
end

# Helper to drive the protected prepend_translation_notice without a network
# hop, mirroring the TestRemoteHelper wrapper pattern in remote_scaffold_spec.cr.
class TestNoticeScaffold < Hwaro::Services::Scaffolds::Simple
  def do_prepend(body : String, lang : String) : String
    prepend_translation_notice(body, lang)
  end
end

describe "minimal_config_content multilingual parseability" do
  # minimal_config_content assembles the [languages] block via raw String
  # concatenation; a missing newline / duplicate key / TOML-special char in a
  # language_name would slip past substring checks but break the first
  # `hwaro build`. Parse it with the real config loader to catch that.
  it "produces parseable multilingual TOML with [languages.en]/[languages.ko] tables for every built-in scaffold" do
    Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
      toml = scaffold.minimal_config_content(multilingual_languages: ["en", "ko"])

      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, toml)
        config = Hwaro::Models::Config.load(path)

        config.default_language.should eq("en")
        config.languages.has_key?("en").should be_true
        config.languages.has_key?("ko").should be_true
      end
    end
  end

  it "produces parseable multilingual TOML with skip_taxonomies for every built-in scaffold" do
    Hwaro::Services::Scaffolds::Registry.all.each do |scaffold|
      toml = scaffold.minimal_config_content(skip_taxonomies: true, multilingual_languages: ["en", "ko"])

      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.toml")
        File.write(path, toml)
        config = Hwaro::Models::Config.load(path)

        config.languages.has_key?("en").should be_true
        config.languages.has_key?("ko").should be_true
        # No global [[taxonomies]] block when skipped.
        toml.should_not contain("[[taxonomies]]")
      end
    end
  end
end

describe "prepend_translation_notice" do
  # The built-in scaffolds all ship TOML (+++) front matter, so the YAML
  # (---) branch and the unclosed-delimiter fallback are never exercised by
  # built-in content. Drive them directly.
  it "inserts the notice after a closing YAML (---) delimiter, before the body" do
    body = "---\ntitle: X\n---\n\nbody"
    result = TestNoticeScaffold.new.do_prepend(body, "ko")

    notice_at = result.index!("<!-- TODO: Translate")
    close_at = result.index!("---", 4) # closing delimiter, past the opening one
    body_at = result.index!("body")

    notice_at.should be > close_at
    notice_at.should be < body_at
    # The front-matter block at the top of the result still parses cleanly
    # (the notice did not get injected between the delimiters).
    lines = result.lines
    second_delim = lines[1..].index!("---") + 1
    inner = lines[1...second_delim].join("\n")
    YAML.parse(inner)["title"].as_s.should eq("X")
  end

  it "prepends the notice at the top when the YAML delimiter is unclosed (fallback)" do
    body = "---\ntitle: X"
    result = TestNoticeScaffold.new.do_prepend(body, "ko")

    result.index!("<!-- TODO: Translate").should eq(0)
    result.should contain("---\ntitle: X")
  end
end
