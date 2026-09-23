require "../spec_helper"
require "../../src/services/server/server"

# Serve rebuilds whose output differed from a cold build of the same final
# source: the incremental strategies skipped a file the cold build rewrites.

private def parity_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = true
  options
end

private def write_sidebar_site
  File.write("config.toml", <<-TOML
    title = "Sidebar"
    base_url = "https://example.com"
    TOML
  )
  FileUtils.mkdir_p("content/guide")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
  # The 404 page prints the site's pages, like a docs sidebar or a nav.
  File.write("templates/404.html", "<html><body>{% for p in site.pages %}[{{ p.title }}]{% endfor %}</body></html>")
  File.write("content/guide/intro.md", "---\ntitle: Old Intro\n---\nbody")
end

describe "serve rebuild parity" do
  # The 404 page renders site-wide listings but was never in any incremental
  # render set, so it kept printing pre-edit titles until a full rebuild.
  it "regenerates 404.html on an incremental content rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_sidebar_site
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true
        File.read("public/404.html").should contain("[Old Intro]")

        File.write("content/guide/intro.md", "---\ntitle: New Intro\n---\nbody")
        builder.run_incremental(["content/guide/intro.md"], options).should be_true

        File.read("public/404.html").should contain("[New Intro]")
      end
    end
  end

  it "regenerates 404.html when content and an unrelated template change together" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_sidebar_site
        builder = Hwaro::Services::Server.new.@builder
        options = parity_options
        builder.run(options).should be_true

        File.write("content/guide/intro.md", "---\ntitle: New Intro\n---\nbody")
        File.write("templates/page.html", "<html><body><h1>{{ page.title }}</h1></body></html>")
        builder.run_incremental_then_rerender(["content/guide/intro.md"], options).should be_true

        File.read("public/404.html").should contain("[New Intro]")
      end
    end
  end
end
