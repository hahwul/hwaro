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

private def privacy_config(extra : String = "", base_url : String = "http://example.com") : Hwaro::Models::Config
  load_config(<<-TOML)
    title = "T"
    base_url = "#{base_url}"
    [privacy]
    enabled = true
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
          <video poster="#{cdn}/img/pic.png" src="#{cdn}/img/pic.png"><source src="#{cdn}/img/pic.png"></video>
          <audio src="#{cdn}/img/pic.png"></audio>
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
      config = privacy_config(%(include = ["127.0.0.1"]\nexclude = ["example.org"]))
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
        #{extra}
        [[taxonomies]]
        name = "tags"
        TOML
      FileUtils.mkdir_p("content/posts")
      FileUtils.mkdir_p("templates")
      File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
      File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
      File.write("content/posts/a.md", "+++\ntitle = \"A\"\ntags = [\"x\"]\n+++\n<img src=\"#{cdn}/img/pic.png\">\n")
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

private def output_snapshot : Hash(String, String)
  Dir.glob("public/**/*").select { |p| File.file?(p) }.sort!.to_h { |p| {p, File.read(p)} }
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
        run_build(cache: true)
        cold = output_snapshot
        fetched = hits.total
        offline.call
        run_build(cache: true)
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
end
