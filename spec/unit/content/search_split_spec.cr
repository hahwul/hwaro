require "../../spec_helper"
require "../../support/build_helper"

# =============================================================================
# `[search] split_by_heading` and `[search] facets`.
#
# Contract: the page record stays byte-identical; split adds one record per
# h2/h3 (`url#id` with the real rendered id, `heading`, the section's text),
# sharing the page's scoping and shard. Facets add a field to every record.
# =============================================================================

private SPLIT_CONFIG = <<-TOML
  title = "T"
  base_url = "http://localhost"

  [search]
  enabled = true
  fields = ["title", "content"]
  split_by_heading = true
  TOML

private SPLIT_PAGE = <<-MD
  +++
  title = "Guide"
  tags = ["a"]
  +++
  Intro.

  ## Install Steps

  Run <b>it</b> &amp; wait.

  ### Custom {#my-id}

  Nested.

  #### Deep

  Still nested.

  ## 한국어 제목

  내용.
  MD

private def records(dir : String, file = "public/search.json") : Array(JSON::Any)
  JSON.parse(File.read(File.join(dir, file))).as_a
end

describe "search split_by_heading" do
  it "adds one record per h2/h3 with the real heading id" do
    build_site(SPLIT_CONFIG, content_files: {"guide.md" => SPLIT_PAGE}) do |dir|
      recs = records(dir).select(&.["url"].as_s.starts_with?("/guide/"))
      recs.map(&.["url"].as_s).should eq(["/guide/", "/guide/#install-steps", "/guide/#my-id", "/guide/#한국어-제목"])
      html = File.read(File.join(dir, "public/guide/index.html"))
      recs[1..].each { |r| html.should contain(%(id="#{r["url"].as_s.split('#', 2)[1]}")) }

      page_rec = recs[0]
      page_rec["heading"]?.should be_nil
      page_rec["content"].as_s.should contain("Intro.")

      install = recs[1]
      install["title"].as_s.should eq("Guide")
      install["heading"].as_s.should eq("Install Steps")
      install["content"].as_s.should eq("Run it & wait.")
      install["lang"].as_s.should eq("en")
      # An h4 stays inside its h3 section.
      recs[2]["content"].as_s.should eq("Nested. Deep Still nested.")
      recs[3]["heading"].as_s.should eq("한국어 제목")
    end
  end

  it "keeps the page record byte-identical to an unsplit build" do
    plain = ""
    build_site(SPLIT_CONFIG.sub("split_by_heading = true", ""), content_files: {"guide.md" => SPLIT_PAGE}) do |dir|
      plain = File.read(File.join(dir, "public/search.json"))
    end
    build_site(SPLIT_CONFIG, content_files: {"guide.md" => SPLIT_PAGE}) do |dir|
      split = records(dir).reject { |r| r["heading"]? }
      split.to_json.should eq(plain)
    end
  end

  it "applies content_max_length to section text and respects in_search_index and drafts" do
    config = SPLIT_CONFIG + "\ncontent_max_length = 8\n"
    build_site(config, content_files: {
      "guide.md"  => SPLIT_PAGE,
      "hidden.md" => "+++\ntitle = \"Hidden\"\nin_search_index = false\n+++\n## Secret\n\nx\n",
      "draft.md"  => "+++\ntitle = \"Draft\"\ndraft = true\n+++\n## Wip\n\nx\n",
    }) do |dir|
      urls = records(dir).map(&.["url"].as_s)
      urls.none? { |u| u.includes?("hidden") || u.includes?("draft") }.should be_true
      records(dir).find! { |r| r["url"] == "/guide/#install-steps" }["content"].as_s.should eq("Run it &")
    end
  end

  it "puts section records in their page's shard and scopes them by language" do
    config = SPLIT_CONFIG.sub("split_by_heading = true", "split_by_heading = true\nshards = \"language\"") + <<-TOML

      [languages.ko]
      language_name = "Korean"
      build_search_index = true

      [languages.ja]
      language_name = "Japanese"
      build_search_index = false
      TOML
    build_site(config, content_files: {
      "guide.md"    => SPLIT_PAGE,
      "guide.ko.md" => "+++\ntitle = \"가이드\"\n+++\n## 설치\n\n본문\n",
      "guide.ja.md" => "+++\ntitle = \"ガイド\"\n+++\n## 導入\n\n本文\n",
    }) do |dir|
      en = records(dir, "public/search/en.json").map(&.["url"].as_s)
      en.should contain("/guide/#install-steps")
      ko = records(dir, "public/search/ko.json")
      ko.map(&.["url"].as_s).should eq(["/ko/guide/", "/ko/guide/#설치"])
      ko.all? { |r| r["lang"] == "ko" }.should be_true
      File.exists?(File.join(dir, "public/search/ja.json")).should be_false
      manifest = JSON.parse(File.read(File.join(dir, "public/search/index.json")))
      manifest["fields"].as_a.map(&.as_s).should eq(["title", "content", "url", "lang", "heading"])
      manifest["shards"].as_a.find! { |s| s["id"] == "ko" }["count"].should eq(2)
    end
  end

  it "keeps older versions' sections out under versions search = latest" do
    config = SPLIT_CONFIG + <<-TOML

      [versions]
      search = "latest"

      [[versions.list]]
      name = "v2"
      path = "docs/v2"
      latest = true

      [[versions.list]]
      name = "v1"
      path = "docs/v1"
      TOML
    build_site(config, content_files: {
      "docs/_index.md"    => "+++\ntitle = \"Docs\"\n+++\n",
      "docs/v2/_index.md" => "+++\ntitle = \"V2\"\n+++\n",
      "docs/v1/_index.md" => "+++\ntitle = \"V1\"\n+++\n",
      "docs/v2/a.md"      => "+++\ntitle = \"A2\"\n+++\n## New Api\n\nx\n",
      "docs/v1/a.md"      => "+++\ntitle = \"A1\"\n+++\n## Old Api\n\nx\n",
    }) do |dir|
      headings = records(dir).compact_map { |r| r["heading"]?.try(&.as_s) }
      headings.should contain("New Api")
      headings.should_not contain("Old Api")
      records(dir).find! { |r| r["heading"]? == "New Api" }["version"].should eq("v2")
    end
  end

  it "skips headings without an id and stops sections at the next h2/h3" do
    html = %(<p>a</p><h2>No id</h2><p>b</p><h3 class="x" id='q&amp;r'>Q <a class="anchor" href="#q" aria-hidden="true">🔗</a></h3><p>c</p><H2 ID="up">Up</H2>d)
    sections = Hwaro::Content::Search.heading_sections(html)
    sections.map { |s| s[:id] }.should eq(["q&r", "up"])
    sections[0][:body].should eq("<p>c</p>")
    sections[1][:body].should eq("d")
    Hwaro::Content::Search.heading_sections("<p>none</p>").should be_empty
  end

  it "ignores headings inside HTML comments" do
    html = %(<!-- <h2 id="ghost">Ghost</h2> --><h2 id="real">Real</h2><p>x</p><!--\n<h3 id="g2">G</h3>\n-->)
    Hwaro::Content::Search.heading_sections(html).map { |s| s[:id] }.should eq(["real"])
  end
end

describe "search facets" do
  it "adds section, lang and taxonomy fields to page and section records" do
    config = SPLIT_CONFIG.sub("split_by_heading = true", "split_by_heading = true\nfacets = [\"section\", \"tags\", \"lang\", \"category\"]") + <<-TOML

      [[taxonomies]]
      name = "tags"

      [[taxonomies]]
      name = "category"
      TOML
    build_site(config, content_files: {
      "docs/_index.md" => "+++\ntitle = \"Docs\"\n+++\n",
      "docs/guide.md"  => "+++\ntitle = \"Guide\"\ntags = [\"a\", \"b\"]\n[taxonomies]\ncategory = [\"howto\"]\n+++\n## H\n\nx\n",
    }) do |dir|
      recs = records(dir).select { |r| r["url"].as_s.starts_with?("/docs/guide/") }
      recs.size.should eq(2)
      recs.each do |r|
        r["section"].should eq("docs")
        r["tags"].as_a.map(&.as_s).should eq(["a", "b"])
        r["category"].as_a.map(&.as_s).should eq(["howto"])
        r["lang"].should eq("en")
      end
      docs = records(dir).find! { |r| r["url"] == "/docs/" }
      docs["category"].as_a.should be_empty
    end
  end

  it "leaves the index byte-identical with every new flag off" do
    off = ""
    build_site(SPLIT_CONFIG.sub("split_by_heading = true", ""), content_files: {"guide.md" => SPLIT_PAGE}) do |dir|
      off = File.read(File.join(dir, "public/search.json"))
    end
    explicit = SPLIT_CONFIG.sub("split_by_heading = true", "split_by_heading = false\nfacets = []\nui = false")
    build_site(explicit, content_files: {"guide.md" => SPLIT_PAGE}) do |dir|
      File.read(File.join(dir, "public/search.json")).should eq(off)
      Dir.exists?(File.join(dir, "public/assets/hwaro-search")).should be_false
    end
  end
end
