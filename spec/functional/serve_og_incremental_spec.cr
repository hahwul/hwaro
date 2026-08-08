require "../spec_helper"
require "../../src/services/server/server"

# Regression coverage for the serve-mode auto-OG fixes:
#
# - A8: the serve incremental re-parse (run_incremental) resets page.image
#   from front matter, erasing the auto-OG og:image meta from the edited
#   page's HTML — and the OG file was never regenerated (og_image:generate is
#   a BeforeRender hook the incremental paths never run). The re-parse now
#   preserves the auto-assigned URL and regenerate_seo_surfaces refreshes the
#   image file.
# - A9: `[og.auto_image] lazy_generate = true` under serve skipped generation
#   entirely — page.image stayed nil, so pages advertised NO og:image and the
#   promised on-request generation had no server handler. Pages now get their
#   predicted URL assigned, and OgLazyImageHandler generates the file on
#   first request.
#
# format = "svg" throughout: the SVG renderer needs no system fonts (the PNG
# path degrades to SVG when font init fails), and the emitted SVG embeds the
# page title as text — letting the specs assert content freshness directly.

private def write_og_site(lazy : Bool = false)
  File.write("config.toml", <<-TOML
    title = "OG Site"
    base_url = "https://example.com"

    [og.auto_image]
    enabled = true
    format = "svg"
    lazy_generate = #{lazy}
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><head>{{ og_all_tags }}</head><body>{{ content }}</body></html>")
  File.write("content/posts/hello.md", "---\ntitle: First Title\n---\nhello body")
end

private def og_builder : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder
end

private def og_options(preserve : Bool = false) : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options.preserve_output = preserve
  options
end

private class OgSpecTerminal
  include HTTP::Handler

  property called : Bool = false

  def call(context)
    @called = true
    context.response.status_code = 404
  end
end

private def og_request(handler : HTTP::Handler, path : String) : {HTTP::Server::Context, OgSpecTerminal}
  terminal = OgSpecTerminal.new
  handler.next = terminal
  request = HTTP::Request.new("GET", path)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  handler.call(context)
  response.close
  {context, terminal}
end

describe "serve auto-OG incremental behavior (A8)" do
  it "keeps og:image meta and refreshes the OG file after an incremental edit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_og_site
        builder = og_builder
        builder.run(og_options).should be_true

        html = File.read("public/posts/hello/index.html")
        html.should contain(%(property="og:image"))
        html.should contain("/og-images/posts-hello.svg")
        File.read("public/og-images/posts-hello.svg").should contain("First Title")

        # Incremental edit: new title, still no front-matter image.
        File.write("content/posts/hello.md", "---\ntitle: Second Title\n---\nhello body edited")
        builder.run_incremental(["content/posts/hello.md"], og_options(preserve: true)).should be_true

        html = File.read("public/posts/hello/index.html")
        html.should contain(%(property="og:image"))
        html.should contain("/og-images/posts-hello.svg")
        File.read("public/og-images/posts-hello.svg").should contain("Second Title")
      end
    end
  end

  it "lets a newly added front-matter image win over the auto-assigned one" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_og_site
        builder = og_builder
        builder.run(og_options).should be_true

        File.write("content/posts/hello.md", "---\ntitle: First Title\nimage: /custom.png\n---\nhello body")
        builder.run_incremental(["content/posts/hello.md"], og_options(preserve: true)).should be_true

        html = File.read("public/posts/hello/index.html")
        html.should contain("https://example.com/custom.png")
        html.should_not contain("/og-images/posts-hello.svg")
      end
    end
  end
end

describe "serve lazy OG generation (A9)" do
  it "advertises the predicted og:image URL without generating the file" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_og_site(lazy: true)
        og_builder.run(og_options).should be_true

        html = File.read("public/posts/hello/index.html")
        html.should contain(%(property="og:image"))
        html.should contain("/og-images/posts-hello.svg")

        # Lazy: nothing rendered up front.
        File.exists?("public/og-images/posts-hello.svg").should be_false
      end
    end
  end

  it "generates the OG image on first request and serves from disk afterwards" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_og_site(lazy: true)
        builder = og_builder
        builder.run(og_options).should be_true
        File.exists?("public/og-images/posts-hello.svg").should be_false

        handler = Hwaro::Services::OgLazyImageHandler.new(builder, "public")

        # First request: generated on demand, then handed to the next
        # handler (the static file handler in the real chain).
        _, terminal = og_request(handler, "/og-images/posts-hello.svg")
        terminal.called.should be_true
        File.exists?("public/og-images/posts-hello.svg").should be_true
        File.read("public/og-images/posts-hello.svg").should contain("First Title")

        # Second request: served from disk without regeneration. Backdate the
        # file — a rewrite would bump its mtime.
        stamp = Time.utc - 5.minutes
        File.touch("public/og-images/posts-hello.svg", stamp)
        og_request(handler, "/og-images/posts-hello.svg")
        File.info("public/og-images/posts-hello.svg").modification_time.should be_close(stamp, 2.seconds)
      end
    end
  end

  it "passes unrelated requests through untouched" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_og_site(lazy: true)
        builder = og_builder
        builder.run(og_options).should be_true

        handler = Hwaro::Services::OgLazyImageHandler.new(builder, "public")
        _, terminal = og_request(handler, "/posts/hello/")
        terminal.called.should be_true
        Dir.exists?("public/og-images").should be_false
      end
    end
  end
end
