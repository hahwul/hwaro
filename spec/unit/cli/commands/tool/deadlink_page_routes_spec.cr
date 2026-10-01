require "../../../../spec_helper"

# check-links read the source tree as the URL space: `/posts/x/` was live
# whenever `content/posts/x.md` existed. Measured against what `hwaro build`
# writes, that was wrong both ways — every `slug` / `path` / alias URL was
# reported dead until a build had populated `public/` (the lint-then-build
# order CI uses), while links to drafts, to the pre-`slug` path and to the
# `.md` source itself passed although the build writes none of them.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def resolve_page_routes_for_test(links : Array(Link), content_dir : String,
                                   language_codes : Array(String) = [] of String) : Array(Result)
    check_internal_links(links, content_dir, [] of String, "", language_codes)
  end
end

private def route_link(dir : String, url : String, from : String = "index.md", kind : Symbol = :internal)
  Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(file: File.join(dir, from), url: url, kind: kind)
end

private def write_page(dir : String, relative : String, front_matter : String = "", body : String = "Body")
  path = File.join(dir, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "+++\ntitle = \"T\"\n#{front_matter}\n+++\n#{body}\n")
end

# Dead link URL → error, for every link in `urls` checked from `from`.
private def dead_routes(dir : String, urls : Array(String), from : String = "index.md",
                        kind : Symbol = :internal, language_codes : Array(String) = [] of String) : Hash(String, String)
  links = urls.map { |url| route_link(dir, url, from, kind) }
  cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
  cmd.resolve_page_routes_for_test(links, dir, language_codes).to_h { |r| {r.link.url, r.error.to_s} }
end

describe "check-links page routes" do
  it "accepts slug, path and alias URLs before any build" do
    Dir.mktmpdir do |dir|
      write_page(dir, "index.md")
      write_page(dir, "posts/slugged.md", %(slug = "renamed"\naliases = ["/old-home/", "legacy"]))
      write_page(dir, "posts/custom.md", %(path = "special-place"))
      write_page(dir, "posts/bundle/index.md", %(slug = "moved-bundle"))

      dead_routes(dir, ["/posts/renamed/", "/special-place/", "/old-home/", "/legacy/", "/posts/moved-bundle/"]).should be_empty
    end
  end

  it "reports the source path of a page the build publishes elsewhere" do
    Dir.mktmpdir do |dir|
      write_page(dir, "index.md")
      write_page(dir, "posts/slugged.md", %(slug = "renamed"))
      write_page(dir, "posts/custom.md", %(path = "special-place"))

      dead = dead_routes(dir, ["/posts/slugged/", "/posts/custom/"])
      dead["/posts/slugged/"].should eq("Internal link target not found: the page is published at /posts/renamed/")
      dead["/posts/custom/"].should eq("Internal link target not found: the page is published at /special-place/")
    end
  end

  it "reports links to pages a default build does not write" do
    Dir.mktmpdir do |dir|
      write_page(dir, "index.md")
      write_page(dir, "posts/drafty.md", "draft = true")
      write_page(dir, "posts/later.md", "date = 2999-01-01")
      write_page(dir, "posts/headless.md", "render = false")
      write_page(dir, "posts/draft-bundle/index.md", "draft = true")

      dead = dead_routes(dir, ["/posts/drafty/", "/posts/later/", "/posts/headless/", "/posts/draft-bundle/"])
      dead["/posts/drafty/"].should eq("Internal link not resolved by the build: target is a draft")
      dead["/posts/later/"].should eq("Internal link not resolved by the build: target is future-dated")
      dead["/posts/headless/"].should eq("Internal link not resolved by the build: target sets render = false")
      dead["/posts/draft-bundle/"].should eq("Internal link not resolved by the build: target is a draft")
    end
  end

  it "does not treat a Markdown source file as a published route" do
    Dir.mktmpdir do |dir|
      write_page(dir, "index.md")
      write_page(dir, "about.md")
      write_page(dir, "posts/_index.md")

      dead_routes(dir, ["/about.md", "/posts/_index.md"]).keys.sort!.should eq(["/about.md", "/posts/_index.md"])
      dead_routes(dir, ["/about/", "/about", "/about/index.html", "/posts/"]).should be_empty
    end
  end

  it "accepts a translated bundle's files under the language prefix" do
    Dir.mktmpdir do |dir|
      write_page(dir, "index.md")
      write_page(dir, "posts/_index.md")
      write_page(dir, "posts/_index.ko.md")
      write_page(dir, "posts/bun/index.md")
      write_page(dir, "posts/bun/index.ko.md", %(slug = "beon"))
      File.write(File.join(dir, "posts", "bun", "p.png"), "png")

      dead_routes(dir, ["/ko/posts/beon/p.png", "/posts/bun/p.png"], kind: :image, language_codes: ["ko"]).should be_empty
      dead_routes(dir, ["/ko/posts/bun/p.png", "/ko/posts/beon/missing.png"], kind: :image, language_codes: ["ko"]).size.should eq(2)
    end
  end

  it "requires a translated page to publish at the linked URL" do
    Dir.mktmpdir do |dir|
      write_page(dir, "index.md")
      write_page(dir, "about.md")
      write_page(dir, "about.ko.md", %(slug = "sogae"))

      dead = dead_routes(dir, ["/ko/sogae/", "/ko/about/"], language_codes: ["ko"])
      dead.keys.should eq(["/ko/about/"])
      dead["/ko/about/"].should eq("Internal link target not found: the page is published at /ko/sogae/")
    end
  end
end

class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def resolve_page_routes_with_config_for_test(links : Array(Link), content_dir : String,
                                               config : Hwaro::Models::Config) : Array(Result)
    check_internal_links(links, content_dir, [] of String, "", [] of String, GeneratedRoutes.new,
      Hwaro::Utils::BuildOutput.oracle("public", tool: "check-links"), config)
  end
end

describe "check-links page routes for an unplaced linking page" do
  # `[git] use_date` + a date-token permalink keeps a dateless page out of
  # the route index, so its relative links stay relative (resolved against
  # the source directory). They used to go through the published-URL lookup
  # as `/../b/` and be reported "published at /b/" — a live link.
  it "keeps the existence test for relative links from a page the index cannot place" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.toml")
      File.write(config_path, "title = \"T\"\nbase_url = \"https://example.com\"\n[git]\nenabled = true\nuse_date = true\n[permalinks]\nposts = \"/:year/:slug/\"\n")
      config = Hwaro::Models::Config.load(config_path)
      content = File.join(dir, "content")
      write_page(content, "b.md")
      write_page(content, "posts/a.md")

      link = route_link(content, "../b/", "posts/a.md")
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.resolve_page_routes_with_config_for_test([link], content, config).should be_empty
    end
  end
end
