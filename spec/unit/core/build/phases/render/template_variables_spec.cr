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

describe "resize_image with a page-bundle image" do
  # `resize_image(path=page.image)` with `image = "cover.png"` beside
  # index.md resolves under the page URL, like its og:image does.
  it "resolves a relative path against the current page's bundle" do
    build_site(
      "title = \"T\"\nbase_url = \"https://ex.com\"\n",
      content_files: {
        "posts/b2/index.md"      => "+++\ntitle = \"B\"\nimage = \"cover.png\"\n+++\n",
        "posts/b2/cover.png"     => "png",
        "posts/b3/index.md"      => "+++\ntitle = \"B3\"\nimage = \"cover.png\"\n+++\n",
        "posts/b3/img/cover.png" => "png",
        "posts/flat.md"          => "+++\ntitle = \"F\"\nimage = \"logo.png\"\n+++\n",
      },
      template_files: {
        "page.html" => "{{ resize_image(path=page.image, width=300).url }}",
      },
    ) do
      File.read("public/posts/b2/index.html").should eq("https://ex.com/posts/b2/cover.png")
      # Only the bundle's own file of that name, not one in a subdirectory.
      File.read("public/posts/b3/index.html").should eq("https://ex.com/cover.png")
      # Not a bundle file: still read from the site root, as before.
      File.read("public/posts/flat/index.html").should eq("https://ex.com/logo.png")
    end
  end
end

describe "section.subsections" do
  # Documented as Array<Section>, but each entry was a four-key stub
  # (title/description/url/pages_count), so a nested nav looping
  # `sub.pages` rendered nothing.
  it "exposes each subsection's pages, name and own subsections" do
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\n",
      content_files: {
        "docs/_index.md"            => "+++\ntitle = \"Docs\"\n+++\n",
        "docs/guide/_index.md"      => "+++\ntitle = \"Guide\"\n+++\n",
        "docs/guide/a.md"           => "+++\ntitle = \"A\"\n+++\n",
        "docs/guide/deep/_index.md" => "+++\ntitle = \"Deep\"\n+++\n",
      },
      template_files: {
        "page.html"    => "P",
        "section.html" => "{% for s in section.subsections %}[{{ s.title }}:{{ s.name }}:{{ s.pages | map(attribute=\"title\") | join(\",\") }}:{{ s.subsections | map(attribute=\"title\") | join(\",\") }}]{% endfor %}",
      },
    ) do
      File.read("public/docs/index.html").should eq("[Guide:docs/guide:A,Deep:Deep]")
    end
  end
end
