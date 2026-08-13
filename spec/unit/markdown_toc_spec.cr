require "../spec_helper"

describe Hwaro::Content::Processors::Markdown do
  describe "TOC generation" do
    it "generates correct TOC structure" do
      content = <<-MARKDOWN
        # Header 1
        ## Header 1.1
        ### Header 1.1.1
        ## Header 1.2
        # Header 2
        MARKDOWN

      _, toc = Hwaro::Content::Processors::Markdown.new.render(content)

      toc.size.should eq(2)
      toc[0].level.should eq(1)
      toc[0].title.should eq("Header 1")

      toc[0].children.size.should eq(2)
      toc[0].children[0].level.should eq(2)
      toc[0].children[0].title.should eq("Header 1.1")

      toc[0].children[0].children.size.should eq(1)
      toc[0].children[0].children[0].level.should eq(3)
      toc[0].children[0].children[0].title.should eq("Header 1.1.1")

      toc[1].level.should eq(1)
      toc[1].title.should eq("Header 2")
    end

    it "ignores non-header tags" do
      content = <<-MARKDOWN
        <hr>
        <div class="h1">Not a header</div>

        # Header
        MARKDOWN

      _, toc = Hwaro::Content::Processors::Markdown.new.render(content)
      toc.size.should eq(1)
      toc[0].title.should eq("Header")
    end

    it "handles header levels correctly with char check optimization" do
      content = <<-MARKDOWN
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        MARKDOWN

      _, toc = Hwaro::Content::Processors::Markdown.new.render(content)

      root = toc[0]
      root.level.should eq(1)
      root.children[0].level.should eq(2)
      root.children[0].children[0].level.should eq(3)
      root.children[0].children[0].children[0].level.should eq(4)
      root.children[0].children[0].children[0].children[0].level.should eq(5)
      root.children[0].children[0].children[0].children[0].children[0].level.should eq(6)
    end

    it "slugifies entity-escaped heading text from the decoded characters" do
      html, toc = Hwaro::Content::Processors::Markdown.new.render("## Tom & Jerry <3\n\ntext")

      toc[0].id.should eq("tom-jerry-3")
      html.should contain(%(<h2 id="tom-jerry-3">))
      # The TOC title keeps the escaped form — consumers interpolate it
      # into HTML verbatim.
      toc[0].title.should eq("Tom &amp; Jerry &lt;3")
    end

    it "does not mistake data-id for the heading's own id" do
      html, toc = Hwaro::Content::Processors::Markdown.new.render(
        %(<h2 data-id="tracker">Real Title</h2>\n\ntext)
      )

      toc[0].id.should eq("real-title")
      html.should contain(%(data-id="tracker"))
      html.should contain(%(id="real-title"))
    end

    it "keeps a quoted '>' in heading attributes out of the TOC title" do
      html, toc = Hwaro::Content::Processors::Markdown.new.render(
        %(<h2 title="a > b">Quoted</h2>\n\ntext)
      )

      toc[0].title.should eq("Quoted")
      toc[0].id.should eq("quoted")
      html.should contain(%(title="a > b"))
    end

    it "keeps a quoted '>' in inline HTML out of the TOC title" do
      _, toc = Hwaro::Content::Processors::Markdown.new.render(
        %(## Hello <img alt="Home > Docs" src="/x.png"> World\n\ntext)
      )

      toc[0].title.should eq("Hello  World")
    end

    # The renamed id is spliced into a `String#sub` REPLACEMENT, where Crystal
    # expands `\0`-`\9` and `\k<name>` unless told not to — `\k<x>` used to
    # raise IndexError and abort the whole render.
    it "does not expand backreferences when renaming a duplicate explicit id" do
      html, toc = Hwaro::Content::Processors::Markdown.new.render(
        %(<h2 id="a\\k<x>">One</h2>\n\n<h2 id="a\\k<x>">Two</h2>\n\ntext)
      )

      toc.size.should eq(2)
      html.should contain(%(id="a\\k<x>-1"))
    end

    it "ignores headings inside HTML comments" do
      content = <<-MARKDOWN
        ## Kept

        <!--
        <h2>Old section title</h2>
        -->

        text
        MARKDOWN

      html, toc = Hwaro::Content::Processors::Markdown.new.render(content)

      toc.size.should eq(1)
      toc[0].title.should eq("Kept")
      # The comment body is left byte-for-byte alone: no injected id.
      html.should contain("<h2>Old section title</h2>")
      html.should_not contain(%(id="old-section-title"))
    end

    it "does not inject anchor links into headings inside HTML comments" do
      content = <<-MARKDOWN
        ## Kept

        <!--
        <h2 id="old">Old</h2>
        -->

        text
        MARKDOWN

      html, _ = Hwaro::Content::Processors::Markdown.new.render_with_anchors(
        content, anchor_style: "before"
      )

      html.should contain(%(href="#kept"))
      html.should contain(%(<h2 id="old">Old</h2>))
      html.should_not contain(%(href="#old"))
    end
  end
end
