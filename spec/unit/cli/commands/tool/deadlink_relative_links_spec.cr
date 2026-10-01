require "../../../../spec_helper"

# The build leaves a relative destination untouched, so the browser resolves
# it against the URL of the page that holds it. check-links resolved it
# against the SOURCE file's directory instead, which only agrees for index
# pages: from `content/posts/a.md` (served at `/posts/a/`), `../b/` reaches
# `/posts/b/` and `img.png` asks for `/posts/a/img.png` — the checker read
# them as `content/b` and `content/posts/img.png`.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def resolve_relative_for_test(links : Array(Link), content_dir : String,
                                language_codes : Array(String) = [] of String) : Array(Result)
    check_internal_links(links, content_dir, ["tags"], "", language_codes)
  end
end

private def write_rel_page(dir : String, relative : String, front_matter : String = "")
  path = File.join(dir, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "+++\ntitle = \"T\"\n#{front_matter}\n+++\nBody\n")
end

private def dead_relative(dir : String, from : String, urls : Array(String), kind : Symbol = :internal,
                          language_codes : Array(String) = [] of String) : Array(String)
  links = urls.map do |url|
    Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(file: File.join(dir, from), url: url, kind: kind)
  end
  cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
  cmd.resolve_relative_for_test(links, dir, language_codes).map(&.link.url).sort!
end

describe "check-links relative links" do
  it "resolves a leaf page's relative links against its URL" do
    Dir.mktmpdir do |dir|
      write_rel_page(dir, "index.md")
      write_rel_page(dir, "about.md")
      write_rel_page(dir, "posts/_index.md")
      write_rel_page(dir, "posts/a.md")
      write_rel_page(dir, "posts/b.md")

      # /posts/a/ + ../b/ = /posts/b/ (live); + ../about/ = /posts/about/ (dead);
      # + ../../about/ = /about/ (live); + ../ = /posts/ (live).
      dead_relative(dir, "posts/a.md", ["../b/", "../about/", "../../about/", "../", "../../tags/x/"]).should eq(["../about/"])
    end
  end

  it "resolves a root page's relative links against its URL" do
    Dir.mktmpdir do |dir|
      write_rel_page(dir, "index.md")
      write_rel_page(dir, "about.md")
      write_rel_page(dir, "links.md")

      # /links/ + ../about/ = /about/ (live); + about/ = /links/about/ (dead).
      dead_relative(dir, "links.md", ["../about/", "about/"]).should eq(["about/"])
    end
  end

  it "reports a leaf page's image that only exists beside its source" do
    Dir.mktmpdir do |dir|
      write_rel_page(dir, "index.md")
      write_rel_page(dir, "posts/_index.md")
      write_rel_page(dir, "posts/leaf.md")
      File.write(File.join(dir, "posts", "leaf.png"), "png")
      write_rel_page(dir, "posts/bundle/index.md")
      File.write(File.join(dir, "posts", "bundle", "pic.png"), "png")

      dead_relative(dir, "posts/leaf.md", ["leaf.png", "../leaf.png"], :image).should eq(["leaf.png"])
      dead_relative(dir, "posts/bundle/index.md", ["pic.png", "./pic.png"], :image).should be_empty
    end
  end

  it "resolves a translated page's relative links under its language prefix" do
    Dir.mktmpdir do |dir|
      write_rel_page(dir, "index.md")
      write_rel_page(dir, "posts/_index.md")
      write_rel_page(dir, "posts/_index.ko.md")
      write_rel_page(dir, "posts/a.md")
      write_rel_page(dir, "posts/a.ko.md")
      write_rel_page(dir, "posts/b.md")

      # /ko/posts/a/ + ../ = /ko/posts/ (live); + ../b/ = /ko/posts/b/ (b is untranslated).
      dead_relative(dir, "posts/a.ko.md", ["../", "../b/"], language_codes: ["ko"]).should eq(["../b/"])
    end
  end
end
