require "../spec_helper"
require "../../src/services/server/server"

# Serve watch passes whose `.hwaro/serve` tree differed from a cold build of
# the same final source (audit 2026-10). Each example drives the strategy the
# watcher picks for the save and compares against what a cold build writes.

module Hwaro
  module Services
    class Server
      def watch_parity_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def watch_parity_apply_changeset(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end

      def watch_parity_effective_strategy(changeset : ChangeSet, output_dir : String) : Symbol
        effective_strategy(changeset, output_dir)
      end
    end
  end
end

private def watch_parity_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def watch_parity_changeset(
  content : Array(String) = [] of String,
  templates : Array(String) = [] of String,
  static : Array(String) = [] of String,
  content_files : Array(String) = [] of String,
) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: content,
    modified_templates: templates,
    modified_static: static,
    added_files: [] of String,
    removed_files: [] of String,
    config_changed: false,
    modified_content_files: content_files,
  )
end

# Three dated posts whose page template prints the reading-order neighbours,
# the series nav and the related box — every relationship a content edit can
# move on a page it never touched. `templates/unrelated.html` is rendered by
# no page: editing it in the same save takes the watcher down the
# content+template strategy without selecting any post on its own account.
private def write_relations_site
  File.write("config.toml", <<-TOML
    title = "Relations"
    base_url = "https://example.com"

    [[taxonomies]]
    name = "tags"

    [related]
    enabled = true
    taxonomies = ["tags"]

    [series]
    enabled = true
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", <<-HTML
    <html><body><h1>{{ page.title }}</h1>
    {% if page.lower %}<a class="newer" href="{{ page.lower.url }}">{{ page.lower.title }}</a>{% endif %}
    {% if page.higher %}<a class="older" href="{{ page.higher.url }}">{{ page.higher.title }}</a>{% endif %}
    {% for s in page.series_pages %}<a class="series" href="{{ s.url }}">{{ s.title }}</a>{% endfor %}
    {% for r in page.related_posts %}<a class="related" href="{{ r.url }}">{{ r.title }}</a>{% endfor %}
    </body></html>
    HTML
  )
  File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
  File.write("templates/unrelated.html", "<p>unused</p>")
  File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
  File.write("content/posts/a.md", "+++\ntitle = \"Alpha\"\ndate = \"2024-01-01\"\ntags = [\"x\"]\nseries = \"s\"\n+++\na")
  File.write("content/posts/b.md", "+++\ntitle = \"Bravo\"\ndate = \"2024-01-02\"\ntags = [\"y\"]\nseries = \"s\"\n+++\nb")
  File.write("content/posts/c.md", "+++\ntitle = \"Charlie\"\ndate = \"2024-01-03\"\ntags = [\"x\"]\n+++\nc")
end

describe "serve watch parity: content+template saves" do
  # The content+template strategy recomputed the neighbours, series and
  # related posts but threw the affected pages away — only the edited page
  # reached the forced render set — so every other post kept linking the
  # old title (and, after a slug edit, a URL whose file was just deleted).
  it "re-renders the reading-order neighbours of a re-slugged page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_relations_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/posts/a/index.html").should contain(%(href="/posts/b/">Bravo<))

        File.write("content/posts/b.md", "+++\ntitle = \"Beta\"\nslug = \"beta\"\ndate = \"2024-01-02\"\ntags = [\"y\"]\nseries = \"s\"\n+++\nb")
        File.write("templates/unrelated.html", "<p>unused v2</p>")
        builder.run_incremental_then_rerender(["content/posts/b.md"], options).should be_true

        File.exists?("public/posts/b/index.html").should be_false
        {"a", "c"}.each do |slug|
          html = File.read("public/posts/#{slug}/index.html")
          html.should_not contain("/posts/b/")
          html.should contain(%(href="/posts/beta/">Beta<))
        end
      end
    end
  end

  it "re-renders the related box of a page the edit made related" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_relations_site
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/posts/a/index.html").should_not contain(%(class="related" href="/posts/b/"))

        File.write("content/posts/b.md", "+++\ntitle = \"Bravo\"\ndate = \"2024-01-02\"\ntags = [\"x\"]\nseries = \"s\"\n+++\nb")
        File.write("templates/unrelated.html", "<p>unused v2</p>")
        builder.run_incremental_then_rerender(["content/posts/b.md"], options).should be_true

        File.read("public/posts/a/index.html").should contain(%(class="related" href="/posts/b/">Bravo<))
        File.read("public/posts/c/index.html").should contain(%(class="related" href="/posts/b/">Bravo<))
      end
    end
  end

  it "re-renders the other members of a series the edit renamed a page in" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        # Drop the neighbour links so only the series nav can carry the title.
        write_relations_site
        File.write("templates/page.html", <<-HTML
          <html><body>{% for s in page.series_pages %}<a class="series" href="{{ s.url }}">{{ s.title }}</a>{% endfor %}</body></html>
          HTML
        )
        File.write("content/posts/c.md", "+++\ntitle = \"Charlie\"\ndate = \"2024-01-03\"\ntags = [\"x\"]\nseries = \"s\"\n+++\nc")
        builder = Hwaro::Services::Server.new.watch_parity_builder
        options = watch_parity_options
        builder.run(options).should be_true
        File.read("public/posts/a/index.html").should contain(%(class="series" href="/posts/c/">Charlie<))

        File.write("content/posts/c.md", "+++\ntitle = \"Charles\"\ndate = \"2024-01-03\"\ntags = [\"x\"]\nseries = \"s\"\n+++\nc")
        File.write("templates/unrelated.html", "<p>unused v2</p>")
        builder.run_incremental_then_rerender(["content/posts/c.md"], options).should be_true

        File.read("public/posts/a/index.html").should contain(%(class="series" href="/posts/c/">Charles<))
      end
    end
  end
end
