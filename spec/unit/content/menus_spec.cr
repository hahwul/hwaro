require "../../spec_helper"

private def menu_item(name : String, url : String = "", identifier : String? = nil, parent : String? = nil, weight : Int32 = 0) : Hwaro::Models::MenuItemConfig
  item = Hwaro::Models::MenuItemConfig.new(name)
  item.url = url
  item.parent = parent
  item.weight = weight
  item.identifier = identifier || name
  item
end

private def page_with_menu(path : String, title : String, url : String, menu_name : String, reg : Hwaro::Models::MenuRegistration, language : String? = nil) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.title = title
  page.url = url
  page.language = language
  page.menus = {menu_name => reg}
  page
end

private def auto_section(dir : String, title : String, weight : Int32 = 0, language : String? = nil) : Hwaro::Models::Section
  suffix = language ? ".#{language}" : ""
  section = Hwaro::Models::Section.new("#{dir}/_index#{suffix}.md")
  section.section = dir
  section.title = title
  section.url = language ? "/#{language}/#{dir}/" : "/#{dir}/"
  section.weight = weight
  section.language = language
  section
end

describe Hwaro::Content::Menus do
  describe ".build" do
    it "builds a flat menu from config entries, sorted by weight then name" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Posts", "/posts/", weight: 2),
          menu_item("About", "/about/", weight: 1),
        ],
      }

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      main = trees["en"]["main"]
      main.map(&.name).should eq(["About", "Posts"])
      main.map(&.weight).should eq([1, 2])
    end

    it "leaves mailto:/tel: and other scheme URLs untouched (not internal paths)" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Email", "mailto:hello@example.com"),
          menu_item("Call", "tel:+15551212"),
          menu_item("GitHub", "https://github.com/hahwul"),
        ],
      }

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      main = trees["en"]["main"]
      by_name = main.index_by(&.name)
      by_name["Email"].url.should eq("mailto:hello@example.com")
      by_name["Email"].external.should be_true
      by_name["Call"].url.should eq("tel:+15551212")
      by_name["Call"].external.should be_true
      by_name["GitHub"].url.should eq("https://github.com/hahwul")
      by_name["GitHub"].external.should be_true
    end

    it "assembles parent/child hierarchy from `parent` identifiers" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Posts", "/posts/", identifier: "posts"),
          menu_item("First Post", "/posts/first/", parent: "posts"),
          menu_item("Second Post", "/posts/second/", parent: "posts"),
        ],
      }

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      main = trees["en"]["main"]
      main.size.should eq(1)
      main[0].identifier.should eq("posts")
      main[0].children.map(&.name).should eq(["First Post", "Second Post"])
    end

    it "promotes an entry with a dangling parent to root and warns" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Orphan", "/orphan/", parent: "nonexistent"),
        ],
      }

      captured = IO::Memory.new
      original_io = Hwaro::Logger.io
      Hwaro::Logger.io = captured
      trees = begin
        Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      ensure
        Hwaro::Logger.io = original_io
      end

      main = trees["en"]["main"]
      main.size.should eq(1)
      main[0].name.should eq("Orphan")
      captured.to_s.should contain("unknown parent")
    end

    it "promotes entries in a mutual parent cycle to root and warns (no crash)" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("A", "/a/", identifier: "a", parent: "b"),
          menu_item("B", "/b/", identifier: "b", parent: "a"),
        ],
      }

      captured = IO::Memory.new
      original_io = Hwaro::Logger.io
      Hwaro::Logger.io = captured
      trees = begin
        Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      ensure
        Hwaro::Logger.io = original_io
      end

      main = trees["en"]["main"]
      main.map(&.name).sort!.should eq(["A", "B"])
      captured.to_s.should contain("cyclic parent chain")
    end

    it "keeps the last entry when identifiers collide, and warns" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("First", "/first/", identifier: "dup"),
          menu_item("Second", "/second/", identifier: "dup"),
        ],
      }

      captured = IO::Memory.new
      original_io = Hwaro::Logger.io
      Hwaro::Logger.io = captured
      trees = begin
        Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      ensure
        Hwaro::Logger.io = original_io
      end

      main = trees["en"]["main"]
      main.size.should eq(1)
      main[0].name.should eq("Second")
      captured.to_s.should contain("duplicate identifier")
    end

    it "includes front-matter menu registrations, falling back to page title/weight/identifier defaults" do
      config = Hwaro::Models::Config.new
      page = page_with_menu("post.md", "My Post", "/blog/post/", "main", Hwaro::Models::MenuRegistration.new)

      trees = Hwaro::Content::Menus.build(config, [page], [] of Hwaro::Models::Section)
      main = trees["en"]["main"]
      main.size.should eq(1)
      main[0].name.should eq("My Post")
      main[0].weight.should eq(0)
      main[0].identifier.should eq("My Post")
      main[0].parent.should be_nil
      main[0].page_path.should eq("post.md")
    end

    it "honors explicit name/weight/parent/identifier overrides in front-matter table form" do
      config = Hwaro::Models::Config.new
      reg = Hwaro::Models::MenuRegistration.new(name: "Custom", weight: 9, parent: "posts", identifier: "custom-id")
      page = page_with_menu("post.md", "My Post", "/blog/post/", "main", reg)

      trees = Hwaro::Content::Menus.build(config, [page], [] of Hwaro::Models::Section)
      entry = trees["en"]["main"][0]
      entry.name.should eq("Custom")
      entry.weight.should eq(9)
      entry.parent.should eq("posts")
      entry.identifier.should eq("custom-id")
    end

    it "combines config entries and front-matter registrations in the same menu, sorted together" do
      config = Hwaro::Models::Config.new
      config.menus = {"main" => [menu_item("Home", "/", weight: 0)]}
      page = page_with_menu("post.md", "Zeta Post", "/blog/post/", "main", Hwaro::Models::MenuRegistration.new(weight: 1))

      trees = Hwaro::Content::Menus.build(config, [page], [] of Hwaro::Models::Section)
      main = trees["en"]["main"]
      main.map(&.name).should eq(["Home", "Zeta Post"])
    end

    it "uses the per-language menu override when present, ignoring the global set" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.menus = {"main" => [menu_item("Posts", "/posts/")]}
      ko = Hwaro::Models::LanguageConfig.new("ko")
      ko.menus = {"main" => [menu_item("글", "/ko/posts/")]}
      config.languages = {"ko" => ko}

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      trees["en"]["main"].map(&.name).should eq(["Posts"])
      trees["ko"]["main"].map(&.name).should eq(["글"])
    end

    it "inherits the global menu set wholesale when a language declares no menus override" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.menus = {"main" => [menu_item("Posts", "/posts/")]}
      fr = Hwaro::Models::LanguageConfig.new("fr")
      config.languages = {"fr" => fr}

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      trees["fr"]["main"].map(&.name).should eq(["Posts"])
    end

    it "filters front-matter registrations to the page's own language" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      ko = Hwaro::Models::LanguageConfig.new("ko")
      config.languages = {"ko" => ko}

      en_page = page_with_menu("en-post.md", "EN Post", "/blog/en-post/", "main", Hwaro::Models::MenuRegistration.new, language: nil)
      ko_page = page_with_menu("ko/ko-post.md", "KO Post", "/ko/blog/ko-post/", "main", Hwaro::Models::MenuRegistration.new, language: "ko")

      trees = Hwaro::Content::Menus.build(config, [en_page, ko_page], [] of Hwaro::Models::Section)
      trees["en"]["main"].map(&.name).should eq(["EN Post"])
      trees["ko"]["main"].map(&.name).should eq(["KO Post"])
    end

    it "produces identical serialized structure across repeated builds (determinism)" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Posts", "/posts/", identifier: "posts", weight: 1),
          menu_item("First Post", "/posts/first/", parent: "posts"),
          menu_item("About", "/about/", weight: 2),
        ],
      }
      page = page_with_menu("post.md", "New Post", "/blog/post/", "main", Hwaro::Models::MenuRegistration.new)

      serialize_entry = uninitialized Proc(Hwaro::Content::Menus::Entry, String)
      serialize_entry = ->(e : Hwaro::Content::Menus::Entry) {
        children = e.children.map { |c| serialize_entry.call(c) }.join(",")
        "#{e.name}|#{e.url}|#{e.identifier}|#{e.weight}|#{e.parent}|#{e.external}|#{e.page_path}|[#{children}]"
      }
      serialize = ->(trees : Hash(String, Hash(String, Array(Hwaro::Content::Menus::Entry)))) {
        trees.keys.sort!.map do |lang|
          menus = trees[lang]
          menu_str = menus.keys.sort!.map { |name| "#{name}:#{menus[name].map { |e| serialize_entry.call(e) }.join(";")}" }.join("|")
          "#{lang}=>#{menu_str}"
        end.join(",")
      }

      first = Hwaro::Content::Menus.build(config, [page], [] of Hwaro::Models::Section)
      second = Hwaro::Content::Menus.build(config, [page], [] of Hwaro::Models::Section)
      serialize.call(first).should eq(serialize.call(second))
    end

    it "normalizes internal urls: leading slash and trailing slash added" do
      config = Hwaro::Models::Config.new
      config.menus = {"main" => [menu_item("Posts", "posts")]}

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      trees["en"]["main"][0].url.should eq("/posts/")
    end

    it "does not add a trailing slash to a url whose last segment has an extension" do
      config = Hwaro::Models::Config.new
      config.menus = {"main" => [menu_item("Feed", "/feed.xml")]}

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      trees["en"]["main"][0].url.should eq("/feed.xml")
    end

    it "does not append a trailing slash to query-string or fragment urls" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Search", "/search?q=foo"),
          menu_item("Contact", "/#contact"),
        ],
      }

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      trees["en"]["main"].map(&.url).should eq(["/#contact", "/search?q=foo"])
    end

    it "flags http(s) and protocol-relative urls as external and leaves them untouched" do
      config = Hwaro::Models::Config.new
      config.menus = {
        "main" => [
          menu_item("Ext HTTP", "http://example.com/x"),
          menu_item("Ext HTTPS", "https://example.com/y"),
          menu_item("Ext Protocol", "//cdn.example.com/z"),
        ],
      }

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      main = trees["en"]["main"]
      main.each(&.external.should(be_true))
      main.map(&.url).should eq([
        "http://example.com/x",
        "https://example.com/y",
        "//cdn.example.com/z",
      ])
    end

    it "does not flag a root-relative url as external" do
      config = Hwaro::Models::Config.new
      config.menus = {"main" => [menu_item("Home", "/")]}

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [] of Hwaro::Models::Section)
      trees["en"]["main"][0].external.should be_false
    end
  end

  describe ".build with [menus] auto_sections" do
    it "adds every top-level section, keyed by directory, sorted by weight then name" do
      config = Hwaro::Models::Config.new
      config.menus_auto_sections = "main"
      root = auto_section("", "Home")
      root.section = ""
      sections = [
        auto_section("posts", "Posts", weight: 2),
        auto_section("about", "About", weight: 1),
        auto_section("docs", "Docs", weight: 2),
        auto_section("posts/2024", "2024"),
        root,
      ]

      main = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, sections)["en"]["main"]
      main.map(&.name).should eq(["About", "Docs", "Posts"])
      main.map(&.identifier).should eq(["about", "docs", "posts"])
      main.map(&.url).should eq(["/about/", "/docs/", "/posts/"])
      main.map(&.weight).should eq([1, 2, 2])
      main.map(&.page_path).should eq(["about/_index.md", "docs/_index.md", "posts/_index.md"])
    end

    it "is off by default" do
      config = Hwaro::Models::Config.new
      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [auto_section("posts", "Posts")])
      trees["en"].should be_empty
    end

    it "skips draft, unpublished, headless, transparent and off-site redirect sections" do
      config = Hwaro::Models::Config.new
      config.menus_auto_sections = "main"
      draft = auto_section("draft", "Draft")
      draft.draft = true
      unpublished = auto_section("later", "Later")
      unpublished.unpublished = true
      headless = auto_section("data", "Data")
      headless.render = false
      transparent = auto_section("flat", "Flat")
      transparent.transparent = true
      offsite = auto_section("gone", "Gone")
      offsite.redirect_to = "https://elsewhere.example/"
      onsite = auto_section("moved", "Moved")
      onsite.redirect_to = "/posts/"
      sections = [draft, unpublished, headless, transparent, offsite, onsite, auto_section("posts", "Posts")]

      main = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, sections)["en"]["main"]
      main.map(&.identifier).should eq(["moved", "posts"])
    end

    it "lets a config or front-matter entry with the same identifier override the auto entry" do
      config = Hwaro::Models::Config.new
      config.menus_auto_sections = "main"
      config.menus = {"main" => [
        menu_item("Blog", "/posts/", identifier: "posts", weight: 9),
        menu_item("GitHub", "https://github.com/hahwul", weight: 5),
      ]}
      fm_reg = Hwaro::Models::MenuRegistration.new(name: "Who", identifier: "about")
      about_page = page_with_menu("who.md", "Who", "/who/", "main", fm_reg)

      sections = [auto_section("posts", "Posts"), auto_section("about", "About"), auto_section("docs", "Docs", weight: 1)]
      main = Hwaro::Content::Menus.build(config, [about_page], sections)["en"]["main"]
      main.map { |e| {e.identifier, e.name, e.url} }.should eq([
        {"about", "Who", "/who/"},
        {"docs", "Docs", "/docs/"},
        {"GitHub", "GitHub", "https://github.com/hahwul"},
        {"posts", "Blog", "/posts/"},
      ])
    end

    it "does not duplicate a section that registers itself into the same menu" do
      config = Hwaro::Models::Config.new
      config.menus_auto_sections = "main"
      posts = auto_section("posts", "Posts")
      posts.menus = {"main" => Hwaro::Models::MenuRegistration.new}

      main = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [posts])["en"]["main"]
      main.map(&.identifier).should eq(["Posts"])
    end

    it "maps versioned sections through their version root (docs/v1, docs/v2 latest at root)" do
      config = Hwaro::Models::Config.new
      config.menus_auto_sections = "main"
      v1 = Hwaro::Models::VersionConfig.new("v1", path: "docs/v1")
      v2 = Hwaro::Models::VersionConfig.new("v2", path: "docs/v2", latest: true)
      config.versions.list = [v1, v2]
      d1 = auto_section("docs/v1", "Docs v1")
      d1.url = "/docs/v1/"
      d1.version = v1
      d2 = auto_section("docs/v2", "Docs")
      d2.url = "/docs/"
      d2.version = v2
      sections = [auto_section("blog", "Blog"), d1, d2]

      latest = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, sections)["en"]["main"]
      latest.map { |e| {e.identifier, e.url} }.should eq([{"blog", "/blog/"}, {"docs", "/docs/"}])
      old = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, sections, v1)["en"]["main"]
      old.map { |e| {e.identifier, e.url} }.should eq([{"blog", "/blog/"}, {"docs", "/docs/v1/"}])
    end

    it "uses a top-level version directory's own sections, not the version root" do
      config = Hwaro::Models::Config.new
      config.menus_auto_sections = "main"
      v2 = Hwaro::Models::VersionConfig.new("v2", latest: true)
      config.versions.list = [v2]
      root = auto_section("v2", "Ver v2")
      root.url = "/"
      guide = auto_section("v2/guide", "Guide")
      guide.url = "/guide/"
      api = auto_section("v2/api", "API")
      api.url = "/api/"
      [root, guide, api].each(&.version=(v2))

      main = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [root, guide, api])["en"]["main"]
      main.map { |e| {e.identifier, e.url} }.should eq([{"api", "/api/"}, {"guide", "/guide/"}])
    end

    [{"v1", "v2"}, {"1.0", "2.0"}].each do |(old_name, new_name)|
      it "gives a shared directory to the menu set's own version (#{old_name}/#{new_name})" do
        config = Hwaro::Models::Config.new
        config.menus_auto_sections = "main"
        config.versions.latest_at_root = false
        old_v = Hwaro::Models::VersionConfig.new(old_name, path: "docs/#{old_name}")
        new_v = Hwaro::Models::VersionConfig.new(new_name, path: "docs/#{new_name}", latest: true)
        config.versions.list = [old_v, new_v]
        sections = [auto_section("docs", "Docs")]
        {old_v, new_v}.each do |v|
          root = auto_section("docs/#{v.name}", "Docs #{v.name}")
          root.version = v
          sections << root
        end

        url = ->(version : Hwaro::Models::VersionConfig?) do
          Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, sections, version)["en"]["main"].map(&.url)
        end
        url.call(nil).should eq(["/docs/"]), "#{old_name}/#{new_name}: unversioned menus"
        url.call(old_v).should eq(["/docs/#{old_name}/"]), "#{old_name}/#{new_name}: #{old_name} menus"
        url.call(new_v).should eq(["/docs/#{new_name}/"]), "#{old_name}/#{new_name}: #{new_name} menus"
      end
    end

    it "leaves the menu out of a language with no auto entry, so get_menu falls back" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.menus_auto_sections = "main"
      config.languages = {"ko" => Hwaro::Models::LanguageConfig.new("ko")}

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, [auto_section("blog", "Blog")])
      trees["en"]["main"].map(&.identifier).should eq(["blog"])
      trees["ko"].has_key?("main").should be_false
    end

    it "builds per-language entries from each language's sections, under that language's overrides" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.menus_auto_sections = "main"
      ko = Hwaro::Models::LanguageConfig.new("ko")
      ko.menus = {"main" => [menu_item("소개", "/ko/about-us/", identifier: "about")]}
      config.languages = {"ko" => ko}
      sections = [
        auto_section("posts", "Posts"),
        auto_section("about", "About"),
        auto_section("posts", "글", language: "ko"),
        auto_section("about", "정보", language: "ko"),
      ]

      trees = Hwaro::Content::Menus.build(config, [] of Hwaro::Models::Page, sections)
      trees["en"]["main"].map { |e| {e.name, e.url} }.should eq([{"About", "/about/"}, {"Posts", "/posts/"}])
      trees["ko"]["main"].map { |e| {e.name, e.url} }.should eq([{"글", "/ko/posts/"}, {"소개", "/ko/about-us/"}])
    end
  end
end
