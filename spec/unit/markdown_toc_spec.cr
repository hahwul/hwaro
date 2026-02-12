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
  end
end
