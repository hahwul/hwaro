require "../support/build_helper"

MULTILINGUAL_LISTING_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"
  default_language = "en"

  [languages.en]
  language_name = "English"

  [languages.ko]
  language_name = "Korean"
  TOML

# Regression: a page spelling out the default-language suffix (`b.en.md`)
# was read with language "en" while unsuffixed siblings carry nil, and section
# listings compare languages exactly — so it vanished from `section.pages`
# (and a suffixed `_index.en.md` listed none of its unsuffixed pages).
describe "Multilingual: explicit default-language suffix" do
  it "lists default-suffixed pages alongside unsuffixed ones" do
    build_site(
      MULTILINGUAL_LISTING_CONFIG,
      content_files: {
        "posts/_index.md"    => "+++\ntitle = \"Posts\"\n+++\n",
        "posts/a.md"         => "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n",
        "posts/b.en.md"      => "+++\ntitle = \"B\"\ndate = 2024-01-02\n+++\n",
        "posts/b.ko.md"      => "+++\ntitle = \"B KO\"\ndate = 2024-01-02\n+++\n",
        "notes/_index.en.md" => "+++\ntitle = \"Notes\"\n+++\n",
        "notes/n.md"         => "+++\ntitle = \"N\"\n+++\n",
      },
      template_files: {
        "page.html"    => "{{ page.url }}|{% for t in page.translations %}{{ t.code }}={{ t.url }};{% endfor %}",
        "section.html" => "{% for p in section.pages %}[{{ p.title }} {{ p.url }}]{% endfor %}",
      },
    ) do
      File.read("public/posts/index.html").should eq("[B /posts/b/][A /posts/a/]")
      File.read("public/notes/index.html").should eq("[N /notes/n/]")
      File.read("public/posts/b/index.html").should eq("/posts/b/|en=/posts/b/;ko=/ko/posts/b/;")
      File.exists?("public/posts/b.en/index.html").should be_false
    end
  end
end
