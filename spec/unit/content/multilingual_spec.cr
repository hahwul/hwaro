require "../../spec_helper"
require "../../support/build_helper"
require "file_utils"

describe Hwaro::Content::Multilingual do
  it "links translation variants on pages" do
    config = Hwaro::Models::Config.new
    config.default_language = "en"
    config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

    en = Hwaro::Models::Page.new("about/index.md")
    en.title = "About"
    en.url = "/about/"

    ko = Hwaro::Models::Page.new("about/index.ko.md")
    ko.title = "소개"
    ko.url = "/ko/about/"
    ko.language = "ko"

    Hwaro::Content::Multilingual.link_translations!([en, ko], config)

    en.translations.map(&.code).should eq(["en", "ko"])
    en.translations.find!(&.is_current).code.should eq("en")
    ko.translations.find!(&.is_current).code.should eq("ko")
    ko.translations.map(&.url).should eq(["/about/", "/ko/about/"])
  end

  it "does not link translations that are never written or only redirect" do
    config = Hwaro::Models::Config.new
    config.default_language = "en"
    config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
    config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")

    en = Hwaro::Models::Page.new("about.md")
    en.url = "/about/"
    ko = Hwaro::Models::Page.new("about.ko.md")
    ko.url = "/ko/about/"
    ko.language = "ko"
    ko.render = false
    ja = Hwaro::Models::Page.new("about.ja.md")
    ja.url = "/ja/about/"
    ja.language = "ja"
    ja.redirect_to = "https://elsewhere.example/"

    Hwaro::Content::Multilingual.link_translations!([en, ko, ja], config)

    # Only the page itself is left, so there is nothing to switch to.
    en.translations.should be_empty
  end

  it "links translation variants on .markdown pages" do
    config = Hwaro::Models::Config.new
    config.default_language = "en"
    config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

    en = Hwaro::Models::Page.new("about.markdown")
    en.title = "About"
    en.url = "/about/"

    ko = Hwaro::Models::Page.new("about.ko.markdown")
    ko.title = "소개"
    ko.url = "/ko/about/"
    ko.language = "ko"

    Hwaro::Content::Multilingual.link_translations!([en, ko], config)

    en.translations.map(&.code).should eq(["en", "ko"])
    ko.translations.map(&.code).should eq(["en", "ko"])
    ko.translations.map(&.url).should eq(["/about/", "/ko/about/"])
  end

  # Regression for https://github.com/hahwul/hwaro/issues/486
  # `link_translations!` used to populate `page.translations` with a
  # single self-entry for pages that have no actual cross-language
  # variants. The canonical guard from docs/templates/data-model.md —
  # `{% if page.translations %}<nav class="lang-switcher">…</nav>{% endif %}` —
  # therefore always rendered an empty (or current-only) switcher on
  # single-language pages.
  it "leaves page.translations empty when no cross-language variant exists" do
    config = Hwaro::Models::Config.new
    config.default_language = "en"
    config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

    only_en = Hwaro::Models::Page.new("solo.md")
    only_en.title = "Solo"
    only_en.url = "/solo/"

    Hwaro::Content::Multilingual.link_translations!([only_en], config)

    only_en.translations.should be_empty
  end

  it "builds /<lang>/ prefixed URLs for nested index.<lang>.md files" do
    temp_dir = File.tempname("hwaro_multilingual")
    Dir.mkdir(temp_dir)

    begin
      Dir.cd(temp_dir) do
        Dir.mkdir_p("content/about")
        File.write("content/about/index.md", <<-MD)
          +++
          title = "About"
          +++

          # About
          MD
        File.write("content/about/index.ko.md", <<-MD)
          +++
          title = "소개"
          +++

          # 소개
          MD

        File.write("config.toml", <<-TOML)
          title = "Test"
          base_url = "http://localhost:3000"
          default_language = "en"

          [languages.ko]
          language_name = "한국어"
          weight = 2
          TOML

        builder = Hwaro::Core::Build::Builder.new
        builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", drafts: false, minify: false, parallel: false, cache: false, highlight: true, verbose: false, profile: false))

        File.exists?("public/about/index.html").should be_true
        File.exists?("public/ko/about/index.html").should be_true
      end
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end
end

private def key_config : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.default_language = "en"
  config.languages["en"] = Hwaro::Models::LanguageConfig.new("en")
  config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
  config
end

private def keyed_page(path : String, url : String, key : String? = nil, language : String? = nil) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.url = url
  page.title = path
  page.language = language
  page.translation_key = key
  page
end

private KEY_SITE_CONFIG = <<-TOML
  title = "T"
  base_url = "https://example.com"
  default_language = "en"
  [languages.en]
  language_name = "English"
  [languages.ko]
  language_name = "Korean"
  [sitemap]
  enabled = true
  TOML

private KEY_TEMPLATE = "{% for t in page.translations %}[{{ t.code }} {{ t.url }}]{% endfor %}|{{ hreflang_tags }}"

describe "Hwaro::Content::Multilingual translation_key" do
  it "links pages that share a key whatever their file names" do
    en = keyed_page("about.md", "/about/", "about")
    ko = keyed_page("소개.ko.md", "/ko/소개/", "about", "ko")
    Hwaro::Content::Multilingual.link_translations!([en, ko], key_config).should be_empty
    en.translations.map { |t| {t.code, t.url, t.is_current} }.should eq([{"en", "/about/", true}, {"ko", "/ko/소개/", false}])
    ko.translations.map { |t| {t.code, t.url, t.is_current} }.should eq([{"en", "/about/", false}, {"ko", "/ko/소개/", true}])
  end

  it "takes a keyed page out of its file-name group instead of merging the two" do
    en = keyed_page("about.md", "/about/", "intro")
    ko = keyed_page("about.ko.md", "/ko/about/", language: "ko")
    Hwaro::Content::Multilingual.link_translations!([en, ko], key_config)
    en.translations.should be_empty
    ko.translations.should be_empty
  end

  it "keeps file-name grouping for pages without a key" do
    en = keyed_page("a.md", "/a/")
    ko = keyed_page("a.ko.md", "/ko/a/", language: "ko")
    # A key spelled like a file-name group id does not join that group.
    other = keyed_page("b.ko.md", "/ko/b/", "a.md", "ko")
    Hwaro::Content::Multilingual.link_translations!([en, ko, other], key_config)
    en.translations.map(&.url).should eq(["/a/", "/ko/a/"])
    other.translations.should be_empty
  end

  it "scopes a key to the page's version" do
    pages = {"v1", "v2"}.to_a.flat_map do |name|
      version = Hwaro::Models::VersionConfig.new(name, path: "docs/#{name}")
      en = keyed_page("docs/#{name}/about.md", "/docs/#{name}/about/", "about")
      ko = keyed_page("docs/#{name}/소개.ko.md", "/ko/docs/#{name}/소개/", "about", "ko")
      en.version = version
      ko.version = version
      [en, ko]
    end
    Hwaro::Content::Multilingual.link_translations!(pages, key_config).should be_empty
    pages[0].translations.map(&.url).should eq(["/docs/v1/about/", "/ko/docs/v1/소개/"])
    pages[2].translations.map(&.url).should eq(["/docs/v2/about/", "/ko/docs/v2/소개/"])
  end

  it "resolves two same-language pages with one key by path, whatever the input order" do
    [false, true].each do |reverse|
      en = keyed_page("about.md", "/about/", "about")
      b = keyed_page("b.ko.md", "/ko/b/", "about", "ko")
      a = keyed_page("a.ko.md", "/ko/a/", "about", "ko")
      pages = [en, b, a]
      pages.reverse! if reverse
      collisions = Hwaro::Content::Multilingual.link_translations!(pages, key_config)
      collisions.map { |c| {c.key, c.code, c.winner.path, c.loser.path} }.should eq([{"about", "ko", "a.ko.md", "b.ko.md"}])
      en.translations.map(&.url).should eq(["/about/", "/ko/a/"])
      a.translations.map(&.url).should eq(["/about/", "/ko/a/"])
      b.translations.should be_empty
    end
  end

  it "prefers a linkable page over a headless or redirecting one in a collision" do
    en = keyed_page("about.md", "/about/", "about")
    headless = keyed_page("a.ko.md", "/ko/a/", "about", "ko")
    headless.render = false
    redirect = keyed_page("b.ko.md", "/ko/b/", "about", "ko")
    redirect.redirect_to = "/elsewhere/"
    real = keyed_page("c.ko.md", "/ko/c/", "about", "ko")
    collisions = Hwaro::Content::Multilingual.link_translations!([en, headless, redirect, real], key_config)
    collisions.map { |c| {c.winner.path, c.loser.path} }.should eq([{"c.ko.md", "a.ko.md"}, {"c.ko.md", "b.ko.md"}])
    en.translations.map(&.url).should eq(["/about/", "/ko/c/"])
    real.translations.map(&.url).should eq(["/about/", "/ko/c/"])
  end

  it "does nothing on a single-language site" do
    page = keyed_page("about.md", "/about/", "about")
    Hwaro::Content::Multilingual.link_translations!([page], Hwaro::Models::Config.new).should be_empty
    page.translations.should be_empty
  end

  it "links keyed pages in a build: switcher, hreflang and sitemap alternates" do
    build_site(KEY_SITE_CONFIG,
      content_files: {
        "about.md"    => "+++\ntitle = \"About\"\ntranslation_key = \"about\"\n+++\n",
        "intro.ko.md" => "---\ntitle: 소개\ntranslation_key: about\n---\n",
        "plain.md"    => "+++\ntitle = \"Plain\"\n+++\n",
        "plain.ko.md" => "+++\ntitle = \"Plain ko\"\n+++\n",
        "loner.md"    => %({"title": "Loner", "translation_key": "solo"}\n),
      },
      template_files: {"page.html" => KEY_TEMPLATE, "section.html" => "", "index.html" => ""}) do
      about = File.read("public/about/index.html")
      about.should start_with("[en /about/][ko /ko/intro/]|")
      about.should contain(%(hreflang="ko" href="https://example.com/ko/intro/"))
      File.read("public/ko/intro/index.html").should start_with("[en /about/][ko /ko/intro/]|")
      File.read("public/plain/index.html").should start_with("[en /plain/][ko /ko/plain/]|")
      File.read("public/loner/index.html").should eq("|")
      File.read("public/sitemap.xml").should contain(%(hreflang="ko" href="https://example.com/ko/intro/"))
    end
  end

  it "warns about a same-language key collision in a build" do
    log = with_captured_log do
      build_site(KEY_SITE_CONFIG,
        content_files: {
          "about.md" => "+++\ntitle = \"About\"\ntranslation_key = \"about\"\n+++\n",
          "a.ko.md"  => "+++\ntitle = \"A\"\ntranslation_key = \"about\"\n+++\n",
          "b.ko.md"  => "+++\ntitle = \"B\"\ntranslation_key = \"about\"\n+++\n",
        },
        template_files: {"page.html" => KEY_TEMPLATE, "section.html" => "", "index.html" => ""}) do
        File.read("public/about/index.html").should start_with("[en /about/][ko /ko/a/]|")
        File.read("public/ko/b/index.html").should eq("|")
      end
    end
    log.should contain(%(content/b.ko.md: translation_key "about" is already used by the 'ko' page content/a.ko.md))
  end

  it "re-links both the old and the new partners under --cache when a key moves" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", KEY_SITE_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", KEY_TEMPLATE)
        File.write("templates/section.html", "")
        File.write("templates/index.html", "")
        File.write("content/about.md", "+++\ntitle = \"About\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/old.ko.md", "+++\ntitle = \"Old\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/new.ko.md", "+++\ntitle = \"New\"\n+++\n")
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, highlight: false)
        Hwaro::Core::Build::Builder.new.run(options)
        File.read("public/about/index.html").should start_with("[en /about/][ko /ko/old/]|")

        File.write("content/old.ko.md", "+++\ntitle = \"Old\"\n+++\n")
        File.write("content/new.ko.md", "+++\ntitle = \"New\"\ntranslation_key = \"about\"\n+++\n")
        Hwaro::Core::Build::Builder.new.run(options)
        File.read("public/about/index.html").should start_with("[en /about/][ko /ko/new/]|")
        File.read("public/ko/new/index.html").should start_with("[en /about/][ko /ko/new/]|")
        File.read("public/ko/old/index.html").should eq("|")
      end
    end
  end
end
