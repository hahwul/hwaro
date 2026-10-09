require "../../spec_helper"
require "../../support/build_helper"

# =============================================================================
# `[search] ui = true`: the built-in client under assets/hwaro-search/ and the
# `{{ search_tags }}` markup that loads it.
# =============================================================================

private UI_CONFIG = <<-TOML
  title = "T"
  base_url = "http://localhost"

  [search]
  enabled = true
  ui = true
  TOML

private UI_TEMPLATE = {"page.html" => "<head>{{ search_tags }}</head>{{ content }}", "section.html" => "<head>{{ search_tags }}</head>"}

private def ui_config(toml : String = "") : Hwaro::Models::Config
  load_config(UI_CONFIG + "\n" + toml)
end

private def payload(tags : String) : JSON::Any
  attr = tags.match!(/data-hwaro-search-config="([^"]*)"/)[1]
  JSON.parse(HTML.unescape(attr))
end

describe Hwaro::Content::SearchUi do
  describe "the client source" do
    js = Hwaro::Content::SearchUi::JS

    it "never builds markup from strings" do
      # Index data (titles, headings, excerpts) reaches the DOM only through
      # textContent and text nodes; the search-UI XSS of PR #643 came from
      # string-built markup.
      js.should_not match(/innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function/)
      js.should contain("textContent")
      js.should contain("document.createTextNode")
    end

    it "routes every index URL through the same-origin guard" do
      js.should contain("(u.protocol !== \"http:\" && u.protocol !== \"https:\") || u.origin !== origin")
      # The only href written is a safeUrl() result, as are shard URLs.
      js.scan(/\.href\s*=\s*(\w+)/).map(&.[1]).should eq(["url"])
      js.should contain("var url = safeUrl(r.url, location.origin);")
      js.should contain("var url = safeUrl(s.url, location.origin);")
    end

    it "returns the checked absolute URL, never a bare path" do
      # `/.//evil.com` resolves same-origin, but its normalized path
      # `//evil.com` is protocol-relative: a returned path would leave the
      # origin again in `href` and `fetch`.
      guard = js[js.index!("function safeUrl")...js.index!("function hasFacet")]
      guard.should contain("return u.href;")
      guard.should_not match(/u\.pathname|u\.search|u\.hash/)
    end

    it "tolerates a failing shard and retries after a total failure" do
      load = js[js.index!("function load()")...js.index!("function build(")]
      # Each shard fetch has its own catch, so the others stay searchable.
      load.should contain("getJson(url).catch(function (err) {")
      # A failure that left no records clears the memo so the next open refetches.
      load.should contain("if (failed && !records.length) loading = null;")
    end

    it "keeps chip counts free of Object.prototype keys" do
      js.should contain("var counts = Object.create(null);")
    end

    it "has no inline-script dependency and no external requests" do
      js.should_not match(%r{https?://})
      Hwaro::Content::SearchUi::CSS.should_not match(%r{https?://|@import})
      Hwaro::Content::SearchUi::CSS.should contain("prefers-color-scheme: dark")
    end
  end

  describe ".tags" do
    translations = Hwaro::Content::I18n::TranslationData.new

    it "links the assets with cache-busting and a data- payload, no inline script" do
      config = ui_config
      tags = Hwaro::Content::SearchUi.tags(config, "en", translations, true, nil)
      tags.should match(%r{\A<link rel="stylesheet" href="/assets/hwaro-search/search\.css\?v=[0-9a-f]{8}">\n<script defer src="/assets/hwaro-search/search\.js\?v=[0-9a-f]{8}" data-hwaro-search-config="[^"]*"></script>\z})
      Hwaro::Content::SearchUi.tags(config, "en", translations, false, nil).should_not contain("?v=")
      data = payload(tags)
      data["index"].should eq("/search.json")
      data["manifest"]?.should be_nil
      data["lang"]?.should be_nil
      data["cjk"].should be_false
      data["i18n"]["placeholder"].should eq("Search")
      data["i18n"]["results_other"].should eq("{count} results")
    end

    it "prefixes base_path and points sharded sites at the manifest" do
      config = ui_config(%(shards = "language"\nsingle_file = false\nfacets = ["lang"]\ntokenize_cjk = true\n)).tap(&.base_url=("https://example.com/docs"))
      tags = Hwaro::Content::SearchUi.tags(config, "en", translations, false, nil)
      tags.should contain(%(href="/docs/assets/hwaro-search/search.css"))
      tags.should contain(%(src="/docs/assets/hwaro-search/search.js"))
      data = payload(tags)
      data["index"]?.should be_nil
      data["manifest"].should eq("/docs/search/index.json")
      data["base"].should eq("/docs")
      data["cjk"].should be_true
      data["facets"].as_a.map(&.as_s).should eq(["lang"])
    end

    it "adds integrity from the emitted files under [assets] sri" do
      Dir.mktmpdir do |dir|
        config = ui_config
        Hwaro::Content::SearchUi.write_assets(config, dir)
        tags = Hwaro::Content::SearchUi.tags(config, "en", translations, true, dir)
        tags.should contain(%(integrity="#{Hwaro::Utils::DigestUtils.sri(Hwaro::Content::SearchUi::CSS)}" crossorigin="anonymous"))
        tags.should contain(%(integrity="#{Hwaro::Utils::DigestUtils.sri(Hwaro::Content::SearchUi::JS)}" crossorigin="anonymous"))
      end
    end

    it "escapes i18n strings into the attribute and falls back to the default language" do
      data = Hwaro::Content::I18n::TranslationData{
        "en" => {"search.placeholder" => %(Find "it" </script><b>), "search.results_count.one" => "one hit"},
        "ko" => {"search.no_results" => "결과 없음", "search.results_count" => "{count}개 결과"},
      }
      config = ui_config
      tags = Hwaro::Content::SearchUi.tags(config, "ko", data, false, nil)
      tags.should_not contain("<b>")
      tags.should_not contain(%("it"))
      strings = payload(tags)["i18n"]
      strings["placeholder"].should eq(%(Find "it" </script><b>))
      strings["no_results"].should eq("결과 없음")
      strings["results_one"].should eq("{count}개 결과")
      strings["results_other"].should eq("{count}개 결과")
      strings["close"].should eq("Close")
      payload(Hwaro::Content::SearchUi.tags(config, "en", data, false, nil))["i18n"]["results_one"].should eq("one hit")
    end
  end

  describe "in a build" do
    it "emits the assets, claims them and renders search_tags" do
      build_site(UI_CONFIG, content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\nx\n"}, template_files: UI_TEMPLATE) do |dir|
        File.read(File.join(dir, "public/assets/hwaro-search/search.js")).should eq(Hwaro::Content::SearchUi::JS)
        File.read(File.join(dir, "public/assets/hwaro-search/search.css")).should eq(Hwaro::Content::SearchUi::CSS)
        html = File.read(File.join(dir, "public/a/index.html"))
        html.should contain(%(<script defer src="/assets/hwaro-search/search.js?v=))
        html.should_not contain("<script>")
      end
    end

    it "warns when it replaces a user file at the same path" do
      log = with_captured_log do
        build_site(UI_CONFIG, content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\nx\n"}, static_files: {"assets/hwaro-search/search.css" => "mine"}) do |dir|
          File.read(File.join(dir, "public/assets/hwaro-search/search.css")).should eq(Hwaro::Content::SearchUi::CSS)
        end
      end
      log.should contain("static/assets/hwaro-search/search.css is replaced by the built-in search UI")
      log.should_not contain("search.js is replaced")
    end

    it "warns about a replaced static file once per process" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "static/assets/hwaro-search"))
        File.write(File.join(dir, "static/assets/hwaro-search/search.js"), "mine")
        config = ui_config
        log = with_captured_log do
          3.times { Hwaro::Content::SearchUi.write_assets(config, File.join(dir, "public"), static_dir: File.join(dir, "static")) }
        end
        log.scan("search.js is replaced").size.should eq(1)
      end
    end

    it "hashes the emitted assets under [assets] sri" do
      build_site(UI_CONFIG + "\n[assets]\nsri = true\n", content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\nx\n"}, template_files: UI_TEMPLATE) do |dir|
        html = File.read(File.join(dir, "public/a/index.html"))
        html.should contain(%(integrity="#{Hwaro::Utils::DigestUtils.sri(Hwaro::Content::SearchUi::JS)}"))
      end
    end

    it "picks each page's language strings on a multilingual site" do
      config = UI_CONFIG + "\n[languages.ko]\nlanguage_name = \"Korean\"\n"
      build_site(config, content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\nx\n", "a.ko.md" => "+++\ntitle = \"가\"\n+++\nx\n"}, template_files: UI_TEMPLATE) do |dir|
        en = File.read(File.join(dir, "public/a/index.html"))
        ko = File.read(File.join(dir, "public/ko/a/index.html"))
        payload(en)["lang"].should eq("en")
        payload(ko)["lang"].should eq("ko")
      end
    end

    it "renders search_tags as empty and writes nothing while the UI is off" do
      build_site(UI_CONFIG.sub("ui = true", ""), content_files: {"a.md" => "+++\ntitle = \"A\"\n+++\nx\n"}, template_files: UI_TEMPLATE) do |dir|
        File.read(File.join(dir, "public/a/index.html")).should start_with("<head></head>")
        Dir.exists?(File.join(dir, "public/assets/hwaro-search")).should be_false
      end
    end
  end
end
