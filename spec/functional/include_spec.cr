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
      # A future mtime is never safely old, whatever the clock does.
      tick = Time.utc + 1.hour
      File.touch("examples/a.cr", tick)
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("puts 1")
      # Same size and, pinned, the same mtime: a rewrite inside the
      # timestamp tick the warm build's stamp was taken in (#857).
      File.write("examples/a.cr", "puts 2\n")
      File.touch("examples/a.cr", tick)
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("puts 2")
    end
  end

  it "re-renders the transcluding page when the transcluded page changes" do
    in_include_project({"content/note.md" => page("first"), "content/p.md" => page("![[note]]")}, wikilinks: true) do
      tick = Time.utc + 1.hour
      File.touch("content/note.md", tick)
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("first")
      File.write("content/note.md", page("second"))
      File.touch("content/note.md", tick)
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("second")
    end
  end
end

describe "include dependencies under --cache: what the included text brings in" do
  it "re-renders the includer when a link target only the included file names moves" do
    in_include_project({
      "examples/s.md" => "See [T](@/t.md) and [[t]].",
      "content/t.md"  => page("t"),
      "content/p.md"  => page(%({{ include_md(path="examples/s.md") }})),
    }, wikilinks: true) do
      include_build(cache: true).should be_true
      include_build(cache: true).should be_true
      File.write("content/t.md", "+++\ntitle = \"T\"\nslug = \"tee\"\n+++\nt\n")
      include_build(cache: true).should be_true
      html = File.read("public/p/index.html")
      html.scan(%(href="/tee/")).size.should eq(2)
      html.should_not contain(%(href="/t/"))
    end
  end

  it "re-renders the includer when a shortcode only the included file calls changes" do
    in_include_project({
      "templates/shortcodes/note.html" => "N1:{{ body }}",
      "examples/s.md"                  => %({{ note(body="x") }}),
      "content/p.md"                   => page(%({{ include_md(path="examples/s.md") }})),
    }) do
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("N1:x")
      File.write("templates/shortcodes/note.html", "N2:{{ body }}")
      include_build(cache: true).should be_true
      File.read("public/p/index.html").should contain("N2:x")
    end
  end
end

describe "include and transclusion edge cases" do
  other = "+++\ntitle = \"Other\"\n+++\nOTHER BODY\n"

  it "never transcludes an embed that included text brings in (one pass)" do
    in_include_project({
      "content/other.md"  => other,
      "examples/notes.md" => "```md\n![[other]]\n```\n",
      "content/p.md"      => page(%(![[other]]\n\n{{ include_code(path="examples/notes.md") }}\n\n{{ include_md(path="examples/notes.md") }})),
    }, wikilinks: true) do
      include_build.should be_true
      html = File.read("public/p/index.html")
      html.scan("OTHER BODY").size.should eq(1)
      html.scan("![[other]]").size.should eq(2)
    end
  end

  it "keeps an include on a list-marker line inside its item" do
    in_include_project({
      "examples/a.cr" => "puts 1\nputs 2\n",
      "examples/s.md" => "one\n\ntwo\n",
      "content/p.md"  => page(%(- {{ include_code(path="examples/a.cr") }}\n- second\n\n1. {{ include_md(path="examples/s.md") }}\n2. next)),
    }) do
      include_build.should be_true
      html = File.read("public/p/index.html")
      html.should contain(%(<ul>\n<li>\n<pre><code class="language-crystal">puts 1\nputs 2\n</code></pre>\n</li>\n<li>second</li>\n</ul>))
      html.should contain(%(<ol>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n<li>\n<p>next</p>\n</li>\n</ol>))
    end
  end

  it "leaves an include in a fence inside a block shortcode body literal" do
    in_include_project({
      "templates/shortcodes/box.html" => "<div class=\"box\">{{ body }}</div>",
      "content/p.md"                  => page(%({% box() %}\n```\n{{ include_code(path="examples/nope.cr") }}\n```\n{% end %})),
    }) do
      include_build.should be_true
      File.read("public/p/index.html").should contain(%(```\n{{ include_code(path="examples/nope.cr") }}\n```))
    end
  end

  it "leaves calls in a {% raw %} region literal" do
    in_include_project({"content/p.md" => page(%({% raw %}{{ include_code(path="nope") }}{% endraw %}))}) do
      include_build.should be_true
      File.read("public/p/index.html").should contain(%({{ include_code(path=&quot;nope&quot;) }}))
    end
  end

  it "does not transclude inside display math or a raw HTML block" do
    in_include_project({
      "config.toml"      => %(title = "t"\nbase_url = "https://example.com"\n[markdown]\nwikilinks = true\nmath = true\n),
      "content/other.md" => other,
      "content/p.md"     => page("$$\n![[other]]\n$$\n\n<div>\n![[other]]\n</div>"),
    }) do
      include_build.should be_true
      File.read("public/p/index.html").should_not contain("OTHER BODY")
    end
  end

  it "lets a note embed its own other heading, and still reports a real section cycle" do
    in_include_project({"content/p.md" => page("# A\n\n![[p#B]]\n\n# B\n\nbee")}, wikilinks: true) do
      include_build.should be_true
      File.read("public/p/index.html").should contain(%(<div class="transclusion" data-source="/p/">))

      File.write("content/p.md", page("# A\n\n![[p#B]]\n\n# B\n\n![[p#A]]"))
      ex = expect_raises(Hwaro::HwaroError) { include_build }
      ex.message.to_s.should contain("include cycle: content/p.md → content/p.md#b → content/p.md#a → content/p.md#b")
    end
  end

  it "reports an include error once, not again from the automatic summary" do
    in_include_project({
      "config.toml"  => %(title = "t"\nbase_url = "https://example.com"\n[content]\nsummary_length = 20\n),
      "content/p.md" => page(%({{ include_md(path="nope.md") }})),
    }) do
      log = with_captured_log { expect_raises(Hwaro::HwaroError, "file not found: nope.md") { include_build } }
      log.should_not contain("Automatic summary skipped")
      log.should_not contain("Summary render failed")
    end
  end

  it "reads a percent sign in path= literally" do
    in_include_project({
      "examples/a%20b.txt" => "percent\n",
      "examples/a b.txt"   => "space\n",
      "content/p.md"       => page(%({{ include_code(path="examples/a%20b.txt") }})),
    }) do
      include_build.should be_true
      html = File.read("public/p/index.html")
      html.should contain("percent")
      html.should_not contain("space")
    end
  end
end

describe "transclusion and the Markdown after it" do
  a = "+++\ntitle = \"A\"\n+++\nALPHA\n"
  body = "intro\n![[a]]\nNext **bold** line.\n## Heading after\n\n- item\n  ![[a]]\n  more in item\n"

  {false, true}.each do |safe|
    it "parses the line after an embed as Markdown (safe = #{safe})" do
      in_include_project({
        "config.toml"  => %(title = "t"\nbase_url = "https://example.com"\n[markdown]\nwikilinks = true\nsafe = #{safe}\n),
        "content/a.md" => a,
        "content/p.md" => page(body),
      }) do
        include_build.should be_true
        html = File.read("public/p/index.html")
        html.should contain("<strong>bold</strong>")
        html.should contain(%(<h2 id="heading-after">Heading after</h2>))
        html.should contain("more in item")
        html.should_not contain("Next **bold**")
        html.scan("ALPHA").size.should eq(2)
      end
    end
  end

  it "transcludes after a display-math block closed at the end of a line" do
    in_include_project({
      "config.toml"  => %(title = "t"\nbase_url = "https://example.com"\n[markdown]\nwikilinks = true\nmath = true\n),
      "content/a.md" => a,
      "content/p.md" => page("$$\\begin{aligned}\na &= b\n\\end{aligned}$$\n\n![[a]]\n\n$$ c\nd $$\n\n![[a]]"),
    }) do
      include_build.should be_true
      File.read("public/p/index.html").scan("ALPHA").size.should eq(2)
    end
  end
end

describe "the block form of include_*" do
  it "is still a missing shortcode" do
    in_include_project({"content/p.md" => page(%({% include_md(path="examples/a.txt") %}\nbody\n{% end %}))}) do
      log = with_captured_log { include_build.should be_true }
      log.should contain("shortcodes/include_md")
      File.read("public/p/index.html").should contain("<!-- hwaro: missing shortcode 'include_md' -->")
    end
  end
end
