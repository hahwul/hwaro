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

private def wl_rewrite(content : String, source : Hwaro::Models::Page, index, safe = false, misses : Array({String, String})? = nil, math = false) : String
  Hwaro::Content::Processors::Wikilinks.rewrite(content, source, index, safe, misses, math: math)
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
        x <!-- [[My Note]] --> [[My Note]] <!-- inline
        [[My Note]] -->

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

    it "never rewrites inside math" do
      wl_rewrite("$[[My Note]]$ and $$[[My Note]]$$", src, index, math: true).should eq("$[[My Note]]$ and $$[[My Note]]$$")
      wl_rewrite("\\([[My Note]]\\)", src, index, math: true).should eq("\\([[My Note]]\\)")
      # Math off: `$` is plain text, so the link is rewritten.
      wl_rewrite("$[[My Note]]$", src, index).should eq("$[My Note](@/notes/My%20Note.md)$")
    end

    it "never rewrites inside a raw HTML block" do
      wl_rewrite("<div>\n[[My Note]] in html\n</div>\n", src, index).should eq("<div>\n[[My Note]] in html\n</div>\n")
    end

    it "never rewrites inside tag attributes" do
      wl_rewrite(%(<abbr title="[[My Note]]">x</abbr>), src, index).should eq(%(<abbr title="[[My Note]]">x</abbr>))
    end

    it "leaves an escaped `\\[[` alone" do
      wl_rewrite("\\[[My Note]]", src, index).should eq("\\[[My Note]]")
    end

    it "never rewrites inside a code span that crosses a line break" do
      wl_rewrite("a `code\n[[My Note]]` b", src, index).should eq("a `code\n[[My Note]]` b")
    end

    it "ends a chunk at list items, table rows and setext underlines" do
      md = <<-MD
        - press the ` key
        - run `echo [[My Note]]` here

        | key | note |
        |-----|------|
        | ` | backtick |
        | `[[My Note]]` | literal |

        Shortcut `
        ---
        See `[[My Note]]` and [[My Note]].
        MD
      wl_rewrite(md, src, index).should eq(md.sub("and [[My Note]].", "and [My Note](@/notes/My%20Note.md)."))
      # Not a table (the delimiter row is invalid): one paragraph, one code span.
      not_table = "| a | `b [[My Note]] |\n|--|--| x\n| c ` |\n"
      wl_rewrite(not_table, src, index).should eq(not_table)
      lists = "- a `\n- b [[My Note]] `\n"
      wl_rewrite(lists, src, index).should eq("- a `\n- b [My Note](@/notes/My%20Note.md) `\n")
    end

    it "keeps a line that cannot start a list item inside the paragraph" do
      md = "Released in `v[[My Note]]\n2026. year` end.\n\nSee `[[My Note]] and\n*\nmore` end.\n"
      wl_rewrite(md, src, index).should eq(md)
      # Sibling items still end the chunk.
      wl_rewrite("1. a `\n2. b [[My Note]] `\n", src, index).should eq("1. a `\n2. b [My Note](@/notes/My%20Note.md) `\n")
    end

    it "ends a chunk where a blockquote opens" do
      md = "A1 stray ` tick\n> quote `[[My Note]]` here\n"
      wl_rewrite(md, src, index).should eq(md)
    end

    it "ends a footnote definition's chunk where the footnote parser ends it" do
      wl_rewrite("[^n]: Footnote with a ` tick\nnext line [[My Note]] and ` here\n", src, index)
        .should eq("[^n]: Footnote with a ` tick\nnext line [My Note](@/notes/My%20Note.md) and ` here\n")
      indented = "[^n]: a ` tick\n    b [[My Note]] ` c\n"
      wl_rewrite(indented, src, index).should eq(indented)
    end

    it "puts math back into a link's own text and never leaks a NUL" do
      with_captured_log do
        wl_rewrite("[[My Note|cost $x$ here]]", src, index, math: true).should eq("[cost \\$x\\$ here](@/notes/My%20Note.md)")
        out = wl_rewrite("[[$y$]] ![[pic $x$.png]] [[My Note#$z$]]", src, index, math: true)
        out.should_not contain('\0')
        out.should contain(%(<span class="wikilink wikilink-missing">$y$</span>))
      end
    end

    it "links a non-image file like a page link" do
      files = [{"notes/doc.pdf", "/notes/doc.pdf"}]
      idx = wl_index([src, target], files)
      wl_rewrite("[[doc.pdf]] ![[doc.pdf|the doc]]", src, idx).should eq("[doc\\.pdf](/notes/doc.pdf) [the doc](/notes/doc.pdf)")
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

    it "matches NFC and NFD spellings of the same name" do
      nfd = wl_page("u/Cafe\u0301.md")
      src = wl_page("a.md")
      wl_index([nfd, src]).resolve("Caf\u00e9", src).should be(nfd)
      nfc = wl_page("u/Caf\u00e9.md")
      wl_index([nfc, src]).resolve("Cafe\u0301", src).should be(nfc)
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

  describe ".rewrite where InlineMarkdown renders the text" do
    src = wl_page("notes/src.md")
    index = wl_index([src, wl_page("notes/my-page.md")], [{"photo.png", "/photo.png"}])

    it "writes link text, a missing link and an image size without Markdown escapes" do
      head = "| a | b |\n|---|---|\n"
      wl_rewrite("#{head}| [[my-page]] | [[my-page\\|Hello, world!]] |", src, index).should eq("#{head}| [my-page](@/notes/my-page.md) | [Hello, world!](@/notes/my-page.md) |")
      wl_rewrite("#{head}| [[nope]] | ![[photo.png\\|300x200]] |", src, index).should eq("#{head}| nope | ![photo.png](/photo.png){width=300 height=200} |")
      wl_rewrite("Term\n: def [[my-page#A B]]", src, index).should eq("Term\n: def [my-page > A B](@/notes/my-page.md#a-b)")
      wl_rewrite("[^1]: see [[my-page]] [[nope-x]]\n    more [[my-page]]\n\n[[my-page]]", src, index)
        .should eq("[^1]: see [my-page](@/notes/my-page.md) nope-x\n    more [my-page](@/notes/my-page.md)\n\n[my\\-page](@/notes/my-page.md)")
    end

    it "leaves the paragraph form alone" do
      wl_rewrite("[[my-page]] [[nope]]", src, index).should eq(%([my\\-page](@/notes/my-page.md) <span class="wikilink wikilink-missing">nope</span>))
    end
  end

  describe ".rewrite for a missing link's text" do
    src = wl_page("notes/src.md")
    index = wl_index([src])

    it "escapes what Markd would read inside the span" do
      with_captured_log do
        wl_rewrite("[[__init__]] [[*a*]] [[`c`]] [[a\\]]", src, index).should eq(
          %(<span class="wikilink wikilink-missing">\\_\\_init\\_\\_</span> <span class="wikilink wikilink-missing">\\*a\\*</span> ) +
          %(<span class="wikilink wikilink-missing">\\`c\\`</span> <span class="wikilink wikilink-missing">a\\\\</span>))
      end
    end

    it "leaves math in the text for the math pass" do
      with_captured_log do
        wl_rewrite("[[$x_1$]]", src, index, math: true).should eq(%(<span class="wikilink wikilink-missing">$x_1$</span>))
      end
    end
  end

  describe ".rewrite near URLs and raw HTML" do
    src = wl_page("notes/src.md")
    index = wl_index([src, wl_page("notes/t.md")])

    it "keeps a wikilink inside an autolink, a link destination or a reference definition" do
      md = "<https://example.com/[[t]]> [a](http://x.y/[[t]]) [a]( <http://x.y/[[t]]>)\n\n[r]: http://x.y/[[t]]\n"
      wl_rewrite(md, src, index).should eq(md)
    end

    it "keeps a wikilink inside a processing instruction, declaration or CDATA block" do
      md = "<?php [[t]] ?>\n\n<?xml\n[[t]]\n?>\n\n<![CDATA[\n[[t]]\n]]>\n\n<!DOCTYPE [[t]]>\n\n[[t]]"
      wl_rewrite(md, src, index).should eq(md.rchop("[[t]]") + "[t](@/notes/t.md)")
    end
  end

  describe ".each_link" do
    it "yields reference definitions and the hrefs of raw HTML blocks, not footnotes or comments" do
      found = [] of String
      md = "[x][r] [^n]\n\n[r]: @/a.md\n  [s]: <@/b.md> \"t\"\n[^n]: /c/\n\n<div>\n  <a href=\"/d/\">d</a>\n  <!-- <a href=\"/e/\">e</a> -->\n</div>\n\n```html\n<div>\n[q]: /f/\n</div>\n```\n"
      Hwaro::Content::Processors::Wikilinks.each_link(md) do |link|
        found << (link.is_a?(String) ? link : "[[#{link.target}]]")
      end
      found.sort.should eq(["/d/", "@/a.md", "@/b.md"])
    end

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
