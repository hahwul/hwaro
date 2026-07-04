require "../spec_helper"

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
end
