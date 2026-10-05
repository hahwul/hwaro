require "../../../../../spec_helper"
require "../../../../../support/build_helper"

describe "page.is_section" do
  # A page bundle's `index.md` is `is_index` like a section's `_index.md`;
  # `is_section` is what lets a listing drop subsection entries but keep
  # bundle posts.
  it "is true for subsection entries and false for page bundles" do
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\n",
      content_files: {
        "s/_index.md"       => "+++\ntitle = \"S\"\n+++\n",
        "s/sub/_index.md"   => "+++\ntitle = \"Sub\"\n+++\n",
        "s/bundle/index.md" => "+++\ntitle = \"Bundle\"\n+++\n",
        "s/flat.md"         => "+++\ntitle = \"Flat\"\n+++\n",
      },
      template_files: {
        "page.html"    => "{{ page.is_section }}",
        "section.html" => "{% for p in section.pages | sort(attribute=\"title\") %}[{{ p.title }}:{{ p.is_index }}:{{ p.is_section }}]{% endfor %}",
      },
    ) do
      File.read("public/s/index.html").should eq("[Bundle:true:false][Flat:false:false][Sub:true:true]")
      File.read("public/s/bundle/index.html").should eq("false")
    end
  end
end

describe "hreflang on paginated listings" do
  # The alternates name the translations' first pages; a page/2/ that
  # canonicalizes to itself must not claim page 1 as its own hreflang URL.
  it "emits alternates on page 1 only" do
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\ndefault_language = \"en\"\n\n[languages.en]\nlanguage_name = \"English\"\n\n[languages.ko]\nlanguage_name = \"한국어\"\n",
      content_files: {
        "posts/_index.md"    => "+++\ntitle = \"Posts\"\npaginate = 1\n+++\n",
        "posts/_index.ko.md" => "+++\ntitle = \"글\"\npaginate = 1\n+++\n",
        "posts/a.md"         => "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n",
        "posts/b.md"         => "+++\ntitle = \"B\"\ndate = 2024-01-02\n+++\n",
      },
      template_files: {
        "page.html"    => "P",
        "section.html" => "{{ hreflang_tags }}",
      },
    ) do
      File.read("public/posts/index.html").should contain(%(hreflang="ko"))
      File.read("public/posts/page/2/index.html").should_not contain("hreflang")
    end
  end
end
