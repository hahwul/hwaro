require "../spec_helper"

private def make_page(path : String, url : String) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.url = url
  page
end

describe Hwaro::Content::Processors::InternalLinkResolver do
  describe ".resolve" do
    it "resolves a basic @/ link" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="@/blog/post.md">link</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq %(<a href="/blog/post/">link</a>)
    end

    it "resolves a @/ link with anchor" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="@/blog/post.md#section">link</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq %(<a href="/blog/post/#section">link</a>)
    end

    it "resolves a section _index.md link" do
      pages = {"blog/_index.md" => make_page("blog/_index.md", "/blog/")}
      html = %(<a href="@/blog/_index.md">blog</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq %(<a href="/blog/">blog</a>)
    end

    it "leaves broken link unchanged and logs warning" do
      pages = {} of String => Hwaro::Models::Page
      html = %(<a href="@/nonexistent.md">broken</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq %(<a href="@/nonexistent.md">broken</a>)
    end

    it "passes through HTML without @/ links unchanged" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="/about/">about</a><p>hello</p>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq html
    end

    it "resolves multiple @/ links in one HTML string" do
      pages = {
        "blog/post.md"   => make_page("blog/post.md", "/blog/post/"),
        "about/index.md" => make_page("about/index.md", "/about/"),
      }
      html = %(<a href="@/blog/post.md">post</a> and <a href="@/about/index.md">about</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq %(<a href="/blog/post/">post</a> and <a href="/about/">about</a>)
    end

    it "only resolves @/ links and leaves regular links untouched" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="https://example.com">ext</a> <a href="@/blog/post.md">int</a> <a href="/static/">static</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq %(<a href="https://example.com">ext</a> <a href="/blog/post/">int</a> <a href="/static/">static</a>)
    end

    it "does not match entity-encoded @/ in code blocks" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      # markd entity-encodes content inside <code>, so @/ becomes &#64;/
      html = %(<code>href="&#64;/blog/post.md"</code>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(html, pages, "index.md")
      result.should eq html
    end

    it "prepends base_url path component when site is served from a subpath" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="@/blog/post.md">link</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(
        html, pages, "index.md", "https://example.github.io/project"
      )
      result.should eq %(<a href="/project/blog/post/">link</a>)
    end

    it "prepends base_url path to links with anchors" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="@/blog/post.md#section">link</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(
        html, pages, "index.md", "https://example.github.io/project"
      )
      result.should eq %(<a href="/project/blog/post/#section">link</a>)
    end

    it "does not add prefix when base_url has no path component" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="@/blog/post.md">link</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(
        html, pages, "index.md", "https://example.com"
      )
      result.should eq %(<a href="/blog/post/">link</a>)
    end

    it "handles trailing slash in base_url" do
      pages = {"blog/post.md" => make_page("blog/post.md", "/blog/post/")}
      html = %(<a href="@/blog/post.md">link</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(
        html, pages, "index.md", "https://example.github.io/project/"
      )
      result.should eq %(<a href="/project/blog/post/">link</a>)
    end

    it "handles nested base path" do
      pages = {"docs/_index.md" => make_page("docs/_index.md", "/docs/")}
      html = %(<a href="@/docs/_index.md">docs</a>)
      result = Hwaro::Content::Processors::InternalLinkResolver.resolve(
        html, pages, "index.md", "https://example.com/a/b"
      )
      result.should eq %(<a href="/a/b/docs/">docs</a>)
    end
  end
end
