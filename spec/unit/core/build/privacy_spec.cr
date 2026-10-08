require "../../../spec_helper"

# Specs for `[privacy]` (issue #840): localizing third-party assets at build
# time. Every HTTP interaction runs against an in-process HTTP::Server bound
# to 127.0.0.1:0 — these specs never touch the external network.

private alias Privacy = Hwaro::Core::Build::Privacy

private WOFF2 = "wOF2\xFF\x00\x01binary-font"
private PNG   = "\x89PNG\r\n\x1A\nfake-image"
private JS    = "console.log('hi');\n"

# Per-path request counts, shared by the fixture server and the examples.
private class Hits
  @counts = Hash(String, Int32).new(0)
  @mutex = Mutex.new

  def bump(path : String) : Nil
    @mutex.synchronize { @counts[path] += 1 }
  end

  def [](path : String) : Int32
    @mutex.synchronize { @counts[path] }
  end

  def total : Int32
    @mutex.synchronize { @counts.values.sum }
  end
end

# The fixture CDN: nested CSS with fonts, images, a script, a redirect, a
# 404, an oversized body, a slow body, a CSS chain deeper than MAX_DEPTH and
# an import cycle.
private def fixture_handler(hits : Hits) : HTTP::Server::Context ->
  ->(ctx : HTTP::Server::Context) do
    path = ctx.request.path
    hits.bump(path)
    res = ctx.response
    port = ctx.request.headers["Host"]?.try(&.split(':').last) || "80"
    css = ->(body : String) { res.content_type = "text/css; charset=utf-8"; res.print(body) }
    case path
    when "/css/site.css"
      css.call(%(@import url("nested.css");\n/* url(ignored.png) */\n@font-face { src: url(/fonts/a.woff2) format("woff2"), url('data:font/woff2;base64,AA'); }\n.x { background: url(#frag); }\n))
    when "/css/nested.css"
      css.call(%(@import "../css/inner.css";\nbody { background: url('../img/pic.png'); }\n))
    when "/css/inner.css"
      css.call(%(.i { background: url("/img/copy.png?v=2#hash"); }\n))
    when "/css2"
      # Google Fonts serves woff2 only to a browser User-Agent.
      font = ctx.request.headers["User-Agent"]?.try(&.includes?("Mozilla")) ? "a.woff2" : "a.ttf"
      css.call(%(@font-face { src: url(/fonts/#{font}); }\n))
    when .starts_with?("/deep/")
      n = path.lchop("/deep/d").rchop(".css").to_i
      css.call(n < 7 ? %(@import "d#{n + 1}.css";\n) : %(.end { color: red; }\n))
    when "/cycle/a.css"
      css.call(%(@import "b.css";\n))
    when "/cycle/b.css"
      css.call(%(@import "a.css";\n))
    when "/fonts/a.woff2"
      res.content_type = "font/woff2"
      res.print(WOFF2)
    when "/img/pic.png", "/img/copy.png"
      res.content_type = "image/png"
      res.print(PNG)
    when "/media/clip.mp4"
      res.content_type = "video/mp4"
      res.print("MP4")
    when "/img/body.png"
      res.content_type = "image/png"
      res.print("BODY-PNG")
    when "/img/only404.png"
      res.content_type = "image/png"
      res.print("ONLY-404-PNG")
    when .starts_with?("/img/%")
      res.content_type = "image/png"
      res.print(PNG)
    when "/upload/w_400,h_300/sample.jpg"
      res.content_type = "image/jpeg"
      res.print("JPEG")
    when "/css/set.css"
      css.call(%(.a { background-image: image-set("../img/pic.png" type("image/png") 1x, url(../img/copy.png) 2x); }\n))
    when "/photo-jpg"
      res.content_type = "image/jpg"
      res.print("JPG")
    when "/fonts/f3"
      res.content_type = "application/x-font-woff"
      res.print("wOFF")
    when "/css/legacy.css"
      css.call(%(@font-face { src: url(../fonts/f3); }\n))
    when "/flaky.png"
      # Down for the first request, up afterwards.
      if hits["/flaky.png"] == 1
        res.status = HTTP::Status::SERVICE_UNAVAILABLE
      else
        res.content_type = "image/png"
        res.print("FLAKY-PNG")
      end
      # A third party pointing the build at the machine's own network.
    when "/redir-internal"
      res.status = HTTP::Status::FOUND
      res.headers["Location"] = "http://localhost:#{port}/secret"
    when "/css/evil.css"
      css.call(%(body { background: url(http://localhost:#{port}/secret.png); }\n))
    when "/secret", "/secret.png"
      res.content_type = "image/png"
      res.print("AWS_SECRET=hunter2")
    when "/photo.html"
      res.content_type = "text/html"
      res.print("<script>alert(document.cookie)</script>")
    when "/logo.svg"
      res.content_type = "image/svg+xml"
      res.print(%(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>))
    when "/img/noext"
      res.content_type = "image/webp"
      res.print("RIFFwebp")
    when "/js/app.js"
      res.content_type = "application/javascript"
      res.print(JS)
    when "/redirect"
      res.status = HTTP::Status::FOUND
      res.headers["Location"] = "/js/app.js"
    when "/big"
      res.content_type = "image/png"
      res.print("x" * 4096)
    when "/slow"
      res.content_type = "image/png"
      res.print("a")
      res.flush
      sleep 3.seconds
      res.print("b")
    else
      res.status = HTTP::Status::NOT_FOUND
    end
  end
end

# Yields the base URL, the hit counter and a proc that takes the CDN offline.
private def with_cdn(& : String, Hits, Proc(Nil) ->)
  hits = Hits.new
  server = HTTP::Server.new(fixture_handler(hits))
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  Fiber.yield
  begin
    yield "http://127.0.0.1:#{address.port}", hits, -> { server.close }
  ensure
    server.close unless server.closed?
  end
end

# A server that answers every request with a malformed HTTP response.
private def with_garbage_server(& : String ->)
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  spawn do
    while client = server.accept?
      spawn do
        while (line = client.gets) && !line.empty?
        end
        client << "GARBAGE\r\n\r\n"
        client.close
      rescue IO::Error
      end
    end
  end
  Fiber.yield
  begin
    yield "http://127.0.0.1:#{port}"
  ensure
    server.close
  end
end

# The fixture CDN lives on loopback, which privacy mode refuses unless
# `include` names the host — so the default lists it.
private def privacy_config(extra : String = "", base_url : String = "http://example.com", hosts : String = %(["127.0.0.1"])) : Hwaro::Models::Config
  load_config(<<-TOML)
    title = "T"
    base_url = "#{base_url}"
    [privacy]
    enabled = true
    include = #{hosts}
    #{extra}
    TOML
end

# Run `block` in a fresh project dir with a Privacy over `public/`.
private def with_privacy(config : Hwaro::Models::Config, now : Time = Time.utc, sri : Bool = false, **opts, & : Privacy, String ->)
  Dir.mktmpdir do |dir|
    output = File.join(dir, "public")
    cache = File.join(dir, ".hwaro", "external")
    privacy = Privacy.new(config, output, sri ? output : nil, cache_dir: cache, now: now,
      max_bytes: opts[:max_bytes]? || Privacy::MAX_BYTES, deadline: opts[:deadline]? || Privacy::FETCH_DEADLINE)
    yield privacy, dir
  end
end

private def rewrite(privacy : Privacy, html : String) : String
  privacy.rewrite_html(html)[0]
end

private def published(dir : String) : Array(String)
  root = File.join(dir, "public", "assets", "external")
  Dir.exists?(root) ? Dir.children(root).sort! : [] of String
end

private def read_published(dir : String, url : String) : String
  File.read(File.join(dir, "public", url.lchop("/")))
end

describe Hwaro::Core::Build::Privacy do
  it "rewrites every tag and attribute kind" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        html = <<-HTML
          <link rel="stylesheet" href="#{cdn}/css/inner.css">
          <link rel="preload" as="image" href="#{cdn}/img/pic.png">
          <link rel="modulepreload" href="#{cdn}/js/app.js">
          <link rel="icon" href="#{cdn}/img/pic.png">
          <script src="#{cdn}/js/app.js"></script>
          <img src="#{cdn}/img/pic.png" alt="x">
          <picture><source srcset="#{cdn}/img/pic.png 1x, /local.png 2x"></picture>
          <video poster="#{cdn}/img/pic.png" src="#{cdn}/media/clip.mp4"><source src="#{cdn}/media/clip.mp4"></video>
          <audio src="#{cdn}/media/clip.mp4"></audio>
          HTML
        result = rewrite(privacy, html)
        result.should_not contain(%(href="#{cdn}/css))
        result.should contain(%(<link rel="icon" href="#{cdn}/img/pic.png">))
        result.scan(cdn).size.should eq(1) # only the icon
        result.should contain(%(<script src="/assets/external/))
        result.should contain(%(srcset="/assets/external/))
        result.should contain(" 1x, /local.png 2x")
        result.should match(/<video poster="\/assets\/external\/[0-9a-f]{12}-pic\.png" src="\/assets\/external\//)
        published(dir).should contain(published(dir).find(&.ends_with?("-app.js")))
      end
    end
  end

  it "leaves same-host, relative, data: and excluded/non-included URLs alone" do
    with_cdn do |cdn, hits, _server|
      config = privacy_config(%(exclude = ["example.org"]))
      with_privacy(config) do |privacy, _dir|
        html = <<-HTML
          <img src="http://example.com/own.png">
          <img src="/rel.png"><img src="rel.png">
          <img src="data:image/png;base64,AA">
          <img src="https://example.org/x.png">
          <img src="http://localhost:1/x.png">
          HTML
        rewrite(privacy, html).should eq(html)
        hits.total.should eq(0)
        rewrite(privacy, %(<img src="#{cdn}/img/pic.png">)).should contain("/assets/external/")
      end
    end
  end

  it "localizes protocol-relative URLs over the configured scheme" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, _dir|
        rel = cdn.lchop("http:")
        rewrite(privacy, %(<img src="#{rel}/img/pic.png">)).should match(/src="\/assets\/external\/[0-9a-f]{12}-pic\.png"/)
      end
    end
  end

  it "rewrites nested CSS recursively, relative to the stylesheet" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        result = rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css/site.css">))
        url = result.match!(/href="([^"]+)"/)[1]
        css = read_published(dir, url)
        css.should_not contain("127.0.0.1")
        css.should match(/@import url\("[0-9a-f]{12}-nested\.css"\)/)
        css.should match(/url\("[0-9a-f]{12}-a\.woff2"\) format/)
        css.should contain("/* url(ignored.png) */")
        css.should contain("url('data:font/woff2;base64,AA')")
        css.should contain("url(#frag)")
        nested = published(dir).find!(&.ends_with?("-nested.css"))
        inner_css = File.read(File.join(dir, "public/assets/external", published(dir).find!(&.ends_with?("-inner.css"))))
        inner_css.should match(/url\("[0-9a-f]{12}-copy\.png#hash"\)/)
        File.read(File.join(dir, "public/assets/external", nested)).should match(/@import "[0-9a-f]{12}-inner\.css"/)
        File.read(File.join(dir, "public/assets/external", published(dir).find!(&.ends_with?("-a.woff2")))).should eq(WOFF2)
      end
    end
  end

  it "stops at MAX_DEPTH and survives import cycles" do
    with_cdn do |cdn, hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/deep/d1.css">))
        # d1 (depth 0) … d5 (depth 4) are local; d5 keeps d6 absolute.
        (1..5).each { |n| published(dir).any?(&.ends_with?("-d#{n}.css")).should be_true }
        hits["/deep/d6.css"].should eq(0)
        d5 = published(dir).find!(&.ends_with?("-d5.css"))
        File.read(File.join(dir, "public/assets/external", d5)).should contain(%(@import "#{cdn}/deep/d6.css"))

        rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/cycle/a.css">))
        b = published(dir).find!(&.ends_with?("-b.css"))
        File.read(File.join(dir, "public/assets/external", b)).should contain(%(@import "#{cdn}/cycle/a.css"))
        hits["/cycle/a.css"].should eq(1)
      end
    end
  end

  it "dedupes identical bytes and fetches each URL once" do
    with_cdn do |cdn, hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        rewrite(privacy, %(<img src="#{cdn}/img/pic.png"><img src="#{cdn}/img/pic.png">))
        rewrite(privacy, %(<img src="#{cdn}/img/copy.png">))
        hits["/img/pic.png"].should eq(1)
        hashes = published(dir).map(&.split('-').first)
        hashes.uniq.size.should eq(1)
      end
    end
  end

  it "names files from the URL, the Content-Type when the path has no extension" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css2?family=Inter&amp;display=swap"><img src="#{cdn}/img/noext">))
        published(dir).any?(&.matches?(/\A[0-9a-f]{12}-css2\.css\z/)).should be_true
        published(dir).any?(&.matches?(/\A[0-9a-f]{12}-noext\.webp\z/)).should be_true
      end
    end
  end

  it "requests Google-Fonts-style CSS with a browser User-Agent" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css2?family=Inter">))
        published(dir).any?(&.ends_with?("-a.woff2")).should be_true
      end
    end
  end

  it "follows redirects" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, dir|
        result = rewrite(privacy, %(<script src="#{cdn}/redirect"></script>))
        read_published(dir, result.match!(/src="([^"]+)"/)[1]).should eq(JS)
      end
    end
  end

  it "keeps the external URL on a 404, oversized or slow body under warn-and-keep" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config, max_bytes: 1024_i64, deadline: 1.second) do |privacy, _dir|
        %w[/missing /big /slow].each do |path|
          html = %(<img src="#{cdn}#{path}">)
          log = with_captured_log { rewrite(privacy, html).should eq(html) }
          log.should contain("keeping the external URL")
        end
      end
    end
  end

  it "raises under on_error = fail" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config(%(on_error = "fail"))) do |privacy, _dir|
        err = expect_raises(Hwaro::HwaroError) { rewrite(privacy, %(<img src="#{cdn}/missing">)) }
        err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
      end
    end
  end

  it "reuses a fresh cache offline, refetches a stale one, and falls back to it when the network fails" do
    with_cdn do |cdn, hits, offline|
      t0 = Time.utc
      Dir.mktmpdir do |dir|
        output = File.join(dir, "public")
        cache = File.join(dir, "cache")
        html = %(<img src="#{cdn}/img/pic.png">)
        make = ->(now : Time) { Privacy.new(privacy_config, output, nil, cache_dir: cache, now: now) }

        first = make.call(t0).rewrite_html(html)[0]
        hits["/img/pic.png"].should eq(1)
        make.call(t0 + 1.day).rewrite_html(html)[0].should eq(first)
        hits["/img/pic.png"].should eq(1)
        make.call(t0 + 8.days).rewrite_html(html)[0].should eq(first)
        hits["/img/pic.png"].should eq(2)

        offline.call
        make.call(t0 + 8.days).rewrite_html(html)[0].should eq(first) # fresh again, offline
        log = with_captured_log { make.call(t0 + 30.days).rewrite_html(html)[0].should eq(first) }
        log.should contain("using the cached copy")
      end
    end
  end

  it "keeps integrity that matches the downloaded bytes and drops one that does not" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config) do |privacy, _dir|
        good = Hwaro::Utils::DigestUtils.sri(JS)
        result = rewrite(privacy, %(<script src="#{cdn}/js/app.js" integrity="#{good}" crossorigin="anonymous"></script>))
        result.should contain(%(integrity="#{good}" crossorigin="anonymous"))

        log = with_captured_log do
          result = rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css/inner.css" integrity="sha384-AAAA" crossorigin="anonymous" />))
        end
        result.should_not contain("integrity")
        result.should_not contain("crossorigin")
        result.should end_with(" />")
        log.should contain("does not match")
        log.should contain("#{cdn}/css/inner.css")
      end
    end
  end

  it "stamps Hwaro's own integrity with [assets] sri" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config, sri: true) do |privacy, _dir|
        result = rewrite(privacy, %(<script src="#{cdn}/js/app.js" integrity="sha384-AAAA"></script>))
        result.should contain(%(integrity="#{Hwaro::Utils::DigestUtils.sri(JS)}" crossorigin="anonymous"))
        result.should_not contain("sha384-AAAA")
      end
    end
  end

  it "prefixes base_path" do
    with_cdn do |cdn, _hits, _server|
      with_privacy(privacy_config(base_url: "http://example.com/blog")) do |privacy, _dir|
        rewrite(privacy, %(<img src="#{cdn}/img/pic.png">)).should match(/src="\/blog\/assets\/external\/[0-9a-f]{12}-pic\.png"/)
      end
    end
  end

  it "skips comments, inline scripts and styles" do
    with_cdn do |cdn, hits, _server|
      with_privacy(privacy_config) do |privacy, _dir|
        html = %(<!-- <img src="#{cdn}/img/pic.png"> --><script>var s = '<img src="#{cdn}/img/pic.png">';</script><style>.a{background:url(#{cdn}/img/pic.png)}</style>)
        rewrite(privacy, html).should eq(html)
        hits.total.should eq(0)
      end
    end
  end

  it "refuses a host that resolves to an internal address unless include names it" do
    with_cdn do |cdn, hits, _offline|
      with_privacy(privacy_config(hosts: "[]")) do |privacy, dir|
        html = %(<img src="#{cdn}/img/pic.png">)
        log = with_captured_log { rewrite(privacy, html).should eq(html) }
        log.should contain("refused")
        hits.total.should eq(0)
        published(dir).should be_empty
      end
      with_privacy(privacy_config(%(on_error = "fail"), hosts: "[]")) do |privacy, _dir|
        expect_raises(Hwaro::HwaroError, /refused/) { rewrite(privacy, %(<img src="#{cdn}/img/pic.png">)) }
      end
    end
  end

  it "refuses a redirect hop and a stylesheet reference into the internal network" do
    with_cdn do |cdn, hits, _offline|
      with_privacy(privacy_config) do |privacy, dir|
        html = %(<img src="#{cdn}/redir-internal">)
        log = with_captured_log { rewrite(privacy, html).should eq(html) }
        log.should contain("refused")

        result = rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css/evil.css">))
        css = read_published(dir, result.match!(/href="([^"]+)"/)[1])
        css.should contain("url(\"http://localhost:")
        hits["/secret"].should eq(0)
        hits["/secret.png"].should eq(0)
        published(dir).none? { |f| File.read(File.join(dir, "public/assets/external", f)).includes?("AWS_SECRET") }.should be_true
      end
    end
  end

  it "never publishes HTML, and publishes SVG for <img> with a warning" do
    with_cdn do |cdn, _hits, _offline|
      with_privacy(privacy_config) do |privacy, dir|
        html = %(<img src="#{cdn}/photo.html">)
        log = with_captured_log { rewrite(privacy, html).should eq(html) }
        log.should contain("not a file type Hwaro publishes")
        published(dir).should be_empty

        log = with_captured_log { rewrite(privacy, %(<img src="#{cdn}/logo.svg">)).should contain("-logo.svg") }
        log.should contain("SVG")
        # A script reference answered with an image is not published as .svg.
        script = %(<script src="#{cdn}/logo.svg"></script>)
        rewrite(privacy, script).should eq(script)
      end
    end
  end

  it "survives a malformed response and undecodable URL bytes" do
    with_garbage_server do |garbage|
      with_cdn do |cdn, _hits, _offline|
        with_privacy(privacy_config) do |privacy, _dir|
          html = %(<img src="#{garbage}/x.png">)
          log = with_captured_log { rewrite(privacy, html).should eq(html) }
          log.should contain("Invalid HTTP response")
          rewrite(privacy, %(<img src="#{cdn}/img/%ff%fe.png">)).should match(/src="\/assets\/external\/[0-9a-f]{12}-[^"]*\.png"/)
        end
      end
    end
  end

  it "parses srcset candidates whose URLs contain commas" do
    with_cdn do |cdn, hits, _offline|
      with_privacy(privacy_config) do |privacy, _dir|
        srcset = %(https://res.example.invalid/x.png 1x, #{cdn}/upload/w_400,h_300/sample.jpg 2x)
        result = rewrite(privacy, %(<img srcset="#{srcset}">))
        result.should match(/srcset="https:\/\/res\.example\.invalid\/x\.png 1x, \/assets\/external\/[0-9a-f]{12}-sample\.jpg 2x"/)
        hits["/upload/w_400,h_300/sample.jpg"].should eq(1)
        hits["/upload/w_400"].should eq(0)
      end
    end
  end

  it "drops preconnect and dns-prefetch hints to localized hosts" do
    with_cdn do |cdn, _hits, _offline|
      with_privacy(privacy_config(%(exclude = ["www.youtube.com"]))) do |privacy, _dir|
        html = %(<link rel="preconnect" href="#{cdn}"><link rel="dns-prefetch" href="#{cdn.lchop("http:")}"><link rel="preconnect" href="https://www.youtube.com"><link rel="stylesheet" href="#{cdn}/css/inner.css">)
        result = rewrite(privacy, html)
        result.should_not contain("preconnect\" href=\"#{cdn}")
        result.should_not contain("dns-prefetch")
        result.should contain(%(<link rel="preconnect" href="https://www.youtube.com">))
      end
    end
  end

  it "keeps connection hints for hosts it localized nothing from" do
    with_cdn do |cdn, _hits, _offline|
      with_privacy(privacy_config(hosts: "[]")) do |privacy, _dir|
        html = %(<link rel="preconnect" href="https://www.youtube-nocookie.com"><link rel="dns-prefetch" href="#{cdn}">)
        with_captured_log { rewrite(privacy, html).should eq(html) }
      end
    end
  end

  it "accepts common non-standard image and font MIME types" do
    with_cdn do |cdn, _hits, _offline|
      with_privacy(privacy_config) do |privacy, dir|
        rewrite(privacy, %(<img src="#{cdn}/photo-jpg">)).should match(/src="\/assets\/external\/[0-9a-f]{12}-photo-jpg\.jpg"/)
        result = rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css/legacy.css">))
        read_published(dir, result.match!(/href="([^"]+)"/)[1]).should match(/url\("[0-9a-f]{12}-f3\.woff"\)/)
      end
    end
  end

  it "leaves Hwaro's own MathJax loader external" do
    Dir.mktmpdir do |dir|
      # A fresh cache entry, so the pre-fix code would localize it offline.
      url = "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"
      cache = File.join(dir, ".hwaro", "external")
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, "blob"), "mathjax")
      File.write(File.join(cache, "index.json"), {url => {file: "blob", fetched_at: Time.utc.to_unix, content_type: "application/javascript", sha256: "blob", final_url: url}}.to_json)
      privacy = Privacy.new(privacy_config(hosts: %(["cdn.jsdelivr.net"])), File.join(dir, "public"), nil, cache_dir: cache)
      html = %(<script async src="#{url}"></script>)
      rewrite(privacy, html).should eq(html)
    end
  end

  it "treats another port on the site's host as external" do
    with_cdn do |cdn, _hits, _offline|
      with_privacy(privacy_config(base_url: "http://127.0.0.1:1")) do |privacy, _dir|
        rewrite(privacy, %(<img src="#{cdn}/img/pic.png">)).should contain("/assets/external/")
        rewrite(privacy, %(<img src="http://127.0.0.1:1/own.png">)).should contain("http://127.0.0.1:1/own.png")
      end
    end
  end

  it "rewrites image-set() strings in downloaded CSS" do
    with_cdn do |cdn, hits, _offline|
      with_privacy(privacy_config) do |privacy, dir|
        result = rewrite(privacy, %(<link rel="stylesheet" href="#{cdn}/css/set.css">))
        css = read_published(dir, result.match!(/href="([^"]+)"/)[1])
        css.should_not contain("../img")
        css.should match(/image-set\("[0-9a-f]{12}-pic\.png" type\("image\/png"\) 1x, url\("[0-9a-f]{12}-copy\.png"\) 2x\)/)
        hits["/css/image/png"].should eq(0)
      end
    end
  end

  it "does not retry a failed URL on the next build of the same process" do
    with_cdn do |cdn, hits, _offline|
      2.times do
        with_privacy(privacy_config) do |privacy, _dir|
          with_captured_log { rewrite(privacy, %(<img src="#{cdn}/missing">)) }
        end
      end
      hits["/missing"].should eq(1)
    end
  end
end

# End-to-end through Builder#run.
private def privacy_site(cdn : String, extra : String = "", &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", <<-TOML)
        title = "T"
        base_url = "http://example.com"
        [privacy]
        enabled = true
        include = ["127.0.0.1"]
        #{extra}
        [[taxonomies]]
        name = "tags"
        TOML
      FileUtils.mkdir_p("content/posts")
      FileUtils.mkdir_p("templates")
      File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
      File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
      File.write("content/posts/a.md", "+++\ntitle = \"A\"\ntags = [\"x\"]\n+++\n<img src=\"#{cdn}/img/pic.png\"><img src=\"#{cdn}/img/body.png\">\n")
      layout = %(<html><head><link rel="stylesheet" href="#{cdn}/css/site.css"><script src="#{cdn}/js/app.js"></script></head><body>{{ content | safe }}</body></html>)
      %w[page section index taxonomy taxonomy_term 404].each { |t| File.write("templates/#{t}.html", layout) }
      yield dir
    end
  end
end

private def run_build(cache : Bool = false, minify : Bool = false, builder = Hwaro::Core::Build::Builder.new, serve_mode : Bool = false)
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) } unless serve_mode && builder.context
  builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: cache, minify: minify, serve_mode: serve_mode))
  builder
end

# Sources older than the build epoch, so a warm `--cache` build really
# skips them (a file written in the build's own second reads as dirty).
private def backdate_sources : Nil
  past = Time.utc - 1.hour
  (Dir.glob("content/**/*") + Dir.glob("templates/**/*") + ["config.toml"]).each do |path|
    File.utime(past, past, path) if File.file?(path)
  end
end

private def output_snapshot : Hash(String, String)
  Dir.glob("public/**/*").select { |p| File.file?(p) }.sort!.to_h { |p| {p, File.read(p)} }
end

# Specs run in one process; forget the 10-minute retry window.
class Hwaro::Core::Build::Privacy
  def self.test_forget_failures : Nil
    @@failures_mutex.synchronize { @@failures.clear }
  end
end

# An incremental serve pass re-claims nothing.
class Hwaro::Core::Build::Builder
  def test_mark_claims_stale : Nil
    @generated_claims_current = false
  end
end

describe "[privacy] builds" do
  it "localizes pages, sections, taxonomies and 404 end to end, leaving no external host" do
    with_cdn do |cdn, _hits, _server|
      privacy_site(cdn) do
        run_build(minify: true)
        html_files = Dir.glob("public/**/*.html")
        %w[public/index.html public/posts/index.html public/posts/a/index.html public/tags/index.html public/tags/x/index.html public/404.html].each do |f|
          html_files.should contain(f)
        end
        html_files.each do |f|
          html = File.read(f)
          next if html.includes?("http-equiv=\"refresh\"")
          html.should_not contain("127.0.0.1")
        end
        Dir.glob("public/assets/external/*.css").each { |f| File.read(f).should_not contain("127.0.0.1") }
        Dir.exists?(".hwaro/external").should be_true
      end
    end
  end

  it "is a byte-identical warm --cache build that keeps localized files, and works offline" do
    with_cdn do |cdn, hits, offline|
      privacy_site(cdn) do
        backdate_sources
        run_build(cache: true)
        cold = output_snapshot
        cold.keys.any?(&.ends_with?("-body.png")).should be_true
        fetched = hits.total
        offline.call
        warm = run_build(cache: true)
        warm.context.not_nil!.stats.pages_rendered.should eq(0)
        output_snapshot.should eq(cold)
        hits.total.should eq(fetched)
        # A full cold build offline still works from .hwaro/external.
        FileUtils.rm_rf("public")
        run_build
        output_snapshot.should eq(cold)
      end
    end
  end

  it "does not refetch across serve rebuilds and keeps its cache outside the watch roots" do
    with_cdn do |cdn, hits, _server|
      privacy_site(cdn) do
        builder = run_build(serve_mode: true)
        fetched = hits.total
        fetched.should be > 0
        run_build(builder: builder, serve_mode: true)
        hits.total.should eq(fetched)
        Hwaro::Services::Server::WATCH_ROOTS.none? { |root| Privacy::CACHE_DIR.starts_with?("#{root}/") }.should be_true
      end
    end
  end

  it "keeps a file only the 404 page uses through a serve incremental prune" do
    with_cdn do |cdn, _hits, _offline|
      privacy_site(cdn) do
        File.write("templates/404.html", %(<html><body><img src="#{cdn}/img/only404.png"></body></html>))
        builder = run_build(serve_mode: true)
        file = Dir.glob("public/assets/external/*-only404.png").first
        past = Time.utc - 1.hour
        File.utime(past, past, file)
        builder.test_mark_claims_stale
        builder.prune_unclaimed_outputs([file], "public")
        File.exists?(file).should be_true
      end
    end
  end

  it "renders a page again on the next --cache build after its download failed" do
    with_cdn do |cdn, _hits, _offline|
      privacy_site(cdn) do
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\n+++\n<img src=\"#{cdn}/flaky.png\">\n")
        backdate_sources
        with_captured_log { run_build(cache: true) }
        File.read("public/posts/a/index.html").should contain("#{cdn}/flaky.png")
        Privacy.test_forget_failures
        run_build(cache: true)
        File.read("public/posts/a/index.html").should match(/src="\/assets\/external\/[0-9a-f]{12}-flaky\.png"/)
      end
    end
  end

  it "leaves the output untouched when disabled" do
    with_cdn do |cdn, hits, _server|
      privacy_site(cdn, "") do
        File.write("config.toml", File.read("config.toml").sub("enabled = true", "enabled = false"))
        run_build
        File.read("public/posts/a/index.html").should contain("#{cdn}/img/pic.png")
        hits.total.should eq(0)
        Dir.exists?(".hwaro/external").should be_false
        Dir.exists?("public/assets/external").should be_false
      end
    end
  end

  it "replaces external PWA precache URLs with their local copies" do
    with_cdn do |cdn, _hits, _server|
      privacy_site(cdn, %([pwa]\nenabled = true\nprecache_urls = ["/", "#{cdn}/js/app.js"])) do
        run_build
        sw = File.read("public/sw.js")
        sw.should_not contain("127.0.0.1")
        sw.should match(/"\/assets\/external\/[0-9a-f]{12}-app\.js"/)
      end
    end
  end

  it "keeps the local precache URLs when serve regenerates sw.js" do
    with_cdn do |cdn, _hits, _server|
      privacy_site(cdn, %([pwa]\nenabled = true\nprecache_urls = ["/", "#{cdn}/js/app.js"])) do
        builder = run_build(serve_mode: true)
        full = File.read("public/sw.js")
        full.should match(/"\/assets\/external\/[0-9a-f]{12}-app\.js"/)

        builder.site.try { |site| builder.regenerate_service_worker(site, "public", false) }
        File.read("public/sw.js").should eq(full)
      end
    end
  end
end
