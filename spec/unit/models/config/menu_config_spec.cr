require "../../../spec_helper"

# Helper to load a Config from a TOML string via a temp file.
describe "menu configuration" do
  it "has empty menus by default" do
    config = Hwaro::Models::Config.new
    config.menus.should eq({} of String => Array(Hwaro::Models::MenuItemConfig))
  end

  it "parses [[menus.*]] array-of-tables into named menu lists" do
    config = load_config(<<-TOML)
      title = "Test"

      [[menus.main]]
      name = "Posts"
      url = "/posts/"
      weight = 1
      identifier = "posts"

      [[menus.main]]
      name = "About"
      url = "/about/"
      weight = 2

      [[menus.footer]]
      name = "Privacy"
      url = "/privacy/"
      TOML

    config.menus.keys.sort!.should eq(["footer", "main"])
    main = config.menus["main"]
    main.size.should eq(2)
    main[0].name.should eq("Posts")
    main[0].url.should eq("/posts/")
    main[0].weight.should eq(1)
    main[0].identifier.should eq("posts")
    main[0].parent.should be_nil

    main[1].name.should eq("About")
    main[1].url.should eq("/about/")
    main[1].weight.should eq(2)

    config.menus["footer"].size.should eq(1)
    config.menus["footer"][0].name.should eq("Privacy")
  end

  it "defaults url to empty, weight to 0, identifier to name, and parent to nil" do
    config = load_config(<<-TOML)
      title = "Test"

      [[menus.main]]
      name = "Posts"
      TOML

    entry = config.menus["main"][0]
    entry.name.should eq("Posts")
    entry.url.should eq("")
    entry.weight.should eq(0)
    entry.identifier.should eq("Posts")
    entry.parent.should be_nil
  end

  it "reads parent when set" do
    config = load_config(<<-TOML)
      title = "Test"

      [[menus.main]]
      name = "Posts"
      identifier = "posts"

      [[menus.main]]
      name = "First Post"
      parent = "posts"
      TOML

    config.menus["main"][1].parent.should eq("posts")
  end

  it "skips entries missing the required name and warns" do
    captured = IO::Memory.new
    original_io = Hwaro::Logger.io
    Hwaro::Logger.io = captured
    config = begin
      load_config(<<-TOML)
        title = "Test"

        [[menus.main]]
        url = "/no-name/"

        [[menus.main]]
        name = "Kept"
        TOML
    ensure
      Hwaro::Logger.io = original_io
    end

    config.menus["main"].size.should eq(1)
    config.menus["main"][0].name.should eq("Kept")
    captured.to_s.should contain("Skipping")
    captured.to_s.should contain("menus.main")
  end

  it "loads a per-language menu override" do
    config = load_config(<<-TOML)
      title = "Test"
      default_language = "en"

      [[menus.main]]
      name = "Posts"
      url = "/posts/"

      [languages.ko]
      language_name = "Korean"

      [[languages.ko.menus.main]]
      name = "글"
      url = "/ko/posts/"
      TOML

    config.languages["ko"].menus.should_not be_nil
    ko_menus = config.languages["ko"].menus.not_nil!
    ko_menus["main"][0].name.should eq("글")
    ko_menus["main"][0].url.should eq("/ko/posts/")

    # Global menus remain untouched.
    config.menus["main"][0].name.should eq("Posts")
  end

  it "inherits the global menu set wholesale when [languages.<code>] omits menus" do
    config = load_config(<<-TOML)
      title = "Test"
      default_language = "en"

      [[menus.main]]
      name = "Posts"
      url = "/posts/"

      [languages.fr]
      language_name = "French"
      TOML

    config.languages["fr"].menus.should be_nil
  end

  it "parses [menus] auto_sections alongside [[menus.*]] tables" do
    config = load_config(<<-TOML)
      title = "Test"

      [menus]
      auto_sections = "main"

      [[menus.main]]
      name = "About"
      url = "/about/"
      TOML

    config.menus_auto_sections.should eq("main")
    config.menus.keys.should eq(["main"])
    config.menus["main"].map(&.name).should eq(["About"])
  end

  it "leaves auto_sections off when absent" do
    Hwaro::Models::Config.new.menus_auto_sections.should be_nil
    load_config(%(title = "T"\n[[menus.main]]\nname = "A"\n)).menus_auto_sections.should be_nil
  end

  it "rejects a non-string or blank auto_sections with a config error" do
    [%(["main"]), "true", %("  ")].each do |value|
      err = expect_config_error(%(title = "T"\n[menus]\nauto_sections = #{value}\n))
      err.message.to_s.should contain("[menus] auto_sections must be a menu name string")
    end
  end

  it "reserves auto_sections: never parsed as a menu" do
    expect_config_error(%(title = "T"\n[[menus.auto_sections]]\nname = "A"\n))
    config = load_config(%(title = "T"\n[menus]\nauto_sections = "main"\n))
    config.menus.has_key?("auto_sections").should be_false
  end

  it "warns on a per-language auto_sections and keeps inheriting the global menus" do
    config = nil
    log = with_captured_log do
      config = load_config(<<-TOML)
        title = "T"
        [[menus.main]]
        name = "A"
        [languages.ko]
        [languages.ko.menus]
        auto_sections = "nav"
        TOML
    end
    log.should contain("[languages.ko.menus] auto_sections is ignored: the name is reserved")
    log.should contain("for a menu, pick another name")
    config.not_nil!.languages["ko"].menus.should be_nil
  end
end
