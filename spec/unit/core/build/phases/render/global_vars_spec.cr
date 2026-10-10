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
