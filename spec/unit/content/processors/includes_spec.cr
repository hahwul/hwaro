require "../../../spec_helper"

private alias Includes = Hwaro::Content::Processors::Includes

private CODE = <<-CR
  require "http"

  module App
    // #region server
    def run
      # #region inner
      puts "hi"
      # #endregion inner
    end
    // #endregion server
  end
  CR

describe Hwaro::Content::Processors::Includes do
  describe ".region" do
    it "selects the region and strips the nested markers" do
      Includes.region(CODE, "server", markdown: false).should eq("  def run\n    puts \"hi\"\n  end\n")
    end

    it "reads markers after every comment leader" do
      %w[// # -- ; /*].each do |leader|
        text = "a\n#{leader} #region r\nb\n#{leader} #endregion r\nc\n"
        Includes.region(text, "r", markdown: false).should eq("b\n")
      end
      Includes.region("<!-- #region r -->\nb\n<!-- #endregion r -->\n", "r", markdown: false).should eq("b\n")
      Includes.region("#region r\nb\n#endregion\n", "r", markdown: false).should eq("b\n")
    end

    it "takes only the HTML-comment form in Markdown" do
      md = "<!-- #region brew -->\n```sh\n# #region x\nbrew\n```\n<!-- #endregion brew -->\n"
      Includes.region(md, "brew", markdown: true).should eq("```sh\n# #region x\nbrew\n```\n")
    end

    it "raises for a missing or unclosed region" do
      expect_raises(Includes::Error, "region 'nope' not found") { Includes.region(CODE, "nope", markdown: false) }
      expect_raises(Includes::Error, "region 'r' is never closed") { Includes.region("# #region r\nx\n", "r", markdown: false) }
    end
  end

  describe ".lines" do
    it "selects 1-based inclusive lines, relative to a region" do
      region = Includes.region(CODE, "server", markdown: false)
      Includes.lines(region, "2-3").should eq("    puts \"hi\"\n  end\n")
      Includes.lines(region, "1").should eq("  def run\n")
    end

    it "raises for a range outside the text or a malformed spec" do
      expect_raises(Includes::Error, "out of range (3 lines)") { Includes.lines("a\nb\nc\n", "2-9") }
      expect_raises(Includes::Error, "out of range") { Includes.lines("a\n", "0") }
      expect_raises(Includes::Error, "out of range") { Includes.lines("a\nb\n", "2-1") }
      expect_raises(Includes::Error, "not a range") { Includes.lines("a\n", "x") }
    end
  end

  it ".dedent removes the common indentation, ignoring blank lines" do
    Includes.dedent("    a\n\n      b\n    c\n").should eq("a\n\n  b\nc\n")
    Includes.dedent("a\n  b\n").should eq("a\n  b\n")
  end

  it ".language_for maps the extension like the highlighter" do
    Includes.language_for("examples/config.toml").should eq("toml")
    Includes.language_for("src/app.cr").should eq("crystal")
    Includes.language_for("a/.bashrc").should eq("bash")
    Includes.language_for("page.php5").should eq("php")
    Includes.language_for("notes.zzz-unknown").should eq("")
  end

  it ".language_for matches capitalised file names against the lowercase table" do
    Includes.language_for("src/Makefile").should eq("makefile")
    Includes.language_for("Dockerfile").should eq("docker")
    Includes.language_for("Dockerfile.dev").should eq("docker")
    Includes.language_for("Gemfile").should eq("ruby")
    Includes.language_for("Rakefile").should eq("ruby")
    # The whole-name entry beats the generic `*.txt` one.
    Includes.language_for("CMakeLists.txt").should eq("cmake")
    Includes.language_for("notes.txt").should eq("plaintext")
  end

  describe ".fenced" do
    it "writes the language and the fence options" do
      Includes.fenced("x\n", "toml", {"title" => "config.toml", "hl_lines" => "3", "lang" => "ignored"})
        .should eq(%(```toml {title="config.toml", hl_lines="3"}\nx\n```\n))
    end

    it "outgrows any backtick run in the code and drops what the option grammar cannot hold" do
      Includes.fenced("a ```` b", "", {"title" => %(a"{b}")}).should eq(%(`````{title="ab"}\na ```` b\n`````\n))
    end

    it "drops backticks from option values, which a backtick fence's info string cannot hold" do
      Includes.fenced("x\n", "rust", {"title" => "`main.rs`"}).should eq(%(```rust {title="main.rs"}\nx\n```\n))
    end
  end

  describe ".heading_ids" do
    it "reads an id block but not an escaped one, which is heading text" do
      Includes.heading_ids("## Title {#t}\n").should eq({"title" => "t"})
      Includes.heading_ids("## Title \\{#t}\n").should eq({Hwaro::Utils::TextUtils.slugify("Title {#t}") => nil})
      Includes.heading_ids("## Title \\\\{#t}\n").should eq({Hwaro::Utils::TextUtils.slugify("Title \\") => "t"})
    end

    it "keeps the first heading of a slug and skips fenced ones" do
      markdown = "```\n## A {#fenced}\n```\n## A\n## A {#late}\n## B {#b .wide}\n"
      Includes.heading_ids(markdown).should eq({"a" => nil, "b" => "b"})
    end

    it "reads a heading holding a long whitespace run" do
      Includes.heading_ids("## Early\n\n## wide#{" " * 3000}gap #\n").should eq({"early" => nil, "wide-gap" => nil})
    end
  end

  describe "ATX_RE" do
    # The backtracking form ATX_RE replaced; it gives up (match limit) on a
    # long whitespace run, so it is compared on short lines only.
    old_atx = /\A {0,3}(\#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*\r?\n?\z/

    it "captures what the backtracking form captured" do
      rng = Random.new(20261111)
      pieces = [" ", "  ", "\t", "#", "##", "\\#", "a", "b c", "{#id}", "{#x .c}", "}", "{", "\r", ".", "\\", "#{" " * 5}"]
      endings = ["", "\n", "\r\n", "\r", " \n", "\t\r\n", " #\n", " ##  \r\n"]
      4000.times do
        line = String.build do |io|
          io << " " * rng.rand(0..4) << "#" * rng.rand(0..7)
          rng.rand(0..8).times { io << pieces.sample(rng) }
          io << endings.sample(rng)
        end
        want = old_atx.match(line)
        got = Includes::ATX_RE.match(line)
        {got.nil?, got.try(&.[1]?), got.try(&.[2]?)}.should eq({want.nil?, want.try(&.[1]?), want.try(&.[2]?)}), line.inspect
      end
    end

    it "reads a long whitespace run without giving up" do
      Includes::ATX_RE.match("## wide#{" " * 20000}gap\n").try(&.[2]?).should eq("wide#{" " * 20000}gap")
      Includes::ATX_RE.match("## wide#{" \t" * 20000}##  \n").try(&.[2]?).should eq("wide")
      Includes::ATX_RE.match("## #{"# " * 20000}x\n").try(&.[2]?).should eq("#{"# " * 20000}x")
    end
  end

  describe ".heading_section" do
    md = "intro\n## Setup {#s}\nbody\n```\n# not a heading\n```\n### Deep\nd\n## Next\nn\n"

    it "runs to the next heading of the same or a higher level" do
      Includes.heading_section(md, "Setup").should eq("## Setup {#s}\nbody\n```\n# not a heading\n```\n### Deep\nd\n")
      Includes.heading_section(md, "deep").should eq("### Deep\nd\n")
    end

    it "is nil for a heading the page does not have" do
      Includes.heading_section(md, "not a heading").should be_nil
    end

    it "reads setext headings as sections and as terminators" do
      note = "## **Bold** Title\nBOLD\n\nSetext Head\n-----------\nSETEXT\n\nTop\n===\nTOP\n"
      Includes.heading_section(note, "Bold Title").should eq("## **Bold** Title\nBOLD\n\n")
      Includes.heading_section(note, "Setext Head").should eq("Setext Head\n-----------\nSETEXT\n\n")
      Includes.heading_section(note, "Top").should eq("Top\n===\nTOP\n")
      # Several paragraph lines before the underline are one heading.
      Includes.heading_section("a\nb\n---\nx\n", "a b").should eq("a\nb\n---\nx\n")
    end

    it "does not take a thematic break after a list item, quote or blank line for a setext underline" do
      note = "## S\n- item\n---\nafter\n\n> quote\n---\nmore\n\ntext\n\n---\nlast\n"
      Includes.heading_section(note, "S").should eq(note)
    end

    it "matches a heading by the text it renders" do
      note = "## See [Foo](https://x.y) bar\nLINK\n## A ![pic](p.png) and [ref][r] <b>b</b>\nIMG\n## Tom &amp; Jerry\nAMP\n\n[r]: /r\n"
      Includes.heading_section(note, "See Foo bar").should eq("## See [Foo](https://x.y) bar\nLINK\n")
      Includes.heading_section(note, "A pic and ref b").should eq("## A ![pic](p.png) and [ref][r] <b>b</b>\nIMG\n")
      Includes.heading_section(note, "Tom & Jerry").should eq("## Tom &amp; Jerry\nAMP\n\n[r]: /r\n")
    end

    it "reads the text of a code span as written, even when it looks like a tag" do
      note = "## `<div>` tag\nCODE\n## Next\nN\n"
      Includes.heading_section(note, "<div> tag").should eq("## `<div>` tag\nCODE\n")
      Includes.heading_section(note, "div tag").should eq("## `<div>` tag\nCODE\n")
    end

    it "takes neither a table nor a reference definition for a setext heading's text" do
      table = "## T\nA\n\n| a | b |\n|---|---|\n| 1 | 2 |\n---\nafter\n\n## Next\nZ\n"
      Includes.heading_section(table, "T").should eq("## T\nA\n\n| a | b |\n|---|---|\n| 1 | 2 |\n---\nafter\n\n")
      ref = "## T\n\n[ref]: /x\n---\nbody\n\n## Next\nZ\n"
      Includes.heading_section(ref, "T").should eq("## T\n\n[ref]: /x\n---\nbody\n\n")
    end
  end

  describe ".relative_path" do
    it "normalizes a project-relative path" do
      Includes.relative_path("./examples//a.cr").should eq("examples/a.cr")
      # Decoding only decides the refusal; the literal name is read.
      Includes.relative_path("examples/a%20b.txt").should eq("examples/a%20b.txt")
    end

    it "refuses absolute paths and traversal" do
      expect_raises(Includes::Error, "absolute") { Includes.relative_path("/etc/passwd") }
      expect_raises(Includes::Error, "escapes") { Includes.relative_path("../secret.txt") }
      expect_raises(Includes::Error, "escapes") { Includes.relative_path("a/%2e%2e/../../x") }
      expect_raises(Includes::Error, "escapes") { Includes.relative_path("%2e%2e/x") }
      expect_raises(Includes::Error, "empty") { Includes.relative_path("  ") }
    end
  end

  describe ".read" do
    it "reads a project file, scrubbing NUL and a BOM" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("a.md", "\u{FEFF}x\0y")
          Includes.clean(Includes.read("a.md", "public")).should eq("x\u{FFFD}y")
        end
      end
    end

    it "refuses a symlink out of the project, the output dir and .hwaro" do
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "secret.txt"), "s")
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            File.symlink(File.join(outside, "secret.txt"), "link.txt")
            expect_raises(Includes::Error, "outside the project root") { Includes.read("link.txt", "public") }
            FileUtils.mkdir_p("public")
            File.write("public/x.html", "x")
            expect_raises(Includes::Error, "build output") { Includes.read("public/x.html", "public") }
            FileUtils.mkdir_p(".hwaro/serve")
            File.write(".hwaro/serve/x.html", "x")
            expect_raises(Includes::Error, "build output") { Includes.read(".hwaro/serve/x.html", nil) }
          end
        end
      end
    end

    it "names a missing file" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          expect_raises(Includes::MissingFile, "file not found: nope.cr") { Includes.read("nope.cr", nil) }
          # A refusal is not a missing file, even when nothing is there yet.
          ex = expect_raises(Includes::Error, "build output") { Includes.read(".hwaro/serve/nope.html", nil) }
          ex.should_not be_a(Includes::MissingFile)
        end
      end
    end
  end
  it ".read refuses files under .git/, which content must never publish" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        Dir.mkdir(".git")
        File.write(".git/config", "MARKER")
        File.write("ok.txt", "fine")
        Includes.read("ok.txt", nil).should eq("fine")
        expect_raises(Includes::Error, /\.git/) { Includes.read(".git/config", nil) }
        expect_raises(Includes::Error, /\.git/) { Includes.read(".GIT/config", nil) } if File.exists?(".GIT/config")
      end
    end
  end

  it ".read refuses dotenv files but allows the committed samples" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        Dir.mkdir("app")
        {".env", ".env.local", "app/.env.production", ".env.example", ".env.sample", "env.txt"}.each { |name| File.write(name, "KEY=#{name}") }
        {".env", ".env.local", "app/.env.production"}.each do |name|
          expect_raises(Includes::Error, /dotenv/) { Includes.read(name, nil) }
        end
        {".env.example", ".env.sample", "env.txt"}.each do |name|
          Includes.read(name, nil).should eq("KEY=#{name}")
        end
      end
    end
  end
end
