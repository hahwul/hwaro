require "../../../../../support/build_helper"

# Authored pages whose output collides with a GENERATED path: a paginator's
# `/page/N/`, a taxonomy page, or a generated file such as sitemap.xml.
describe "Render output paths: authored vs generated collisions" do
  it "keeps an authored page over a colliding paginator page, with a warning" do
    log = with_captured_log do
      build_site(
        "title = \"T\"\nbase_url = \"http://localhost\"\n\n[pagination]\nenabled = true\nper_page = 1\n",
        content_files: {
          "blog/_index.md" => "+++\ntitle = \"Blog\"\n+++\n",
          "blog/p1.md"     => "+++\ntitle = \"P1\"\n+++\nP1",
          "blog/p2.md"     => "+++\ntitle = \"P2\"\n+++\nP2",
          "blog/page/2.md" => "+++\ntitle = \"Authored\"\n+++\nAUTHORED-PAGE-2",
        },
        template_files: {
          "page.html"    => "{{ content }}",
          "section.html" => "PAGE={{ paginator.current_index }}",
        },
        parallel: true,
      ) do
        File.read("public/blog/page/2/index.html").should contain("AUTHORED-PAGE-2")
      end
    end
    log.should contain("content page 'blog/page/2.md' publishes the same path")
  end

  it "keeps an authored page over a colliding taxonomy term page, with a warning" do
    log = with_captured_log do
      build_site(
        "title = \"T\"\nbase_url = \"http://localhost\"\n\n[[taxonomies]]\nname = \"tags\"\n",
        content_files: {
          "post.md" => "+++\ntitle = \"Post\"\ntags = [\"c\"]\n+++\nPost",
          "tc.md"   => "+++\ntitle = \"TagC\"\npath = \"tags/c\"\n+++\nAUTHORED-TAG",
        },
        template_files: {
          "page.html"          => "{{ content }}",
          "taxonomy.html"      => "TAXONOMY",
          "taxonomy_term.html" => "TERM={{ taxonomy_term }}",
        },
      ) do
        File.read("public/tags/c/index.html").should contain("AUTHORED-TAG")
        File.read("public/tags/index.html").should contain("TAXONOMY")
      end
    end
    log.should contain("content page 'tc.md' publishes the same path")
  end

  it "fails with a classified I/O error when a page's slug shadows sitemap.xml" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        "title = \"T\"\nbase_url = \"http://localhost\"\n\n[sitemap]\nenabled = true\n",
        content_files: {"sm.md" => "+++\ntitle = \"SM\"\nslug = \"sitemap.xml\"\n+++\nx"},
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_IO)
    err.message.to_s.should contain("a directory already exists at that path")
  end
end
