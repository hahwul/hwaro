require "./support/build_helper"

# ---------------------------------------------------------------------------
# Regression tests for page.assets in templates (GitHub issue #224)
#
# page.assets items must be plain strings when iterated in templates,
# not Crinja callable objects.
# ---------------------------------------------------------------------------
describe "Build Integration: page.assets in templates" do
  it "iterates page.assets as strings in page templates" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "drawings/index.md"     => "---\ntitle: Drawings\n---\nGallery content",
        "drawings/images/1.jpg" => "fake-jpg-1",
        "drawings/images/2.jpg" => "fake-jpg-2",
      },
      template_files: {
        "page.html" => "{% for asset in page.assets -%}ASSET:{{ asset }}\n{% endfor -%}",
      },
    ) do
      html = File.read("public/drawings/index.html")
      html.should contain("ASSET:drawings/images/1.jpg")
      html.should contain("ASSET:drawings/images/2.jpg")
      html.should_not contain("unnamed_callable")
    end
  end

  it "allows matching filter on page.assets items" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "gallery/index.md"  => "---\ntitle: Gallery\n---\nContent",
        "gallery/photo.jpg" => "fake-jpg",
        "gallery/notes.txt" => "fake-txt",
      },
      template_files: {
        "page.html" => "{% for asset in page.assets -%}{%- if asset is matching(\"[.](jpg|png)$\") -%}IMG:{{ asset }}\n{%- endif %}{%- endfor -%}",
      },
    ) do
      html = File.read("public/gallery/index.html")
      html.should contain("IMG:gallery/photo.jpg")
      html.should_not contain("notes.txt")
    end
  end

  it "iterates section.assets as strings in section templates" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "photos/_index.md"  => "---\ntitle: Photos\n---\nSection content",
        "photos/banner.png" => "fake-png",
      },
      template_files: {
        "section.html" => "{% for asset in section.assets -%}SECT_ASSET:{{ asset }}\n{% endfor -%}",
        "page.html"    => "{{ content }}",
      },
    ) do
      html = File.read("public/photos/index.html")
      html.should contain("SECT_ASSET:photos/banner.png")
      html.should_not contain("unnamed_callable")
    end
  end
end
