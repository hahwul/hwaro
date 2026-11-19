require "../../../../spec_helper"

# `Builder#plan_urls` — the URL preview behind `hwaro tool urls`.
#
# The contract is "what a build would publish", so the main examples are an
# oracle: plan the site, check nothing was written, build it for real, and
# compare the plan against the files on disk.

private URL_PLAN_CONFIG = <<-TOML
  title = "Plan"
  base_url = "http://localhost"

  [feeds]
  enabled = true

  [[taxonomies]]
  name = "tags"
  feed = true
  paginate_by = 2

  [[taxonomies]]
  name = "categories"
  TOML

private def write_site(config : String, files : Hash(String, String)) : Nil
  File.write("config.toml", config)
  FileUtils.mkdir_p("templates")
  %w[page section taxonomy taxonomy_term].each do |name|
    File.write("templates/#{name}.html", "<html>{{ content }}</html>")
  end
  files.each do |path, body|
    full = File.join("content", path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end
end

private def page(front_matter : String) : String
  "+++\n#{front_matter}\n+++\n\nBody\n"
end

private def plan(drafts : Bool = false) : Array(Hwaro::Core::Build::Builder::PlannedUrl)
  Hwaro::Core::Build::Builder.new.plan_urls(Hwaro::Config::Options::BuildOptions.new(drafts: drafts))
end

# The URL of every HTML page and feed a real build wrote, minus the outputs
# `plan_urls` leaves out on purpose.
private def built_urls(drafts : Bool = false) : Array(String)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(drafts: drafts, parallel: false, highlight: false)).should be_true
  Dir.glob("public/**/*.{html,xml}").map(&.lchop("public").gsub('\\', '/').sub(/\/index\.html\z/, "/")).reject(&.in?("/404.html", "/sitemap.xml")).sort!
end

private def in_site(config : String, files : Hash(String, String), &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      write_site(config, files)
      yield
    end
  end
end

private DENSE_SITE = {
  "index.md"          => page(%(title = "Home")),
  "about.md"          => page(%(title = "About"\naliases = ["/me/", "old-about", "/legacy.html", "https://x.test/y", "/../up/", "/posts/", "/About/"])),
  "posts/_index.md"   => page(%(title = "Posts"\npaginate = 2\ngenerate_feeds = true)),
  "posts/a.md"        => page(%(title = "A"\ndate = "2024-01-01"\ntags = ["x", "C++", "C#"]\ncategories = ["one"])),
  "posts/b.md"        => page(%(title = "B"\ndate = "2024-01-02"\ntags = ["x"]\naliases = ["/posts/page/2/"])),
  "posts/c.md"        => page(%(title = "C"\ndate = "2024-01-03"\ntags = ["x"])),
  "posts/d.md"        => page(%(title = "D"\ndate = "2024-01-04"\ntags = ["x"]\nslug = "c")),
  "posts/e.md"        => page(%(title = "E"\ndate = "2024-01-05"\ntags = ["x"]\npath = "moved/here")),
  "posts/draft.md"    => page(%(title = "Draft"\ndraft = true\ntags = ["draft-only"]\naliases = ["/draft-old/"])),
  "posts/future.md"   => page(%(title = "Future"\ndate = "2999-01-01")),
  "posts/expired.md"  => page(%(title = "Expired"\ndate = "2020-01-01"\nexpires = "2020-06-01")),
  "posts/hidden.md"   => page(%(title = "Hidden"\nrender = false\naliases = ["/hidden-old/"])),
  "posts/redirect.md" => page(%(title = "Redirect"\nredirect_to = "/about/"\naliases = ["/redirect-old/"])),
  "tags/x/_index.md"  => page(%(title = "The X tag"\naliases = ["/x/", "/tags/"])),
  "bundle/index.md"   => page(%(title = "Bundle")),
}

describe "Hwaro::Core::Build::Builder#plan_urls" do
  it "lists exactly the pages, aliases, pager pages, taxonomy pages and feeds a build writes" do
    in_site(URL_PLAN_CONFIG, DENSE_SITE) do
      planned = plan
      Dir.exists?("public").should be_false
      Dir.exists?(".hwaro").should be_false
      planned.map(&.url).sort!.should eq(built_urls)
    end
  end

  it "matches the build under --drafts" do
    in_site(URL_PLAN_CONFIG, DENSE_SITE) do
      planned = plan(drafts: true).map(&.url)
      planned.should contain("/posts/draft/")
      planned.should contain("/draft-old/")
      # A draft previews, but stays out of the generated listings.
      planned.should_not contain("/tags/draft-only/")
      planned.sort!.should eq(built_urls(drafts: true))
    end
  end

  it "labels each URL with its kind and source" do
    in_site(URL_PLAN_CONFIG, DENSE_SITE) do
      by_url = plan.index_by(&.url)
      {
        "/"               => {"page", "content/index.md"},
        "/posts/"         => {"section", "content/posts/_index.md"},
        "/posts/page/2/"  => {"pagination", "content/posts/_index.md"},
        "/moved/here/"    => {"page", "content/posts/e.md"},
        "/me/"            => {"alias", "content/about.md"},
        "/legacy.html"    => {"alias", "content/about.md"},
        "/x/"             => {"alias", "content/tags/x/_index.md"},
        "/tags/"          => {"taxonomy", nil},
        "/tags/x/"        => {"term", nil},
        "/tags/x/page/2/" => {"pagination", nil},
        "/tags/c-2/"      => {"term", nil},
        "/tags/x/rss.xml" => {"feed", nil},
        "/posts/rss.xml"  => {"feed", nil},
        "/rss.xml"        => {"feed", nil},
      }.each do |url, (kind, source)|
        entry = by_url[url]?
        entry.should_not be_nil, "expected #{url} in the plan"
        next unless entry
        {entry.kind, entry.source}.should eq({kind, source}), "for #{url}"
      end
    end
  end

  it "leaves out what the build refuses to write" do
    in_site(URL_PLAN_CONFIG, DENSE_SITE) do
      urls = plan.map(&.url)
      # Unpublished pages and their aliases.
      urls.should_not contain("/posts/draft/")
      urls.should_not contain("/draft-old/")
      urls.should_not contain("/posts/future/")
      urls.should_not contain("/posts/expired/")
      # `render = false` writes no page.
      urls.should_not contain("/posts/hidden/")
      # Collision loser (posts/d.md takes the slug of posts/c.md): one row.
      urls.count("/posts/c/").should eq(1)
      urls.should_not contain("/posts/d/")
      # External and traversing aliases.
      urls.none?(&.includes?("x.test")).should be_true
      urls.none?(&.includes?("up")).should be_true
    end
  end

  it "plans language prefixes, permalinks, versions and generated pages" do
    config = <<-TOML
      title = "Plan"
      base_url = "http://localhost"
      default_language = "en"

      [languages.en]
      language_name = "English"
      taxonomies = ["tags"]

      [languages.ko]
      language_name = "Korean"
      generate_feed = true
      taxonomies = ["tags"]

      [feeds]
      enabled = true

      [[taxonomies]]
      name = "tags"

      [permalinks]
      "notes" = "/n/:year/:slug/"

      [versions]
      latest_at_root = true

      [[versions.list]]
      name = "v2"
      path = "docs/v2"
      latest = true

      [[versions.list]]
      name = "v1"
      path = "docs/v1"

      [[content.generate]]
      source = "products"
      section = "products"
      slug = "sku"
      title = "name"
      TOML
    files = {
      "index.md"           => page(%(title = "Home")),
      "index.ko.md"        => page(%(title = "Home")),
      "notes/_index.md"    => page(%(title = "Notes")),
      "notes/n1.md"        => page(%(title = "N1"\ndate = "2024-03-04"\ntags = ["a"])),
      "notes/n1.ko.md"     => page(%(title = "N1"\ndate = "2024-03-04"\ntags = ["b"])),
      "docs/v1/_index.md"  => page(%(title = "v1")),
      "docs/v1/install.md" => page(%(title = "Install")),
      "docs/v2/_index.md"  => page(%(title = "v2")),
      "docs/v2/install.md" => page(%(title = "Install")),
    }
    in_site(config, files) do
      FileUtils.mkdir_p("data")
      File.write("data/products.json", %([{"sku": "Blue Widget", "name": "Blue"}]))
      planned = plan
      urls = planned.map(&.url)
      urls.should contain("/n/2024/n1/")
      urls.should contain("/ko/n/2024/n1/")
      urls.should contain("/tags/a/")
      urls.should contain("/ko/tags/b/")
      urls.should_not contain("/ko/tags/a/")
      urls.should contain("/ko/rss.xml")
      urls.should contain("/docs/install/")
      urls.should contain("/docs/v1/install/")
      urls.should contain("/products/blue-widget/")
      planned.find! { |entry| entry.url == "/products/blue-widget/" }.source.should be_nil
      Dir.exists?("public").should be_false
      urls.sort!.should eq(built_urls)
    end
  end

  it "makes no network request: a generate rule over a remote key is skipped" do
    config = <<-TOML
      title = "Plan"
      base_url = "http://localhost"

      [[data.remote]]
      key = "team"
      url = "http://127.0.0.1:1/unreachable.json"

      [[content.generate]]
      source = "team"
      section = "people"
      slug = "id"
      title = "name"
      TOML
    in_site(config, {"index.md" => page(%(title = "Home"))}) do
      urls = [] of String
      warnings = with_captured_log { urls = plan.map(&.url) }
      urls.should eq(["/"])
      warnings.should contain(%([[content.generate]] "team": remote source))
      Dir.exists?(".hwaro").should be_false
    end
  end

  it "spells an alias the way page URLs are spelled" do
    files = {
      "a b.md" => page(%(title = "Spaced"\naliases = ["/old%20name/", "/plain"])),
    }
    in_site(URL_PLAN_CONFIG, files) do
      by_url = plan.index_by(&.url)
      by_url["/old%20name/"]?.try(&.kind).should eq("alias")
      by_url["/plain/"]?.try(&.kind).should eq("alias")
      by_url.keys.any?(&.includes?("old name")).should be_false
    end
  end

  it "raises the build's own classified error for a broken site" do
    in_site(URL_PLAN_CONFIG, {"bad.md" => "+++\ntitle = \"open\n+++\n"}) do
      expect_raises(Hwaro::HwaroError, /Invalid TOML frontmatter/) { plan }
    end
  end
end
