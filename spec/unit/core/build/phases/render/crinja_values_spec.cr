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
