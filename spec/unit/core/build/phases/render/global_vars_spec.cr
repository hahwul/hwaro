require "../../../../../support/build_helper"

describe "Render global vars: bundle asset URLs" do
  # Regression: `get_url(path=asset)` with a `page.assets` entry pointed at
  # the content path, which a slug moves the page (and the copied asset)
  # away from — and which is never published without [content.files].
  it "resolves get_url(path=asset) to the copy next to a slugged page" do
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\n",
      content_files: {
        "posts/my-post/index.md" => "+++\ntitle = \"P\"\nslug = \"renamed\"\n+++\nBody",
        "posts/my-post/i.png"    => "png",
      },
      template_files: {
        "page.html" => "{% for a in page.assets %}[{{ get_url(path=a) }}]{% endfor %}[{{ get_url(path='/about/') }}]",
      },
    ) do
      File.exists?("public/posts/renamed/i.png").should be_true
      html = File.read("public/posts/renamed/index.html")
      html.should contain("[http://localhost/posts/renamed/i.png]")
      html.should contain("[http://localhost/about/]")
    end
  end

  it "resolves resize_image(path=asset) to the copy next to a slugged page" do
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\n",
      content_files: {
        "posts/my-post/index.md" => "+++\ntitle = \"P\"\nslug = \"renamed\"\n+++\nBody",
        "posts/my-post/i.png"    => "png",
      },
      template_files: {
        "page.html" => "{% for a in page.assets %}[{{ resize_image(path=a, width=64).url }}]{% endfor %}",
      },
    ) do
      File.read("public/posts/renamed/index.html").should eq("[http://localhost/posts/renamed/i.png]")
    end
  end
end

# `@/` links already reached a decomposed (NFD) file name from a precomposed
# path; get_page/get_section missed it, so the same site resolved one and not
# the other.
describe "Render global vars: Unicode-normalized lookups" do
  it "finds a decomposed page and section from a precomposed path, and back" do
    nfd = "café".unicode_normalize(:nfd)
    nfc = "café".unicode_normalize(:nfc)
    build_site(
      "title = \"T\"\nbase_url = \"http://localhost\"\n",
      content_files: {
        "index.md"         => "+++\ntitle = \"Home\"\ntemplate = \"probe\"\n+++\n",
        "#{nfd}/_index.md" => "+++\ntitle = \"Sec\"\n+++\n",
        "#{nfd}/#{nfd}.md" => "+++\ntitle = \"Dec\"\n+++\n",
        "posts/#{nfc}.md"  => "+++\ntitle = \"Pre\"\n+++\n",
      },
      template_files: {
        "probe.html" => "[{{ get_page(path='#{nfc}/#{nfc}.md').title }}][{{ get_section(path='#{nfc}').title }}][{{ get_page(path='posts/#{nfd}.md').title }}]",
      },
    ) do
      File.read("public/index.html").should eq("[Dec][Sec][Pre]")
    end
  end
end
