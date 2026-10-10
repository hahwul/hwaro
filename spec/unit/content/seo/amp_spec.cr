require "../../../spec_helper"

private def make_amp_config(toml : String = "") : Hwaro::Models::Config
  config_str = <<-TOML
    title = "Test Site"
    description = "A test site"
    base_url = "https://example.com"
    #{toml}
    TOML

  File.tempfile("hwaro-amp", ".toml") do |file|
    file.print(config_str)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe Hwaro::Models::AmpConfig do
  describe "defaults" do
    it "is disabled by default" do
      config = Hwaro::Models::Config.new
      config.amp.enabled.should be_false
      config.amp.path_prefix.should eq("amp")
      config.amp.sections.should be_empty
    end
  end

  describe "loading from TOML" do
    it "loads amp config" do
      config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        path_prefix = "mobile"
        sections = ["posts", "blog"]
        TOML

      config.amp.enabled.should be_true
      config.amp.path_prefix.should eq("mobile")
      config.amp.sections.should eq(["posts", "blog"])
    end
  end

  describe "#section_enabled?" do
    it "returns true for any section when sections is empty" do
      config = Hwaro::Models::Config.new
      config.amp.section_enabled?("posts").should be_true
      config.amp.section_enabled?("anything").should be_true
    end

    it "returns true only for configured sections" do
      config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        sections = ["posts"]
        TOML

      config.amp.section_enabled?("posts").should be_true
      config.amp.section_enabled?("pages").should be_false
    end

    it "covers a configured section's descendants, like [feeds] sections" do
      config = make_amp_config(<<-TOML)
        [amp]
        enabled = true
        sections = ["posts"]
        TOML

      config.amp.section_enabled?("posts/2024").should be_true
      config.amp.section_enabled?("postscript").should be_false
    end
  end
end

describe Hwaro::Content::Seo::Amp do
  describe ".convert_to_amp" do
    it "adds amp attribute to html tag" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      html = "<html lang=\"en\"><head></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<html amp lang=\"en\">")
    end

    # Regression: the mirror is written one prefix deeper (/amp/posts/b1/), so a
    # document-relative `cover.png` / `../b2/` copied verbatim resolved under
    # /amp/ — a 404 for page-bundle images and links outside the mirrored tree.
    describe "document-relative URLs" do
      html = %(<html><head></head><body><img src="cover.png" alt="c" width="10" height="10"><a href="../b2/">rel</a> <a href="cover.png">file</a> <a href="/root/">root</a> <a href="#frag">frag</a> <a href="https://other.test/x">abs</a> <a href="//cdn.test/x">proto</a> <a href="mailto:a@b.test">mail</a></body></html>)

      it "resolves them against the canonical page URL" do
        page = Hwaro::Models::Page.new("posts/b1/index.md")
        page.url = "/posts/b1/"
        config = Hwaro::Models::Config.new
        config.base_url = "https://example.com/sub"

        result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
        result.should contain(%(src="https://example.com/sub/posts/b1/cover.png"))
        result.should contain(%(href="https://example.com/sub/posts/b2/"))
        result.should contain(%(href="https://example.com/sub/posts/b1/cover.png"))
      end

      it "leaves root-relative, absolute, protocol-relative, scheme and fragment URLs alone" do
        page = Hwaro::Models::Page.new("posts/b1/index.md")
        page.url = "/posts/b1/"
        config = Hwaro::Models::Config.new
        config.base_url = "https://example.com"

        result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
        result.should contain(%(href="/root/"))
        result.should contain(%(href="#frag"))
        result.should contain(%(href="https://other.test/x"))
        result.should contain(%(href="//cdn.test/x"))
        result.should contain(%(href="mailto:a@b.test"))
      end

      it "resolves to root-relative paths when base_url is empty" do
        page = Hwaro::Models::Page.new("posts/b1/index.md")
        page.url = "/posts/b1/"
        config = Hwaro::Models::Config.new
        config.base_url = ""

        result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
        result.should contain(%(src="/posts/b1/cover.png"))
        result.should contain(%(href="/posts/b2/"))
      end
    end

    it "converts img to amp-img with fill layout when no dimensions" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><img src="/photo.jpg" alt="Photo"></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should contain("layout=\"fill\"")
      result.should contain("amp-img-container")
      result.should_not contain("<img ")
    end

    it "converts img to amp-img with responsive layout when dimensions present" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><img src="/photo.jpg" width="800" height="600"></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should contain("layout=\"responsive\"")
      # The img should NOT be wrapped in a container div
      result.should_not contain(%(<div class="amp-img-container"><amp-img))
    end

    # Markdown renders images as self-closing `<img … />`. The conversion regex
    # greedily captured that trailing slash, producing the invalid
    # `<amp-img … / layout="fill">`. The slash must be stripped.
    it "does not leave a stray slash mid-tag for self-closing <img />" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<p><img src="https://example.com/a.png" alt="A diagram" /></p>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should_not contain("<img")
      result.should contain("</amp-img>")
      # No orphaned self-closing slash before the appended layout attribute.
      result.should_not match(/<amp-img[^>]*\/\s+layout=/)
      result.should_not contain(%(alt="A diagram" /))
    end

    it "removes inline style attributes" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><div style="color: red">text</div></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("style=")
      result.should contain("text")
    end

    # Regression: the value ended at the first quote of EITHER kind, leaving
    # `dialog').showModal()"` behind as a garbage attribute.
    it "removes whole event handlers and styles whose values nest the other quote" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      html = %(<html><head></head><body><div class="c" onclick="this.querySelector('dialog').showModal()" ) +
             %(style="font-family:'Foo'">x</div><p onmouseover='say("hi")'>y</p></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, Hwaro::Models::Config.new)
      result.should contain(%(<div class="c">x</div>))
      result.should contain(%(<p>y</p>))
    end

    # Regression: `loading` is legal on <img>/<iframe> but is not an allowed
    # attribute on amp-img/amp-iframe/amp-video, so it fails AMP validation as
    # DISALLOWED_ATTR. hwaro emits it itself — `[markdown] lazy_loading`, the
    # image pipeline, and the built-in youtube/vimeo/codepen/figure shortcodes
    # all hard-code `loading="lazy"` — so it reached nearly every AMP page.
    it "drops the loading attribute when converting to AMP elements" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = <<-HTML
        <p><img loading="lazy" src="/a.png" alt="A"></p>
        <iframe src="https://youtube.com/embed/x" width="560" height="315" loading="lazy"></iframe>
        <video src="/v.mp4" loading=lazy></video>
        HTML

      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-img")
      result.should contain("<amp-iframe")
      result.should contain("<amp-video")
      result.should_not contain("loading=")
      # Only the disallowed attribute goes; the rest of the tag is intact.
      result.should contain(%(src="/a.png"))
      result.should contain(%(alt="A"))
      result.should contain(%(width="560"))
    end

    # Regression: theme image hints `decoding`/`fetchpriority` are not
    # allowed on amp-img and failed validation.
    it "drops decoding and fetchpriority from amp-img" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      html = %(<html><head></head><body><img src="/h.png" width="8" height="4" alt="h" decoding="async" fetchpriority="high"></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, Hwaro::Models::Config.new)
      result.should contain(%(<amp-img src="/h.png" width="8" height="4" alt="h" layout="responsive">))
    end

    # Scoped to the converted tag's attribute string, so `loading=` appearing
    # inside <style amp-custom> or JSON-LD text is left alone.
    it "does not strip loading= from stylesheet or ld+json text" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head><script type="application/ld+json">{"a":"x loading='lazy' y"}</script></head><body>t</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("x loading='lazy' y")
    end

    it "strips disallowed external stylesheets but keeps font-provider links" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head>" +
             %(<link rel="stylesheet" href="/css/style.css">) +
             %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/highlight.min.css">) +
             %(<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Inter">) +
             "</head><body>x</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)

      # Disallowed stylesheets (site CSS, highlight.js CDN) are removed...
      result.should_not contain("/css/style.css")
      result.should_not contain("cdnjs.cloudflare.com")
      # ...but allowlisted font-provider stylesheets stay.
      result.should contain("fonts.googleapis.com")
    end

    it "injects AMP boilerplate CSS" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("amp-boilerplate")
      result.should contain("cdn.ampproject.org")
    end

    # Regression: the -ms-animation declaration was missing, and the AMP
    # validator requires the boilerplate verbatim — every page failed with
    # "The mandatory text inside tag 'head > style[amp-boilerplate]' is
    # missing or incorrect".
    it "injects the AMP boilerplate verbatim" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      result = Hwaro::Content::Seo::Amp.convert_to_amp("<html><head></head><body>x</body></html>", page, Hwaro::Models::Config.new)
      result.should contain(
        "<style amp-boilerplate>body{-webkit-animation:-amp-start 8s steps(1,end) 0s 1 normal both;" \
        "-moz-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-ms-animation:-amp-start 8s steps(1,end) 0s 1 normal both;" \
        "animation:-amp-start 8s steps(1,end) 0s 1 normal both}@-webkit-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}" \
        "@-moz-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-ms-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}" \
        "@-o-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}</style>" \
        "<noscript><style amp-boilerplate>body{-webkit-animation:none;-moz-animation:none;-ms-animation:none;animation:none}</style></noscript>")
    end

    it "adds canonical link to original page" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/posts/hello/"
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      html = "<html><head></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(rel="canonical"))
      result.should contain("https://example.com/posts/hello/")
    end

    it "removes disallowed script tags" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head><script>alert(1)</script></head><body>Hello</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("alert(1)")
    end

    it "removes multiline script tags" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head><script>\nconsole.log('hello');\nalert(1);\n</script></head><body>Hello</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("console.log")
      result.should_not contain("alert(1)")
    end

    it "preserves ld+json scripts" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head><script type="application/ld+json">{"@type":"Article"}</script></head><body>Hello</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("application/ld+json")
    end

    # Regression: any `async` script survived (analytics, the tweet
    # shortcode's widgets.js), which AMP forbids.
    it "removes third-party async scripts but keeps AMP's own" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      amp_ext = %(<script async custom-element="amp-bind" src="https://cdn.ampproject.org/v0/amp-bind-0.1.js"></script>)
      html = %(<html><head><script async src="https://www.googletagmanager.com/gtag/js?id=G-1"></script>#{amp_ext}</head>) +
             %(<body><script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, Hwaro::Models::Config.new)
      result.should_not contain("googletagmanager")
      result.should_not contain("platform.twitter.com")
      result.should contain(amp_ext)
    end

    # Regression: the simple scaffold's inline CSS uses @view-transition and
    # @starting-style; folded into <style amp-custom> they are CSS syntax
    # errors that fail every AMP page.
    it "drops at-rules AMP disallows from folded theme CSS" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      css = "/* @starting-style in a comment; */ a{content:\"@x {\"}\n" \
            "@view-transition { navigation: auto; }\n@import url(x.css);\n" \
            "@media (prefers-reduced-motion: no-preference) { .m{opacity:1} @starting-style { .m{opacity:0} } }\n" \
            "@font-face{font-family:F;src:url(f.woff2)} @keyframes k{from{opacity:0}to{opacity:1}} b{c:d} @layer x"
      html = "<html><head><style>#{css}</style></head><body>x</body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, Hwaro::Models::Config.new)
      custom = result[/<style amp-custom>([\s\S]*?)<\/style>/, 1]
      custom.should_not contain("@view-transition")
      custom.should_not contain("@import")
      custom.should_not contain("@starting-style {")
      custom.should contain("/* @starting-style in a comment; */ a{content:\"@x {\"}")
      custom.should contain("@media (prefers-reduced-motion: no-preference) { .m{opacity:1}  }")
      custom.should contain("@font-face{font-family:F;src:url(f.woff2)} @keyframes k{from{opacity:0}to{opacity:1}} b{c:d}")
      custom.should_not contain("@layer")
    end

    # Regression: the codepen shortcode / CodePen embed snippet (height only,
    # allowfullscreen="true", frameborder="no") became an invalid amp-iframe.
    it "converts a height-only embed iframe into a valid amp-iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      html = %(<html><head></head><body><iframe height="300" scrolling="no" src="https://codepen.io/u/embed/x" ) +
             %(frameborder="no" allowtransparency="true" allowfullscreen="true"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, Hwaro::Models::Config.new)
      tag = result[/<amp-iframe[^>]*>/]
      tag.should contain(%(layout="fixed-height"))
      tag.should contain(%(frameborder="0"))
      tag.should contain(" allowtransparency ")
      tag.should contain(" allowfullscreen ")
      tag.should_not contain(%(="true"))
    end

    it "converts iframe to amp-iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><iframe src="https://example.com"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-iframe")
      result.should_not contain("<iframe")
    end

    it "adds a sandbox attribute and amp-iframe extension script" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><iframe src="https://example.com"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-iframe")
      result.should contain("sandbox=")
      result.should contain(%(custom-element="amp-iframe"))
      result.should contain("amp-iframe-0.1.js")
    end

    it "preserves an existing sandbox attribute on iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><iframe src="https://example.com" sandbox="allow-scripts"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(sandbox="allow-scripts"))
      # No duplicate sandbox attribute was appended.
      result.scan(/sandbox=/).size.should eq(1)
    end

    # AMP: "An amp-iframe must not be in the same origin as the container
    # unless they do not allow allow-same-origin in the sandbox attribute."
    it "grants allow-same-origin to a cross-origin iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="https://www.youtube.com/embed/x"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(sandbox="allow-scripts allow-same-origin allow-popups"))
    end

    it "withholds allow-same-origin from a same-origin iframe" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="https://example.com/embed/"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(sandbox="allow-scripts allow-popups"))
      result.should_not contain("allow-same-origin")
    end

    it "withholds allow-same-origin from a root-relative iframe src" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="/embed/widget.html"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("allow-same-origin")
    end

    it "withholds allow-same-origin from an unquoted same-origin src" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src=/embed/widget.html width=600></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("allow-same-origin")
    end

    it "withholds allow-same-origin from an iframe with no src" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe width="600"></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain("allow-same-origin")
    end

    it "keeps the iframe body when adding a sandbox" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = make_amp_config

      html = %(<html><head></head><body><iframe src="https://cdn.example.org/e"><p>fallback</p></iframe></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<p>fallback</p>")
    end

    describe ".same_origin_src?" do
      it "treats relative references as same-origin" do
        Hwaro::Content::Seo::Amp.same_origin_src?("/a/", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("a/b.html", "https://example.com").should be_true
      end

      it "compares scheme, host, and port" do
        Hwaro::Content::Seo::Amp.same_origin_src?("https://example.com/a", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("https://EXAMPLE.com/a", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("https://other.com/a", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("http://example.com/a", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("https://example.com:8443/a", "https://example.com").should be_false
      end

      it "treats a src whose port overflows Int32 as unknown (same-origin)" do
        Hwaro::Content::Seo::Amp.same_origin_src?("http://a.example:99999999999999999999/x", "https://example.com").should be_true
      end

      it "treats an explicit default port as equal to an implicit one" do
        Hwaro::Content::Seo::Amp.same_origin_src?("https://example.com:443/a", "https://example.com").should be_true
      end

      it "resolves a protocol-relative src against the document scheme" do
        Hwaro::Content::Seo::Amp.same_origin_src?("//example.com/a", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("//other.com/a", "https://example.com").should be_false
      end

      # Fail-safe direction: an src we can't read must not be granted
      # allow-same-origin, because a wrong guess there is the exact AMP
      # violation this check exists to prevent.
      it "treats an unreadable src as same-origin" do
        Hwaro::Content::Seo::Amp.same_origin_src?("", "https://example.com").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("   ", "https://example.com").should be_true
      end

      it "compares the port on a protocol-relative src" do
        Hwaro::Content::Seo::Amp.same_origin_src?("//example.com:8443/a", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("//example.com:443/a", "https://example.com").should be_true
      end

      it "treats opaque-origin schemes as cross-origin" do
        Hwaro::Content::Seo::Amp.same_origin_src?("data:text/html,hi", "https://example.com").should be_false
        Hwaro::Content::Seo::Amp.same_origin_src?("about:blank", "https://example.com").should be_false
      end

      it "handles a base_url carrying a subpath" do
        Hwaro::Content::Seo::Amp.same_origin_src?("/repo/e/", "https://user.github.io/repo").should be_true
        Hwaro::Content::Seo::Amp.same_origin_src?("https://user.github.io/repo/e/", "https://user.github.io/repo").should be_true
      end
    end

    it "adds amp-video extension script when video present" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = %(<html><head></head><body><video src="/v.mp4" width="640" height="360"></video></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain("<amp-video")
      result.should contain(%(custom-element="amp-video"))
      result.should contain("amp-video-0.1.js")
    end

    it "injects missing extension scripts when boilerplate already present" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head><style amp-boilerplate>body{}</style>" +
             %(<script async src="https://cdn.ampproject.org/v0.js"></script>) +
             "</head><body><iframe src=\"https://example.com\"></iframe></body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(custom-element="amp-iframe"))
      result.should contain("amp-iframe-0.1.js")
    end

    it "does not duplicate extension scripts already declared" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      html = "<html><head><style amp-boilerplate>body{}</style>" +
             %(<script async src="https://cdn.ampproject.org/v0.js"></script>) +
             %(<script async custom-element="amp-iframe" src="https://cdn.ampproject.org/v0/amp-iframe-0.1.js"></script>) +
             "</head><body><iframe src=\"https://example.com\"></iframe></body></html>"
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.scan(/custom-element="amp-iframe"/).size.should eq(1)
    end

    it "strips a self-referencing amphtml link (idempotent across builds)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      # Simulate the on-disk canonical HTML from a prior run already carrying an
      # amphtml link.
      html = %(<html><head><link rel="amphtml" href="https://example.com/amp/test/"></head><body>Hi</body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should_not contain(%(rel="amphtml"))
    end

    it "unwraps a paragraph whose sole child is an amp-img container" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      # Markdown wraps a standalone image in <p>...</p>.
      html = %(<html><head></head><body><p><img src="/x.png" alt="x" /></p></body></html>)
      result = Hwaro::Content::Seo::Amp.convert_to_amp(html, page, config)
      result.should contain(%(<div class="amp-img-container">))
      # The block container must not be nested directly inside <p>.
      result.should_not match(/<p>\s*<div class="amp-img-container"/)
    end
  end

  describe ".generate" do
    it "does nothing when disabled" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        pages = [] of Hwaro::Models::Page
        Hwaro::Content::Seo::Amp.generate(pages, config, dir)

        Dir.glob(File.join(dir, "**/*")).should be_empty
      end
    end

    it "writes no mirror for a redirect_to stub" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          TOML
        page = Hwaro::Models::Page.new("moved.md")
        page.url = "/moved/"
        page.redirect_to = "https://elsewhere.example/"
        FileUtils.mkdir_p(File.join(dir, "moved"))
        File.write(File.join(dir, "moved", "index.html"), "<html><head></head><body>stub</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        File.exists?(File.join(dir, "amp", "moved", "index.html")).should be_false
        Hwaro::Content::Seo::Amp.mirror_output_for(page, config, dir).should be_nil
      end
    end

    it "generates AMP page from canonical HTML" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          sections = ["posts"]
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.title = "Hello"
        page.section = "posts"
        page.render = true

        # Write a canonical HTML file
        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body><p>Hello World</p></body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        # AMP version should exist
        amp_path = File.join(dir, "amp", "posts", "hello", "index.html")
        File.exists?(amp_path).should be_true

        amp_content = File.read(amp_path)
        amp_content.should contain("<html amp>")
        amp_content.should contain("amp-boilerplate")

        # Canonical page should have amphtml link
        canonical_content = File.read(File.join(canonical_dir, "index.html"))
        canonical_content.should contain("rel=\"amphtml\"")
        canonical_content.should contain("/amp/posts/hello/")
      end
    end

    it "mirrors a page whose URL carries an encoded # or ?" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          TOML

        # Page#url= stores `#`/`?` as %23/%3F; render writes the decoded dir.
        page = Hwaro::Models::Page.new("posts/c#-tips.md")
        page.url = "/posts/c#-tips/"
        page.section = "posts"
        canonical_dir = File.join(dir, "posts", "c#-tips")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body>C#</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        amp_path = File.join(dir, "amp", "posts", "c#-tips", "index.html")
        File.exists?(amp_path).should be_true
        Hwaro::Content::Seo::Amp.mirror_output_for(page, config, dir).should eq(amp_path)
        File.read(File.join(canonical_dir, "index.html")).should contain(%(href="https://example.com/amp/posts/c%23-tips/"))
      end
    end

    it "percent-encodes the amphtml and fallback canonical URLs" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          TOML

        page = Hwaro::Models::Page.new("글 하나.md")
        page.url = "/글 하나/"
        canonical_dir = File.join(dir, "글 하나")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body>x</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        File.read(File.join(canonical_dir, "index.html"))
          .should contain(%(rel="amphtml" href="https://example.com/amp/%EA%B8%80%20%ED%95%98%EB%82%98/"))
        File.read(File.join(dir, "amp", "글 하나", "index.html"))
          .should contain(%(rel="canonical" href="https://example.com/%EA%B8%80%20%ED%95%98%EB%82%98/"))
      end
    end

    it "skips sections not in configured list" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          sections = ["posts"]
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/about/"
        page.section = "pages"
        page.render = true

        canonical_dir = File.join(dir, "about")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body>About</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        File.exists?(File.join(dir, "amp", "about", "index.html")).should be_false
      end
    end

    it "uses custom path prefix" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          path_prefix = "mobile"
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.section = "posts"
        page.render = true

        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        File.write(File.join(canonical_dir, "index.html"), "<html><head></head><body>Hello</body></html>")

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        File.exists?(File.join(dir, "mobile", "posts", "hello", "index.html")).should be_true
      end
    end

    # A blank/slash-only path_prefix collapses amp_output_path onto the
    # canonical path, which would overwrite every page with its AMP variant.
    # The guard must skip generation, leaving canonical HTML untouched.
    it "skips generation when path_prefix is slash-only to avoid clobbering canonical pages" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          path_prefix = "/"
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.section = "posts"
        page.render = true

        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        original = "<html><head></head><body><p>Hello World</p></body></html>"
        canonical_path = File.join(canonical_dir, "index.html")
        File.write(canonical_path, original)

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        # Canonical page is unchanged (not AMP-converted, not clobbered).
        content = File.read(canonical_path)
        content.should eq(original)
        content.should_not contain("<html amp")
      end
    end

    it "skips generation when path_prefix is empty to avoid clobbering canonical pages" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          path_prefix = ""
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/hello/"
        page.section = "posts"
        page.render = true

        canonical_dir = File.join(dir, "posts", "hello")
        FileUtils.mkdir_p(canonical_dir)
        original = "<html><head></head><body><p>Hello World</p></body></html>"
        canonical_path = File.join(canonical_dir, "index.html")
        File.write(canonical_path, original)

        Hwaro::Content::Seo::Amp.generate([page], config, dir)

        content = File.read(canonical_path)
        content.should eq(original)
        content.should_not contain("<html amp")
      end
    end

    # A dot-segment prefix (".", "./", "a/..") is not empty, so the emptiness
    # guard above never fires, yet File.join resolves it right back onto the
    # canonical path — the AMP variant would overwrite the page it was
    # converted from and point rel="amphtml" at itself.
    [".", "./", "a/.."].each do |traversing_prefix|
      it "skips generation when path_prefix is #{traversing_prefix.inspect} to avoid clobbering canonical pages" do
        Dir.mktmpdir do |dir|
          config = make_amp_config(<<-TOML)
            [amp]
            enabled = true
            path_prefix = "#{traversing_prefix}"
            TOML

          page = Hwaro::Models::Page.new("test.md")
          page.url = "/posts/hello/"
          page.section = "posts"
          page.render = true

          canonical_dir = File.join(dir, "posts", "hello")
          FileUtils.mkdir_p(canonical_dir)
          original = "<html><head></head><body><p>Hello World</p></body></html>"
          canonical_path = File.join(canonical_dir, "index.html")
          File.write(canonical_path, original)

          log = with_captured_log do
            Hwaro::Content::Seo::Amp.generate([page], config, dir)
          end

          content = File.read(canonical_path)
          content.should eq(original)
          content.should_not contain("<html amp")
          content.should_not contain("amphtml")
          log.should contain("path_prefix")
        end
      end
    end

    it "skips draft pages" do
      Dir.mktmpdir do |dir|
        config = make_amp_config(<<-TOML)
          [amp]
          enabled = true
          TOML

        page = Hwaro::Models::Page.new("test.md")
        page.url = "/posts/draft/"
        page.section = "posts"
        page.draft = true
        page.render = true

        Hwaro::Content::Seo::Amp.generate([page], config, dir)
        File.exists?(File.join(dir, "amp", "posts", "draft", "index.html")).should be_false
      end
    end
  end
end
