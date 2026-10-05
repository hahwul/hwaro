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

  describe ".fenced" do
    it "writes the language and the fence options" do
      Includes.fenced("x\n", "toml", {"title" => "config.toml", "hl_lines" => "3", "lang" => "ignored"})
        .should eq(%(```toml {title="config.toml", hl_lines="3"}\nx\n```\n))
    end

    it "outgrows any backtick run in the code and drops what the option grammar cannot hold" do
      Includes.fenced("a ```` b", "", {"title" => %(a"{b}")}).should eq(%(`````{title="ab"}\na ```` b\n`````\n))
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
  end

  describe ".relative_path" do
    it "normalizes a project-relative path" do
      Includes.relative_path("./examples//a.cr").should eq("examples/a.cr")
    end

    it "refuses absolute paths and traversal" do
      expect_raises(Includes::Error, "absolute") { Includes.relative_path("/etc/passwd") }
      expect_raises(Includes::Error, "escapes") { Includes.relative_path("../secret.txt") }
      expect_raises(Includes::Error, "escapes") { Includes.relative_path("a/%2e%2e/../../x") }
      expect_raises(Includes::Error, "empty") { Includes.relative_path("  ") }
    end
  end

  describe ".read" do
    it "reads a project file, scrubbing NUL and a BOM" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("a.md", "\u{FEFF}x\0y")
          Includes.read("a.md", "public").should eq("x\u{FFFD}y")
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
end
