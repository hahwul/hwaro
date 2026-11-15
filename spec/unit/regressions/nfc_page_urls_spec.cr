require "../../spec_helper"
require "../../support/build_helper"

# The same sources must publish the same site whatever Unicode form their
# file names are stored in: macOS tools often hand out decomposed (NFD) names,
# Linux checkouts and keyboards precomposed (NFC) ones. Page URLs, and every
# output name derived from a content path, are spelled NFC.

private def nfd(s : String) : String
  s.unicode_normalize(:nfd)
end

# Every entry under `root`, relative, as the file system spells it.
private def output_names(root : String) : Array(String)
  Dir.glob(File.join(root, "**", "*")).map { |path| Path[path].relative_to(root).to_s }.sort!
end

private def nfc_url_png(w : Int32, h : Int32) : String
  Dir.mktmpdir do |dir|
    path = File.join(dir, "x.png")
    px = Bytes.new(w * h * 3, 90_u8)
    LibStb.stbi_write_png(path, w, h, 3, px.to_unsafe.as(Void*), w * 3)
    File.read(path)
  end
end

class Hwaro::Core::Build::Builder
  def test_nfc_url_winners(pages : Array(Models::Page)) : Hash(String, String)
    compute_output_url_winners(pages)
  end
end

describe "NFC page URLs" do
  it "publishes NFD-named content under the NFC names an NFC checkout gets" do
    config = <<-TOML
      title = "T"
      base_url = "http://localhost"
      [search]
      enabled = true
      shards = "section"
      [image_processing]
      enabled = true
      widths = [16]
      [permalinks]
      "블로그" = "/글/:slug/"
      TOML
    content = {
      nfd("블로그/_index.md")    => "+++\ntitle = \"B\"\n+++\n",
      nfd("블로그/첫 글.md")       => "+++\ntitle = \"P\"\n+++\nbody\n",
      nfd("café/_index.md")   => "+++\ntitle = \"C\"\n+++\n",
      nfd("café/번들/index.md") => "+++\ntitle = \"Bundle\"\n+++\n![x](그림.png)\n",
      nfd("café/번들/그림.png")   => nfc_url_png(32, 32),
      nfd("café/번들/메모.txt")   => "memo\n",
      nfd("café/슬러그.md")      => "+++\ntitle = \"S\"\nslug = \"#{nfd("이름")}\"\n+++\n",
    }
    templates = {"page.html" => "U={{ page.url }}|{{ content }}", "section.html" => "U={{ section.url }}"}
    build_site(config, content_files: content, template_files: templates) do
      names = output_names("public")
      names.reject { |n| n == n.unicode_normalize(:nfc) }.should be_empty
      names.should contain("글/첫 글/index.html")
      names.should contain("café/번들/그림.png")
      names.should contain("café/번들/그림_16w.png")
      names.should contain("café/번들/메모.txt")
      names.should contain("café/이름/index.html")
      names.should contain("search/블로그.json")
      File.read("public/글/첫 글/index.html").should start_with("U=/글/첫 글/|")
      File.read("public/café/번들/index.html").should contain("%EA%B7%B8%EB%A6%BC_16w.png 16w")
    end
  end

  it "lists and tie-breaks NFD-stored pages in the NFC order" do
    # `crème` sorts after `crf`, its NFD spelling `crème` before.
    config = "title = \"T\"\nbase_url = \"http://localhost\"\n[sitemap]\nenabled = true\n"
    content = {
      "_index.md"     => "+++\ntitle = \"H\"\n+++\n",
      nfd("crème.md") => "+++\ntitle = \"Creme\"\n+++\n",
      "crf.md"        => "+++\ntitle = \"Crf\"\n+++\n",
    }
    templates = {"page.html" => "x", "section.html" => "{% for p in section.pages %}{{ p.title }},{% endfor %}"}
    build_site(config, content_files: content, template_files: templates) do
      File.read("public/index.html").should eq("Crf,Creme,")
      sitemap = File.read("public/sitemap.xml")
      sitemap.index!("/crf/").should be < sitemap.index!("/cr%C3%A8me/")
    end
  end

  it "routes two names that differ only in Unicode form through the duplicate-output check" do
    # Only a normalization-sensitive file system (ext4) can hold both; build
    # the pages in memory instead.
    config = Hwaro::Models::Config.new
    pages = {"한글.md", nfd("한글.md")}.map do |path|
      page = Hwaro::Models::Page.new(path)
      page.url = Hwaro::Utils::PermalinkResolver.resolve_url(path, config, slug: nil, custom_path: nil, language: nil, date: nil, title: "t")
      page
    end.to_a
    pages.map(&.url).uniq!.should eq(["/한글/"])

    builder = Hwaro::Core::Build::Builder.new
    log = with_captured_log { builder.test_nfc_url_winners(pages) }
    pages.count(&.output_suppressed).should eq(1)
    winner = pages.find! { |p| !p.output_suppressed }
    winner.path.should eq(nfd("한글.md")) # byte order: U+1112 sorts before U+D55C
    log.should contain("Duplicate output path '/한글/'")
    log.should contain("differ only in Unicode form")
  end
end
