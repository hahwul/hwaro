require "../../spec_helper"
require "../../support/build_helper"

# Slug collisions (`-2`) are resolved among the terms of ONE language's
# listing: a tag used only by pages of another language writes no page in
# this one, so it must not claim the base slug — and a language's term URLs
# must not move when another language adds a case-variant tag.
private MULTILINGUAL_CONFIG = <<-TOML
  title = "T"
  base_url = "http://localhost"
  default_language = "en"

  [languages.en]
  language_name = "English"

  [languages.ko]
  language_name = "Korean"
  taxonomies = ["tags"]

  [[taxonomies]]
  name = "tags"
  TOML

private def tagged(title : String, tag : String) : String
  "+++\ntitle = \"#{title}\"\ntags = [\"#{tag}\"]\n+++\nbody"
end

private TAG_URL_TEMPLATES = {
  "page.html"          => %(LINK={{ get_taxonomy_url(kind="tags", term=page.tags[0]) }}),
  "taxonomy.html"      => "{{ content }}",
  "taxonomy_term.html" => "{{ content }}",
}

describe "taxonomy term slugs on a multilingual site" do
  it "keeps the default language's term at the base slug when another language adds a case variant" do
    build_site(MULTILINGUAL_CONFIG,
      content_files: {"e.md" => tagged("E", "x y"), "k1.ko.md" => tagged("K", "X Y")},
      template_files: TAG_URL_TEMPLATES) do |dir|
      File.exists?(File.join(dir, "public/tags/x-y/index.html")).should be_true
      File.exists?(File.join(dir, "public/tags/x-y-2/index.html")).should be_false
      File.exists?(File.join(dir, "public/ko/tags/x-y/index.html")).should be_true
      File.read(File.join(dir, "public/e/index.html")).should contain("LINK=http://localhost/tags/x-y/")
      File.read(File.join(dir, "public/ko/k1/index.html")).should contain("LINK=http://localhost/ko/tags/x-y/")
    end
  end

  it "keeps the other language's term at the base slug when the default language's variant sorts first" do
    build_site(MULTILINGUAL_CONFIG,
      content_files: {"e.md" => tagged("E", "X Y"), "k1.ko.md" => tagged("K", "x y")},
      template_files: TAG_URL_TEMPLATES) do |dir|
      File.exists?(File.join(dir, "public/tags/x-y/index.html")).should be_true
      File.exists?(File.join(dir, "public/ko/tags/x-y/index.html")).should be_true
      File.exists?(File.join(dir, "public/ko/tags/x-y-2/index.html")).should be_false
      File.read(File.join(dir, "public/ko/k1/index.html")).should contain("LINK=http://localhost/ko/tags/x-y/")
    end
  end

  it "still suffixes colliding terms inside one language" do
    build_site(MULTILINGUAL_CONFIG,
      content_files: {"e.md" => tagged("E", "X Y"), "e2.md" => tagged("E2", "x y")},
      template_files: TAG_URL_TEMPLATES) do |dir|
      File.exists?(File.join(dir, "public/tags/x-y/index.html")).should be_true
      File.exists?(File.join(dir, "public/tags/x-y-2/index.html")).should be_true
    end
  end
end
