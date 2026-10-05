require "../../../spec_helper"
require "../../../../src/content/processors/wikilinks"

private def wl_page(path : String, url : String? = nil, language : String? = nil, assets = [] of String) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  base = File.basename(path)
  page.is_index = base.starts_with?("index.") || base.starts_with?("_index.")
  page.url = url || "/#{path.rchop(".md")}/"
  page.language = language
  page.assets = assets
  page
end

private def wl_index(pages : Array(Hwaro::Models::Page), files = [] of {String, String}) : Hwaro::Content::Processors::Wikilinks::Index
  Hwaro::Content::Processors::Wikilinks::Index.new(pages, "en", -> { files })
end

private def wl_rewrite(content : String, source : Hwaro::Models::Page, index, safe = false, misses : Array({String, String})? = nil) : String
  Hwaro::Content::Processors::Wikilinks.rewrite(content, source, index, safe, misses)
end

describe Hwaro::Content::Processors::Wikilinks do
  describe ".rewrite" do
    src = wl_page("notes/src.md")
    target = wl_page("notes/My Note.md")
    index = wl_index([src, target])

    it "rewrites every link form to an @/ Markdown link" do
      wl_rewrite("[[My Note]]", src, index).should eq("[My Note](@/notes/My%20Note.md)")
      wl_rewrite("[[My Note|the note]]", src, index).should eq("[the note](@/notes/My%20Note.md)")
      wl_rewrite("[[My Note#Setup Guide]]", src, index).should eq("[My Note \\> Setup Guide](@/notes/My%20Note.md#setup-guide)")
      wl_rewrite("[[My Note#Setup Guide|go]]", src, index).should eq("[go](@/notes/My%20Note.md#setup-guide)")
      wl_rewrite("[[#Local Part]]", src, index).should eq("[Local Part](#local-part)")
    end

    it "matches case-insensitively, by content path and with an extension" do
      wl_rewrite("[[my note]]", src, index).should eq("[my note](@/notes/My%20Note.md)")
      wl_rewrite("[[notes/my note]]", src, index).should eq("[notes\\/my note](@/notes/My%20Note.md)")
      wl_rewrite("[[My Note.md]]", src, index).should eq("[My Note\\.md](@/notes/My%20Note.md)")
    end

    it "links a block ref to the page without the fragment" do
      wl_rewrite("[[My Note#^abc123]]", src, index).should eq("[My Note](@/notes/My%20Note.md)")
    end

    it "takes `\\|` as the alias pipe (tables)" do
      wl_rewrite("| [[My Note\\|alias]] |", src, index).should eq("| [alias](@/notes/My%20Note.md) |")
    end

    it "escapes Markdown in the link text" do
      wl_rewrite("[[My Note|*x* [y]]]", src, index).should eq("[[My Note|*x* [y]]]") # `]` ends the alias
      wl_rewrite("[[My Note|*x* _y_]]", src, index).should eq("[\\*x\\* \\_y\\_](@/notes/My%20Note.md)")
    end

    it "renders an unresolved link as a missing span and reports it" do
      misses = [] of {String, String}
      log = with_captured_log { wl_rewrite("a [[Nope|<b>]] b", src, index, misses: misses).should eq(%(a <span class="wikilink wikilink-missing">&lt;b&gt;</span> b)) }
      log.should contain("Wikilink '[[Nope|<b>]]' in 'notes/src.md' could not be resolved: page not found.")
      misses.should eq([{"[[Nope|<b>]]", "page not found"}])
    end

    it "renders an unresolved link as plain text in safe mode" do
      with_captured_log { wl_rewrite("[[Nope]]", src, index, safe: true).should eq("Nope") }
    end

    it "never rewrites inside code or HTML comments" do
      md = <<-MD
        `[[My Note]]` and ``a [[My Note]] b``
        <!-- [[My Note]] --> [[My Note]]
        <!-- open
        [[My Note]]
        -->

        ```
        [[My Note]]
        ```

            [[My Note]]
        MD
      out = wl_rewrite(md, src, index)
      out.should eq(md.sub("--> [[My Note]]", "--> [My Note](@/notes/My%20Note.md)"))
    end

    it "is a no-op without `[[`" do
      text = "plain [link](x)"
      wl_rewrite(text, src, index).should be(text)
    end
  end

  describe "resolution" do
    it "names a bundle and a section by their directory" do
      bundle = wl_page("guides/install/index.md")
      section = wl_page("guides/_index.md")
      src = wl_page("a.md")
      index = wl_index([bundle, section, src])
      index.resolve("install", src).should be(bundle)
      index.resolve("Guides", src).should be(section)
      index.resolve("guides/install", src).should be(bundle)
    end

    it "prefers the source page's language and strips the language suffix" do
      en = wl_page("about.md")
      ko = wl_page("about.ko.md", language: "ko")
      ko_src = wl_page("intro.ko.md", language: "ko")
      en_src = wl_page("intro.md")
      index = wl_index([en, ko, ko_src, en_src])
      log = with_captured_log do
        index.resolve("about", ko_src).should be(ko)
        index.resolve("about", en_src).should be(en)
      end
      log.should_not contain("Ambiguous")
    end

    it "breaks ties by same directory, then shortest path, then name, warning once with every candidate" do
      src = wl_page("blog/post.md")
      near = wl_page("blog/setup.md")
      short = wl_page("a/setup.md")
      far = wl_page("docs/deep/setup.md")
      index = wl_index([far, short, near, src])
      log = with_captured_log do
        index.resolve("setup", src).should be(near)
        index.resolve("setup", src).should be(near)
      end
      log.scan("Ambiguous wikilink").size.should eq(1)
      log.should contain("Ambiguous wikilink '[[setup]]' in 'blog/post.md' matches a/setup.md, blog/setup.md, docs/deep/setup.md; using 'blog/setup.md'.")

      other = wl_page("x/y.md")
      with_captured_log { wl_index([far, short, near, other]).resolve("setup", other).should be(short) }
      b = wl_page("b/setup.md")
      with_captured_log { wl_index([b, short, other]).resolve("setup", other).should be(short) }
    end

    it "does not match titles" do
      page = wl_page("p.md")
      page.title = "Fancy Title"
      wl_index([page]).resolve("Fancy Title", page).should be_nil
    end
  end

  describe "image embeds" do
    src = wl_page("posts/trip/index.md", url: "/posts/trip/", assets: ["posts/trip/photo.png", "posts/trip/img/map.png"])
    files = [{"posts/other/photo.png", "/posts/other/photo.png"}, {"img/logo.svg", "/img/logo.svg"}, {"img/My Pic.png", "/img/My Pic.png"}]
    index = wl_index([src], files)

    it "prefers the page's own bundle asset, relative" do
      wl_rewrite("![[photo.png]]", src, index).should eq("![photo\\.png](photo.png)")
      wl_rewrite("![[map.png]]", src, index).should eq("![map\\.png](img/map.png)")
    end

    it "finds a published file elsewhere by name" do
      wl_rewrite("![[logo.svg]]", src, index).should eq("![logo\\.svg](/img/logo.svg)")
      wl_rewrite("![[My Pic.png]]", src, index).should eq("![My Pic\\.png](/img/My%20Pic.png)")
    end

    it "reads a numeric alias as the size and any other as the alt text" do
      wl_rewrite("![[photo.png|300]]", src, index).should eq("![photo\\.png](photo.png){width=300}")
      wl_rewrite("![[photo.png|300x200]]", src, index).should eq("![photo\\.png](photo.png){width=300 height=200}")
      wl_rewrite("![[photo.png|A trip]]", src, index).should eq("![A trip](photo.png)")
    end

    it "reports a missing file, and links a non-image embed like a wikilink" do
      misses = [] of {String, String}
      with_captured_log { wl_rewrite("![[gone.png]]", src, index, misses: misses) }
      misses.should eq([{"![[gone.png]]", "file not found"}])
      wl_rewrite("![[trip]]", src, index).should eq("[trip](@/posts/trip/index.md)")
    end
  end

  describe ".each_link" do
    it "yields wikilinks and link URLs outside code" do
      found = [] of String
      md = "[[A]] [b](/b/) <a href=\"/c/\">c</a> `[d](/d/)`\n```\n[[E]]\n```\n"
      Hwaro::Content::Processors::Wikilinks.each_link(md) do |link|
        found << (link.is_a?(String) ? link : "[[#{link.target}]]")
      end
      found.should eq(["[[A]]", "/b/", "/c/"])
    end
  end
end
