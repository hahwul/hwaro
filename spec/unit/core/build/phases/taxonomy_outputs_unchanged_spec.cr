require "../../../../spec_helper"
require "../../../../../src/core/build/builder"
require "../../../../../src/content/hooks"

# A warm `--cache` build in which nothing a taxonomy page renders from
# changed keeps the term pages, pagers and term feeds the previous build
# wrote (Builder#taxonomy_outputs_unchanged?) instead of rendering and
# rewriting every one of them. Each example below changes one input those
# files depend on and checks the warm build re-renders them.

private def taxonomy_build
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, cache: true, highlight: false,
  )).should be_true
end

private TAXONOMY_OUTPUTS = %w[public/tags/index.html public/tags/red/index.html public/tags/red/page/2/index.html public/tags/red/rss.xml]

# A file the build keeps still ends with the marker.
private def mark_taxonomy_outputs
  TAXONOMY_OUTPUTS.each { |path| File.write(path, File.read(path) + "<!--kept-->") }
end

private def kept?(path : String) : Bool
  File.read(path).ends_with?("<!--kept-->")
end

private def with_taxonomy_site(term_template : String = "{{ content }}", &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", <<-TOML)
        title = "T"
        base_url = "http://localhost"
        [[taxonomies]]
        name = "tags"
        feed = true
        paginate_by = 1
        TOML
      FileUtils.mkdir_p("content")
      File.write("content/a.md", "+++\ntitle = \"A\"\ndate = \"2024-01-01\"\ntags = [\"red\"]\n+++\na")
      File.write("content/b.md", "+++\ntitle = \"B\"\ndate = \"2024-01-02\"\ntags = [\"red\"]\n+++\nb")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "<p>{{ content }}</p>")
      File.write("templates/taxonomy.html", "<ul>{{ content }}</ul>")
      File.write("templates/taxonomy_term.html", term_template)
      FileUtils.mkdir_p("extra")
      File.write("extra/term.json", %({"label": "first"}))
      taxonomy_build
      TAXONOMY_OUTPUTS.each { |path| File.exists?(path).should be_true }
      mark_taxonomy_outputs
      yield
    end
  end
end

describe "warm --cache builds and the taxonomy pages" do
  it "keeps every taxonomy output when nothing changed" do
    with_taxonomy_site do
      taxonomy_build
      TAXONOMY_OUTPUTS.each { |path| kept?(path).should be_true }
    end
  end

  it "re-renders them when a page they list changes" do
    with_taxonomy_site do
      File.write("content/a.md", "+++\ntitle = \"A2\"\ndate = \"2024-01-01\"\ntags = [\"red\"]\n+++\na")
      taxonomy_build
      TAXONOMY_OUTPUTS.each { |path| kept?(path).should be_false }
      File.read("public/tags/red/page/2/index.html").should contain("A2")
    end
  end

  it "re-renders them when a taxonomy template changes" do
    with_taxonomy_site do
      File.write("templates/taxonomy_term.html", "<div>{{ content }}</div>")
      taxonomy_build
      kept?("public/tags/red/index.html").should be_false
      File.read("public/tags/red/index.html").should start_with("<div>")
    end
  end

  it "re-renders them when an env() value only a taxonomy template reads changes" do
    name = "HWARO_TAXONOMY_REUSE_SPEC"
    ENV[name] = "one"
    begin
      with_taxonomy_site(%({{ env(name="#{name}") }}{{ content }})) do
        File.read("public/tags/red/index.html").should start_with("one")
        ENV[name] = "two"
        taxonomy_build
        File.read("public/tags/red/index.html").should start_with("two")
      end
    ensure
      ENV.delete(name)
    end
  end

  it "re-renders them when a load_data() file only a taxonomy template reads changes" do
    with_taxonomy_site(%({{ load_data(path="extra/term.json").label }}{{ content }})) do
      File.read("public/tags/red/index.html").should start_with("first")
      File.write("extra/term.json", %({"label": "second"}))
      taxonomy_build
      File.read("public/tags/red/index.html").should start_with("second")
    end
  end

  it "writes a deleted taxonomy output again and keeps the rest" do
    with_taxonomy_site do
      File.delete("public/tags/red/page/2/index.html")
      File.delete("public/tags/red/rss.xml")
      taxonomy_build
      File.read("public/tags/red/page/2/index.html").should contain("http://localhost/a/")
      File.read("public/tags/red/rss.xml").should contain("<rss")
      kept?("public/tags/red/index.html").should be_true
    end
  end

  it "writes the term page over a changed static file at its path" do
    with_taxonomy_site do
      FileUtils.mkdir_p("static/tags/red")
      File.write("static/tags/red/index.html", "static bytes")
      taxonomy_build
      File.read("public/tags/red/index.html").should contain("http://localhost/b/")
    end
  end
end
