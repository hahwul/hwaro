require "../spec_helper"
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
    en.translations.find(&.is_current).not_nil!.code.should eq("en")
    ko.translations.find(&.is_current).not_nil!.code.should eq("ko")
    ko.translations.map(&.url).should eq(["/about/", "/ko/about/"])
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
        builder.run(output_dir: "public", drafts: false, minify: false, parallel: false, cache: false, highlight: true, verbose: false, profile: false)

        File.exists?("public/about/index.html").should be_true
        File.exists?("public/ko/about/index.html").should be_true
      end
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end
end
