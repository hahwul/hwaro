require "../support/build_helper"

# `include_code` / `include_md` built-ins and `![[note]]` transclusion (#838).

private def include_build(cache : Bool = false, highlight : Bool = false) : Bool
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, cache: cache, highlight: highlight, verbose: false,
  ))
end

# Writes `files` (project-relative) into the current directory.
private def include_project(files : Hash(String, String), wikilinks : Bool = false) : Nil
  config = %(title = "t"\nbase_url = "https://example.com"\n)
  config += "[markdown]\nwikilinks = true\n" if wikilinks
  File.write("config.toml", config)
  {"templates/page.html" => "<nav>{{ toc }}</nav><main>{{ content }}</main>"}.merge(files).each do |path, body|
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end
end

private def in_include_project(files : Hash(String, String), wikilinks : Bool = false, &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      include_project(files, wikilinks)
      yield
    end
  end
end

private APP_CR = <<-CR
  module App
    # #region server
    def run
      # #region inner
      puts "hi"
      # #endregion inner
      serve
    end
    # #endregion server
  end
  CR

private def page(body : String) : String
  "+++\ntitle = \"P\"\ntoc = true\n+++\n#{body}\n"
end

describe "include_code" do
  it "renders a region as a fenced block with fence options and the inferred language" do
    in_include_project({
      "examples/app.cr" => APP_CR,
      "content/p.md"    => page(%({{ include_code(path="examples/app.cr", region="server", lines="2-3", title="app.cr", hl_lines="1") }})),
    }) do
      include_build(highlight: true).should be_true
      html = File.read("public/p/index.html")
      html.should contain(%(<div class="code-filename">app.cr</div>))
      html.should contain(%(class="language-crystal))
      html.should contain(%(<span class="line hl">))
      html.should contain("puts")
      html.should contain("serve")
      html.should_not contain("region")
      html.should_not contain("def run")
    end
  end

  it "dedents, keeps list indentation and leaves calls inside code literal" do
    in_include_project({
      "examples/a.toml" => "    [feeds]\n    enabled = true\n",
      "content/p.md"    => page(<<-MD),
        - item

          {{ include_code(path="examples/a.toml") }}

        `{{ include_code(path="nope") }}`

        ```
        {{ include_code(path="nope") }}
        ```
        MD
    }) do
      include_build.should be_true
      html = File.read("public/p/index.html")
      html.should contain(%(<li>\n<p>item</p>\n<pre><code class="language-toml">[feeds]\nenabled = true\n</code></pre>\n</li>))
      html.scan(%({{ include_code(path=&quot;nope&quot;) }})).size.should eq(2)
    end
  end

  it "fails the build with an error naming the file" do
    {
      %(path="examples/nope.cr")                 => "file not found: examples/nope.cr",
      %(path="examples/app.cr", region="nope")   => "region 'nope' not found",
      %(path="examples/app.cr", lines="40-50")   => %(lines="40-50" is out of range (10 lines)),
      %(path="../outside.cr")                    => "escapes the project root",
      %(path="/etc/hosts")                       => "absolute paths are refused",
      %(path="examples/link.cr")                 => "outside the project root",
      %(path="examples/app.cr", region="server") => nil,
    }.each do |args, error|
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "secret.cr"), "secret")
        in_include_project({"examples/app.cr" => APP_CR, "content/p.md" => page("{{ include_code(#{args}) }}")}) do
          File.symlink(File.join(outside, "secret.cr"), "examples/link.cr")
          if error
            ex = expect_raises(Hwaro::HwaroError) { include_build }
            ex.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
            ex.message.to_s.should contain("in content/p.md: ")
            ex.message.to_s.should contain(error)
          else
            include_build.should be_true
          end
        end
      end
    end
  end

  it "yields to a project's own shortcode of the same name" do
    in_include_project({
      "templates/shortcodes/include_code.html" => "OWN:{{ path }}",
      "content/p.md"                           => page(%({{ include_code(path="nope.cr") }})),
    }) do
      include_build.should be_true
      File.read("public/p/index.html").should contain("OWN:nope.cr")
    end
  end
end

describe "include_md" do
  it "renders in place: shortcodes expand, headings join the TOC, front matter is stripped" do
    in_include_project({
      "shared/install.md" => "+++\ntitle = \"Shared\"\n+++\n## Install\n\n<!-- #region brew -->\n### Homebrew\n\n{{ alert(type=\"info\", body=\"brewed\") }}\n<!-- #endregion brew -->\n",
      "content/p.md"      => page(%(## Intro\n\n{{ include_md(path="shared/install.md") }}\n\n{{ include_md(path="shared/install.md", region="brew") }})),
    }) do
      include_build.should be_true
      html = File.read("public/p/index.html")
      html.should_not contain("Shared")
      html.should_not contain("include_md")
      html.should contain(%(<h2 id="install">Install</h2>))
      html.should contain(%(<h3 id="homebrew">Homebrew</h3>))
      html.should contain(%(<h3 id="homebrew-1">Homebrew</h3>))
      html.should contain("brewed")
      toc = html[/<nav>.*<\/nav>/m]
      toc.should contain("#install")
      toc.should contain("#homebrew-1")
    end
  end

  it "includes nested files and reports a cycle with its chain" do
    in_include_project({
      "shared/a.md"  => %(A {{ include_md(path="shared/b.md") }}),
      "shared/b.md"  => "B",
      "content/p.md" => page(%({{ include_md(path="shared/a.md") }})),
    }) do
      include_build.should be_true
      File.read("public/p/index.html").should contain("<p>A B</p>")

      File.write("shared/b.md", %({{ include_md(path="shared/a.md") }}))
      ex = expect_raises(Hwaro::HwaroError) { include_build }
      ex.message.to_s.should contain("in shared/b.md: include cycle: content/p.md → shared/a.md → shared/b.md → shared/a.md")
    end
  end

  it "stops at the depth limit" do
    files = {"content/p.md" => page(%({{ include_md(path="shared/0.md") }}))}
    10.times { |i| files["shared/#{i}.md"] = %({{ include_md(path="shared/#{i + 1}.md") }}) }
    files["shared/10.md"] = "end"
    in_include_project(files) do
      ex = expect_raises(Hwaro::HwaroError) { include_build }
      ex.message.to_s.should contain("include depth limit (8) exceeded")
    end
  end
end

describe "transclusion" do
  note = "+++\ntitle = \"Note\"\n+++\nIntro.\n\n## Setup\n\nsetup body\n\n### Deep\n\ndeep\n\n## Other\n\nother\n"

  it "transcludes a page and a heading section with [markdown] wikilinks" do
    in_include_project({"content/note.md" => note, "content/p.md" => page("![[note]]\n\n> ![[note#Setup]]\n\n![[missing]]")}, wikilinks: true) do
      include_build.should be_true
      html = File.read("public/p/index.html")
      html.should contain(%(<div class="transclusion" data-source="/note/">\n<p>Intro.</p>))
      html.should contain(%(<blockquote>\n<div class="transclusion" data-source="/note/">\n<h2 id="setup-1">Setup</h2>\n<p>setup body</p>\n<h3 id="deep-1">Deep</h3>\n<p>deep</p>\n</div>\n</blockquote>))
      html.should contain(%(<span class="wikilink wikilink-missing">missing</span>))
    end
  end

  it "stays a link without [markdown] wikilinks" do
    in_include_project({"content/note.md" => note, "content/p.md" => page("![[note]]")}) do
      include_build.should be_true
      File.read("public/p/index.html").should_not contain("transclusion")
    end
  end
end

describe "include dependencies under --cache" do
  it "re-renders the includer when an included file outside content/ changes" do
    in_include_project({"examples/a.cr" => "puts 1\n", "content/p.md" => page(%({{ include_code(path="examples/a.cr") }}))}) do
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("puts 1")
      File.write("examples/a.cr", "puts 2\n")
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("puts 2")
    end
  end

  it "re-renders the transcluding page when the transcluded page changes" do
    in_include_project({"content/note.md" => page("first"), "content/p.md" => page("![[note]]")}, wikilinks: true) do
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("first")
      File.write("content/note.md", page("second"))
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("second")
    end
  end
end
