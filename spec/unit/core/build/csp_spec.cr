require "../../../spec_helper"
require "../../../support/build_helper"

private alias Csp = Hwaro::Core::Build::Csp

# Independent of Csp.hash: the browser's `'sha256-<base64>'` of `body`.
private def sha(body : String) : String
  "'sha256-#{Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(body).final)}'"
end

private def csp_config(toml : String = "") : Hwaro::Models::CspConfig
  load_config("[csp]\nenabled = true\n#{toml}").csp
end

# The value of the `name` directive in `policy`, or nil.
private def directive(policy : String, name : String) : String?
  policy.split("; ").each do |part|
    key, _, value = part.partition(' ')
    return value if key == name
  end
  nil
end

private def meta_policy(html : String) : String?
  html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]*)">/).try { |m| HTML.unescape(m[1]) }
end

private def headers_policy(headers : String, path : String) : String?
  lines = headers.lines
  lines.each_with_index do |line, i|
    return lines[i + 1].partition(": ")[2] if line == path
  end
  nil
end

private CSP_TEMPLATE = <<-HTML
  <!DOCTYPE html>
  <html><head><meta charset="utf-8"><title>{{ page.title }}</title>
  <style>body { color: red; }</style>
  </head><body><script>console.log("hi");</script>{{ content }}</body></html>
  HTML

describe Hwaro::Core::Build::Csp do
  describe ".scan" do
    it "hashes inline script and style bodies over their exact bytes" do
      body = "\n  var a = \"<b>\";\t\n"
      scan = Csp.scan(%(<script>#{body}</script><STYLE media="x"> p{} </STYLE >))
      scan.scripts.should eq([sha(body)])
      scan.styles.should eq([sha(" p{} ")])
    end

    it "normalizes CR and CRLF like the HTML parser before hashing" do
      Csp.scan("<script>a\r\nb\rc</script>").scripts.should eq([sha("a\nb\nc")])
    end

    it "skips JSON-LD, data blocks and external scripts" do
      html = <<-HTML
        <script type="application/ld+json">{"a":1}</script>
        <script type="text/template"><b>x</b></script>
        <script src="/a.js"> </script>
        HTML
      Csp.scan(html).scripts.should be_empty
    end

    it "hashes every executed script type" do
      html = %w[module importmap speculationrules text/javascript Text/JavaScript].join do |type|
        %(<script type="#{type}">#{type}</script>)
      end + %(<script type="">empty</script>)
      Csp.scan(html).scripts.size.should eq(6)
    end

    it "ignores comments and elements the parser reads as text" do
      html = %(<!-- <script>a</script> --><textarea><script>b</script></textarea><title><style>d</style></title>)
      scan = Csp.scan(html)
      scan.scripts.should be_empty
      scan.styles.should be_empty
    end

    it "hashes <noscript> styles, which apply when scripting is off" do
      Csp.scan(%(<noscript><style>.js{display:none}</style></noscript>)).styles.should eq([sha(".js{display:none}")])
    end

    it "hashes style attributes by their decoded value and flags event handlers" do
      scan = Csp.scan(%(<p style="color: &quot;red&quot;" class=x>a</p><div style='margin:0'></div><svg><g style=fill:red /></svg>))
      scan.style_attrs.should eq([sha(%(color: "red")), sha("margin:0"), sha("fill:red")])
      scan.handlers.should be_false
      Csp.scan(%(<button type="button" onClick="go()">x</button>)).handlers.should be_true
    end

    it "ends comments where the tokenizer does" do
      Csp.scan(%(<!--><script>a</script><!-- x -->)).scripts.should eq([sha("a")])
      Csp.scan(%(<!---><script>b</script>)).scripts.should eq([sha("b")])
      Csp.scan(%(<!-- x --!><script>c</script>)).scripts.should eq([sha("c")])
    end

    it "keeps a semicolon-less reference before = or an alphanumeric literal in style attributes" do
      Csp.scan(%(<p style="background:url(a?x=1&copy=2)">)).style_attrs.should eq([sha("background:url(a?x=1&copy=2)")])
      Csp.scan(%(<p style="content:'&copyx'">)).style_attrs.should eq([sha("content:'&copyx'")])
      Csp.scan(%(<p style="content:'&copy &amp; &#65;'">)).style_attrs.should eq([sha("content:'© & A'")])
    end

    it "does not raise on bytes that are not UTF-8" do
      html = String.new(Bytes[60, 104, 101, 97, 100, 62, 60, 112, 32, 115, 116, 121, 108, 101, 61, 34, 0xe9, 38, 97, 109, 112, 59, 34, 62, 0xff])
      Csp.scan(html).style_attrs.size.should eq(1)
      Csp.inject_meta(html, "p").should start_with(%(<head><meta http-equiv="Content-Security-Policy" content="p">))
    end

    it "does not read attributes inside a script body" do
      scan = Csp.scan(%(<script>var s = '<p style="x" onclick="y">';</script>))
      scan.style_attrs.should be_empty
      scan.handlers.should be_false
    end
  end

  describe ".policy" do
    it "uses the default directives" do
      Csp.policy(csp_config, "<p>x</p>").should eq(
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; " \
        "connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'")
    end

    it "keeps user script-src/style-src and appends hashes; other directives replace, empty removes" do
      config = csp_config(<<-TOML)
        [csp.directives]
        script-src = "'self' https://js.example.com"
        img-src = "*"
        frame-ancestors = ""
        upgrade-insecure-requests = ""
        TOML
      policy = Csp.policy(config, "<script>x</script><style>y</style>")
      directive(policy, "script-src").should eq("'self' https://js.example.com #{sha("x")}")
      directive(policy, "style-src").should eq("'self' #{sha("y")}")
      directive(policy, "img-src").should eq("*")
      directive(policy, "frame-ancestors").should be_nil
      policy.should end_with("; upgrade-insecure-requests")
    end

    it "sends style attributes through 'unsafe-hashes' in style-src-attr" do
      policy = Csp.policy(csp_config, %(<p style="a:b">x</p>))
      directive(policy, "style-src-attr").should eq("'unsafe-hashes' #{sha("a:b")}")
      directive(policy, "style-src").should eq("'self'")
      directive(Csp.policy(csp_config, "<p>x</p>"), "style-src-attr").should be_nil
    end

    it "adds a feature's hosts only when the page uses it" do
      cdn = %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">)
      directive(Csp.policy(csp_config, cdn), "style-src").should eq("'self' https://cdnjs.cloudflare.com")
      directive(Csp.policy(csp_config, cdn), "script-src").should eq("'self' https://cdnjs.cloudflare.com")
      local = %(<link rel="stylesheet" href="/assets/css/highlight/github.min.css">)
      directive(Csp.policy(csp_config, local), "style-src").should eq("'self'")
    end

    it "seeds an unset directive from its fallback before adding a host" do
      youtube = %(<iframe src="https://www.youtube.com/embed/abc"></iframe>)
      directive(Csp.policy(csp_config, youtube), "frame-src").should eq("'self' https://www.youtube.com")
      config = csp_config(%([csp.directives]\nchild-src = "'none'"))
      directive(Csp.policy(config, youtube), "frame-src").should eq("https://www.youtube.com")
    end

    it "drops what a <meta> policy cannot carry in meta mode" do
      config = csp_config(%(mode = "meta"\n[csp.directives]\nreport-uri = "/r"\nsandbox = "allow-scripts"))
      policy = Csp.policy(config, "<p>x</p>")
      policy.should_not contain("frame-ancestors")
      policy.should_not contain("report-uri")
      policy.should_not contain("sandbox")
      Csp.policy(config, "<p>x</p>", meta: false).should contain("frame-ancestors 'self'")
    end
  end

  describe ".inject_meta" do
    it "puts the escaped policy first in <head>, after a leading charset meta" do
      Csp.inject_meta(%(<html><HEAD lang="en"><title>t</title></head></html>), "a 'b' \"c\"").should eq(
        %(<html><HEAD lang="en"><meta http-equiv="Content-Security-Policy" content="a &apos;b&apos; &quot;c&quot;"><title>t</title></head></html>))
      Csp.inject_meta(%(<head>\n  <meta charset="utf-8">\n<title>t</title>), "p").should eq(
        %(<head>\n  <meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="p">\n<title>t</title>))
    end

    it "goes after a charset declaration that only <title> and <meta> precede" do
      Csp.inject_meta(%(<head><!-- c --><title>a<b</title><meta name="viewport" content="x"><meta charset="utf-8"><link rel="icon">), "p").should eq(
        %(<head><!-- c --><title>a<b</title><meta name="viewport" content="x"><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="p"><link rel="icon">))
      Csp.inject_meta(%(<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">), "p").should end_with(%(charset=utf-8"><meta http-equiv="Content-Security-Policy" content="p">))
      Csp.inject_meta(%(<head><link rel="icon"><meta charset="utf-8">), "p").should eq(%(<head><meta http-equiv="Content-Security-Policy" content="p"><link rel="icon"><meta charset="utf-8">))
      Csp.inject_meta(%(<!-- <head> --><html><head></head>), "p").should eq(%(<!-- <head> --><html><head><meta http-equiv="Content-Security-Policy" content="p"></head>))
    end

    it "strips its own meta" do
      page = %(<head><meta charset="utf-8"><title>t</title></head>)
      Csp.strip_meta(Csp.inject_meta(page, "p")).should eq(page)
      Csp.strip_meta(page).should eq(page)
    end

    it "replaces its own earlier meta and leaves a page without <head> alone" do
      once = Csp.inject_meta("<header></header><head><title>t</title></head>", "old")
      Csp.inject_meta(once, "new").should eq(%(<header></header><head><meta http-equiv="Content-Security-Policy" content="new"><title>t</title></head>))
      Csp.inject_meta("<p>no head</p>", "p").should eq("<p>no head</p>")
    end
  end

  describe ".url_path / .headers_file" do
    it "maps output files to served URL paths" do
      Csp.url_path("index.html").should eq("/")
      Csp.url_path("blog/a/index.html").should eq("/blog/a/")
      Csp.url_path("404.html").should eq("/404.html")
    end

    it "percent-encodes non-ASCII paths in the headers file" do
      build_site(
        %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\n),
        content_files: {"한글.md" => "+++\ntitle = \"K\"\n+++\nk"},
        template_files: {"page.html" => CSP_TEMPLATE},
      ) do
        File.read("public/_headers").should contain("\n/%ED%95%9C%EA%B8%80/\n")
      end
    end

    it "appends to the user's file, whose block for the same path and header wins" do
      user = "/a/\n  content-security-policy: default-src *\n/b/\n  X-Frame-Options: DENY\n"
      out = Csp.headers_file([{"/a/", "p1"}, {"/b/", "p2"}], "Content-Security-Policy", user)
      out.should eq(user + "\n# Content-Security-Policy generated by Hwaro ([csp])\n/b/\n  Content-Security-Policy: p2\n")
    end
  end

  describe "build" do
    it "writes a per-page headers file with base_path paths, merged with static/_headers" do
      build_site(
        %(title = "T"\nbase_url = "https://example.com/sub"\n[csp]\nenabled = true\n),
        content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\n<div style=\"x:y\">a</div>", "b.md" => "+++\ntitle = \"B\"\n+++\nb"},
        template_files: {"page.html" => CSP_TEMPLATE},
        static_files: {"_headers" => "/sub/b/\n  Content-Security-Policy: default-src *\n", "legacy.html" => "<head></head><script>x</script>"},
      ) do
        headers = File.read("public/_headers")
        headers.should start_with("/sub/b/\n  Content-Security-Policy: default-src *\n\n# Content-Security-Policy generated")
        policy = headers_policy(headers, "/sub/a/").should_not be_nil
        directive(policy, "script-src").should eq("'self' #{sha(%(console.log("hi");))}")
        directive(policy, "style-src").should eq("'self' #{sha("body { color: red; }")}")
        directive(policy, "style-src-attr").should eq("'unsafe-hashes' #{sha("x:y")}")
        headers.scan("\n/sub/b/\n").size.should eq(0)
        headers.should_not contain("legacy")
        File.read("public/a/index.html").should_not contain("Content-Security-Policy")
      end
    end

    it "injects a meta policy hashing the minified bytes, and leaves static HTML alone" do
      build_site(
        %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\nmode = "meta"\n),
        content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\n<script>\n  window.x = 1;\n</script>"},
        template_files: {"page.html" => CSP_TEMPLATE},
        static_files: {"legacy.html" => "<head></head><script>x</script>"},
        minify: true,
      ) do
        html = File.read("public/a/index.html")
        html.should contain(%(<head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="))
        policy = meta_policy(html).should_not be_nil
        policy.should_not contain("frame-ancestors")
        bodies = html.scan(/<script>(.*?)<\/script>/m).map { |m| sha(m[1]) }
        bodies.size.should eq(2)
        directive(policy, "script-src").should eq((["'self'"] + bodies).join(" "))
        File.read("public/legacy.html").should eq("<head></head><script>x</script>")
        File.exists?("public/_headers").should be_false
      end
    end

    it "skips a static HTML file that is not UTF-8" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\nmode = "meta"\n))
          FileUtils.mkdir_p("templates")
          FileUtils.mkdir_p("static")
          File.write("templates/page.html", CSP_TEMPLATE)
          legacy = Bytes[60, 104, 116, 109, 108, 62, 60, 104, 101, 97, 100, 62, 99, 97, 102, 0xe9, 60, 47, 104, 101, 97, 100, 62]
          File.write("static/legacy.html", legacy)
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
          builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)).should be_true
          File.read("public/legacy.html").to_slice.should eq(legacy)
        end
      end
    end

    it "warns about pages without <head> in meta mode" do
      log = with_captured_log do
        build_site(
          %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\nmode = "meta"\n),
          content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\na"},
          template_files: {"page.html" => "<p>{{ content }}</p>"},
        ) { }
      end
      log.should contain("[csp] no <head> to put the policy <meta> in, so these pages get no policy: a/index.html")
    end

    it "warns about inline event handlers" do
      log = with_captured_log do
        build_site(
          %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\n),
          content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\n<button onclick=\"go()\">go</button>"},
          template_files: {"page.html" => CSP_TEMPLATE},
        ) { }
      end
      log.should contain("[csp] inline event handlers (onclick=…) are blocked by the policy on a/index.html")
    end

    it "warns when a post hook changes inline bytes after hashing" do
      log = with_captured_log do
        build_site(
          %(title = "T"\nbase_url = "https://example.com"\n[build]\nhooks.post = ["sed -i.bak 's/hi/bye/' public/a/index.html"]\n[csp]\nenabled = true\n),
          content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\na"},
          template_files: {"page.html" => CSP_TEMPLATE},
        ) { }
      end
      log.should contain("hooks.post changed inline scripts or styles in ")
      log.should contain("a/index.html after its Content-Security-Policy was computed")
    end

    it "emits nothing when off" do
      build_site(
        %(title = "T"\nbase_url = "https://example.com"\n),
        content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\na"},
        template_files: {"page.html" => CSP_TEMPLATE},
      ) do
        File.exists?("public/_headers").should be_false
        File.read("public/a/index.html").should_not contain("Content-Security-Policy")
      end
    end

    it "emits nothing under serve" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\nmode = "meta"\n))
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na")
          File.write("templates/page.html", CSP_TEMPLATE)
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
          builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false, serve_mode: true))
          html = Dir.glob("**/a/index.html", match: :dot_files).map { |path| File.read(path) }
          html.should_not be_empty
          html.each(&.should_not(contain("Content-Security-Policy")))
        end
      end
    end

    {"headers", "meta"}.each do |mode|
      it "gives a warm --cache build the cold build's bytes (#{mode} mode)" do
        config = %(title = "T"\nbase_url = "https://example.com"\n[csp]\nenabled = true\nmode = "#{mode}"\n[amp]\nenabled = true\n[pwa]\nenabled = true\n)
        content = {"_index.md" => "+++\ntitle = \"Home\"\n+++\nhome", "a.md" => "+++\ntitle = \"A\"\n+++\n<p style=\"a:b\">a</p>", "b.md" => "+++\ntitle = \"B\"\n+++\nb"}
        templates = {"page.html" => CSP_TEMPLATE, "section.html" => CSP_TEMPLATE, "index.html" => CSP_TEMPLATE}
        cold = {} of String => String
        build_site(config, content_files: content, template_files: templates) do
          File.exists?("public/sw.js").should be_true
          Dir.glob("public/**/*").each { |path| cold[path] = File.read(path) if File.file?(path) }
        end
        build_site(config, content_files: content, template_files: templates, cache: true) do
          File.write("content/b.md", "+++\ntitle = \"B\"\n+++\nb")
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
          builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false, cache: true))
          builder.context.not_nil!.stats.cache_hits.should be > 0
          warm = {} of String => String
          Dir.glob("public/**/*").each { |path| warm[path] = File.read(path) if File.file?(path) }
          warm.should eq(cold)
        end
      end
    end
  end
end
