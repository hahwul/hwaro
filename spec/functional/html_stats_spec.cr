require "../support/build_helper"

# `[build] write_stats`: hwaro_stats.json at the project root lists the
# tags/classes/ids of every rendered HTML page, for Tailwind's `@source`.

private STATS_CONFIG = <<-TOML
  title = "Stats"
  base_url = "http://localhost"
  taxonomies = [{ name = "tags" }]

  [build]
  write_stats = true
  TOML

private STATS_TEMPLATES = {
  "page.html"          => %(<article class="page-{{ page.extra.kind | default(value='x') }}">{{ content }}</article>),
  "section.html"       => %(<section class="sec" id="s-{{ section.title | lower }}">{{ content }}</section>),
  "taxonomy.html"      => %(<ul class="tax-list"></ul>),
  "taxonomy_term.html" => %(<ul class="term-list"></ul>),
  "404.html"           => %(<div class="not-found"></div>),
}

private def stats_classes : Array(String)
  JSON.parse(File.read("hwaro_stats.json"))["htmlElements"]["classes"].as_a.map(&.as_s)
end

private def stats_build(cache : Bool = false)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, cache: cache, highlight: false,
  )).should be_true
end

describe "[build] write_stats" do
  it "collects pages, sections, taxonomy pages and the 404 page" do
    build_site(
      STATS_CONFIG,
      content_files: {
        "_index.md"      => "+++\ntitle = \"Home\"\n+++\n<b class=\"from-md\">x</b>",
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n+++\n",
        "blog/a.md"      => "+++\ntitle = \"A\"\ntags = [\"t\"]\n[extra]\nkind = \"a\"\n+++\na",
      },
      template_files: STATS_TEMPLATES,
    ) do
      classes = stats_classes
      %w[page-a sec tax-list term-list not-found from-md].each { |cls| classes.should contain(cls) }
      JSON.parse(File.read("hwaro_stats.json"))["htmlElements"]["ids"].as_a.map(&.as_s).should eq(["s-blog", "s-home"])
      # Written at the project root, never into the deployable output.
      File.exists?("public/hwaro_stats.json").should be_false
    end
  end

  it "writes nothing when off" do
    build_site(BASIC_CONFIG, content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\na"}) do
      File.exists?("hwaro_stats.json").should be_false
    end
  end

  it "keeps the classes of cached pages on a warm --cache build" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", STATS_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        STATS_TEMPLATES.each { |name, body| File.write(File.join("templates", name), body) }
        File.write("content/a.md", "+++\ntitle = \"A\"\n[extra]\nkind = \"a\"\n+++\na")
        File.write("content/b.md", "+++\ntitle = \"B\"\n[extra]\nkind = \"b\"\n+++\nb")
        stats_build(cache: true)
        stats_classes.should contain("page-b")

        File.write("content/a.md", "+++\ntitle = \"A\"\n[extra]\nkind = \"a2\"\n+++\na")
        stats_build(cache: true)

        classes = stats_classes
        classes.should contain("page-a2")
        # b.md was served from the cache, not rendered, and still counts.
        classes.should contain("page-b")
      end
    end
  end

  # A partial build extends the previous file; with that file gone (a CI
  # that restores the cache but not the project root) or corrupt, a warm
  # build listed only the pages it rendered, and Tailwind purged the rest.
  it "renders every page on a warm --cache build when the stats file is missing or malformed" do
    ["", %({"htmlElements": 5}), "{not json"].each do |replacement|
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", STATS_CONFIG)
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          STATS_TEMPLATES.each { |name, body| File.write(File.join("templates", name), body) }
          File.write("content/a.md", "+++\ntitle = \"A\"\n[extra]\nkind = \"a\"\n+++\na")
          File.write("content/b.md", "+++\ntitle = \"B\"\n[extra]\nkind = \"b\"\n+++\nb")
          stats_build(cache: true)

          replacement.empty? ? File.delete("hwaro_stats.json") : File.write("hwaro_stats.json", replacement)
          stats_build(cache: true)

          stats_classes.should contain("page-a")
          stats_classes.should contain("page-b")
        end
      end
    end
  end
end
