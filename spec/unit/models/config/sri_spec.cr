require "../../../spec_helper"

# `[assets] sri`: the local tags Hwaro emits carry `integrity` (with
# `crossorigin="anonymous"`, so a cross-origin view of an absolute
# `base_url` URL can still be checked) over the emitted file under
# `sri_root` (the output directory); CDN tags never do.
describe "[assets] sri" do
  it "defaults to off and parses from [assets]" do
    Hwaro::Models::Config.new.assets.sri.should be_false
    config = load_config(<<-TOML)
      title = "T"
      base_url = "https://example.com"

      [assets]
      sri = true
      TOML
    config.assets.sri.should be_true
    config.assets.enabled.should be_false
  end

  it "adds integrity to self-hosted highlight tags only" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets/css/highlight"))
      FileUtils.mkdir_p(File.join(dir, "assets/js"))
      File.write(File.join(dir, "assets/css/highlight/github.min.css"), "h{}")
      File.write(File.join(dir, "assets/js/highlight.min.js"), "x()")
      highlight = Hwaro::Models::HighlightConfig.new
      highlight.mode = "client"

      highlight.use_cdn = true
      highlight.tags("", dir).should_not contain("integrity")

      highlight.use_cdn = false
      css_sri = Hwaro::Utils::DigestUtils.sri("h{}")
      js_sri = Hwaro::Utils::DigestUtils.sri("x()")
      highlight.css_tag("abc", dir).should eq(%(<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=abc" integrity="#{css_sri}" crossorigin="anonymous">))
      highlight.js_tag("", dir).should contain(%(<script src="/assets/js/highlight.min.js" integrity="#{js_sri}" crossorigin="anonymous"></script>))
      highlight.tags("", dir).should contain(css_sri)
      # Off (no root) is byte-identical to the pre-SRI tag.
      highlight.css_tag("abc").should eq(%(<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=abc">))
    end
  end

  it "adds integrity to auto-include tags and skips files that were not emitted" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("static/inc")
        File.write("static/inc/a.css", "a{}")
        File.write("static/inc/b.js", "b()")
        FileUtils.mkdir_p("public/inc")
        File.write("public/inc/a.css", "a{}")
        includes = Hwaro::Models::AutoIncludesConfig.new
        includes.enabled = true
        includes.dirs = ["inc"]

        tags = includes.all_tags("https://x.test", "", "public")
        tags.should contain(%(<link rel="stylesheet" href="https://x.test/inc/a.css" integrity="#{Hwaro::Utils::DigestUtils.sri("a{}")}" crossorigin="anonymous">))
        tags.should contain(%(<script src="https://x.test/inc/b.js"></script>))
        includes.all_tags("https://x.test", "").should_not contain("integrity")
      end
    end
  end
end
