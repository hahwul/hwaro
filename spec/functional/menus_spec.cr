require "../support/build_helper"

# =============================================================================
# First-class menu system: functional coverage
#
# Exercises the full pipeline — config [[menus.*]] + front-matter menus/menu
# registration -> Content::Menus.build -> site.menus / get_menu() /
# active_path in real rendered output, including subpath base_url, per-language
# overrides, and --cache incremental rebuilds.
# =============================================================================

MENU_NAV_TEMPLATE = <<-HTML
  <nav>{% for item in get_menu(name="main") %}<a href="{{ item.href }}" data-url="{{ item.url }}" data-external="{{ item.external }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>{% endfor %}</nav>
  {{ content }}
  HTML

describe "Menus: config-defined" do
  it "renders [[menus.main]] entries via get_menu() in declaration/weight order" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [[menus.main]]
      name = "Home"
      url = "/"
      weight = 1

      [[menus.main]]
      name = "About"
      url = "/about/"
      weight = 2
      TOML

    build_site(
      config,
      content_files: {
        "index.md" => "---\ntitle: Home\n---\nHi",
        "about.md" => "---\ntitle: About\n---\nAbout body",
      },
      template_files: {"page.html" => MENU_NAV_TEMPLATE},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/" data-url="/" data-external="false" aria-current="page">Home</a>))
      html.should contain(%(<a href="/about/" data-url="/about/" data-external="false">About</a>))

      about_html = File.read("public/about/index.html")
      about_html.should contain(%(<a href="/about/" data-url="/about/" data-external="false" aria-current="page">About</a>))
    end
  end

  it "builds a parent/child hierarchy from `parent` identifiers" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [[menus.main]]
      name = "Posts"
      url = "/posts/"
      identifier = "posts"

      [[menus.main]]
      name = "First Post"
      url = "/posts/first/"
      parent = "posts"
      TOML

    template = <<-HTML
      {% for item in get_menu(name="main") %}{{ item.name }}[{% for c in item.children %}{{ c.name }}{% endfor %}]{% endfor %}
      HTML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHi"},
      template_files: {"page.html" => template},
    ) do
      html = File.read("public/index.html")
      html.should contain("Posts[First Post]")
    end
  end
end

describe "Menus: front-matter registration" do
  it "a page registered into a menu via front matter appears in the nav" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      TOML

    build_site(
      config,
      content_files: {
        "index.md" => "---\ntitle: Home\n---\nHi",
        "about.md" => "+++\ntitle = \"About\"\nmenus = [\"main\"]\n+++\nAbout body",
      },
      template_files: {"page.html" => MENU_NAV_TEMPLATE},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/about/" data-url="/about/" data-external="false">About</a>))
    end
  end

  it "table-form front matter overrides name/weight/identifier/parent" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      TOML

    build_site(
      config,
      content_files: {
        "index.md" => "---\ntitle: Home\n---\nHi",
        "about.md" => <<-MD,
          +++
          title = "About"

          [menus.main]
          name = "Who We Are"
          weight = 5
          +++
          About body
          MD
      },
      template_files: {"page.html" => MENU_NAV_TEMPLATE},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(data-url="/about/" data-external="false">Who We Are</a>))
      html.should_not contain(">About<")
    end
  end
end

describe "Menus: subpath base_url" do
  it "prefixes internal hrefs with the base_path while leaving external urls untouched" do
    config = <<-TOML
      title = "Test Site"
      base_url = "https://x.com/repo"

      [[menus.main]]
      name = "About"
      url = "/about/"

      [[menus.main]]
      name = "Docs"
      url = "https://docs.example.com/"
      TOML

    build_site(
      config,
      content_files: {
        "index.md" => "---\ntitle: Home\n---\nHi",
        "about.md" => "---\ntitle: About\n---\nAbout body",
      },
      template_files: {"page.html" => MENU_NAV_TEMPLATE},
    ) do
      html = File.read("public/index.html")
      # Internal entry: href carries the /repo subpath, url stays bare
      # (root-relative, comparable to page.url for active_path).
      html.should contain(%(<a href="/repo/about/" data-url="/about/" data-external="false">About</a>))
      # External entry: href and url are both the untouched absolute URL.
      html.should contain(%(<a href="https://docs.example.com/" data-url="https://docs.example.com/" data-external="true">Docs</a>))
    end
  end
end

describe "Menus: multilingual" do
  it "a per-language menu override is picked up by get_menu() on that language's pages" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [languages.ko]
      language_name = "한국어"
      weight = 1

      [[menus.main]]
      name = "About"
      url = "/about/"

      [[languages.ko.menus.main]]
      name = "소개"
      url = "/ko/about/"
      TOML

    build_site(
      config,
      content_files: {
        "about.md"    => "---\ntitle: About\n---\nEnglish",
        "about.ko.md" => "---\ntitle: 소개\n---\n한국어",
      },
      template_files: {"page.html" => MENU_NAV_TEMPLATE},
    ) do
      en_html = File.read("public/about/index.html")
      en_html.should contain(%(data-url="/about/" data-external="false" aria-current="page">About</a>))

      ko_html = File.read("public/ko/about/index.html")
      ko_html.should contain(%(data-url="/ko/about/" data-external="false" aria-current="page">소개</a>))
      ko_html.should_not contain(">About<")
    end
  end
end

describe "Menus: --cache incremental rebuild" do
  it "re-renders a page whose template calls get_menu() when another page's front-matter menu registration changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML)
          title = "Test Site"
          base_url = "http://localhost"
          TOML
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", MENU_NAV_TEMPLATE)
        # Page A: renders the "main" menu via get_menu(). Page B: not
        # registered into any menu (yet).
        File.write("content/a.md", "---\ntitle: A\n---\nPage A")
        File.write("content/b.md", "---\ntitle: B\n---\nPage B")

        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false))

        a_html_before = File.read("public/a/index.html")
        a_html_before.should_not contain("data-url=\"/b/\"")

        # Page A's OWN source is unchanged; only page B (unrelated to A)
        # gains a menu registration. Without the __menus__/get_menu markers
        # in PAGE_SET_MARKERS, A's cache entry alone would short-circuit the
        # rebuild and it would keep serving the stale nav forever.
        sleep 100.milliseconds
        File.write("content/b.md", "+++\ntitle = \"B\"\nmenus = [\"main\"]\n+++\nPage B")

        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false))

        a_html_after = File.read("public/a/index.html")
        a_html_after.should contain("data-url=\"/b/\"")
      end
    end
  end
end

describe "Menus: [menus] auto_sections" do
  it "fills the menu from top-level sections per language, with config overrides by identifier" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [languages.ko]
      language_name = "한국어"
      weight = 1

      [menus]
      auto_sections = "main"

      [[menus.main]]
      name = "Journal"
      url = "/posts/"
      identifier = "posts"
      weight = 3
      TOML

    build_site(
      config,
      content_files: {
        "posts/_index.md"     => "+++\ntitle = \"Posts\"\nweight = 1\n+++\n",
        "posts/_index.ko.md"  => "+++\ntitle = \"글\"\nweight = 1\n+++\n",
        "posts/hello.md"      => "---\ntitle: Hello\n---\nHi",
        "posts/sub/_index.md" => "+++\ntitle = \"Sub\"\n+++\n",
        "docs/_index.md"      => "+++\ntitle = \"Docs\"\nweight = 2\n+++\n",
        "docs/_index.ko.md"   => "+++\ntitle = \"문서\"\nweight = 2\n+++\n",
        "flat/_index.md"      => "+++\ntitle = \"Flat\"\ntransparent = true\n+++\n",
        "wip/_index.md"       => "+++\ntitle = \"WIP\"\ndraft = true\n+++\n",
        "about.md"            => "---\ntitle: About\n---\nAbout",
      },
      template_files: {
        "page.html"    => MENU_NAV_TEMPLATE,
        "section.html" => MENU_NAV_TEMPLATE,
      },
    ) do
      en_html = File.read("public/posts/hello/index.html")
      en_html.should contain(%(<nav><a href="/docs/" data-url="/docs/" data-external="false">Docs</a><a href="/posts/" data-url="/posts/" data-external="false">Journal</a></nav>))

      ko_html = File.read("public/ko/docs/index.html")
      # ko inherits the global [[menus.main]] override; its own sections
      # supply the rest.
      ko_html.should contain(%(<nav><a href="/ko/docs/" data-url="/ko/docs/" data-external="false" aria-current="page">문서</a><a href="/posts/" data-url="/posts/" data-external="false">Journal</a></nav>))
    end
  end

  it "re-renders the nav on a --cache build when a top-level section turns headless" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost\"\n[menus]\nauto_sections = \"main\"\n")
        FileUtils.mkdir_p("content/docs")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", MENU_NAV_TEMPLATE)
        File.write("templates/section.html", MENU_NAV_TEMPLATE)
        File.write("content/a.md", "---\ntitle: A\n---\nPage A")
        File.write("content/docs/_index.md", "+++\ntitle = \"Docs\"\n+++\n")

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)
        builder1 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder1.register(h) }
        builder1.run(options)
        File.read("public/a/index.html").should contain(%(data-url="/docs/"))

        sleep 100.milliseconds
        File.write("content/docs/_index.md", "+++\ntitle = \"Docs\"\nrender = false\n+++\n")

        builder2 = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder2.register(h) }
        builder2.run(options)
        File.read("public/a/index.html").should_not contain(%(data-url="/docs/"))
      end
    end
  end
end

describe "Menus: auto_sections default-language fallback" do
  it "a language with no translated top-level section falls back to the default-language menu" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [languages.ko]
      language_name = "한국어"

      [menus]
      auto_sections = "main"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n+++\n",
        "about.md"       => "---\ntitle: About\n---\nEN",
        "about.ko.md"    => "---\ntitle: 소개\n---\nKO",
      },
      template_files: {"page.html" => MENU_NAV_TEMPLATE, "section.html" => MENU_NAV_TEMPLATE},
    ) do
      File.read("public/ko/about/index.html").should contain(%(<nav><a href="/blog/" data-url="/blog/" data-external="false">Blog</a></nav>))
    end
  end
end
