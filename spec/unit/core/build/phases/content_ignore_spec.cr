require "../../../../spec_helper"
require "../../../../../src/core/build/builder"
require "../../../../support/build_helper"

# `[content] ignore` (#890): a matched path is invisible to the build — not a
# page, not a section, not a bundle asset, not a published content file.
private IGNORE_TEMPLATES = {
  "page.html"    => "{{ content }}",
  "section.html" => "{% for p in section.pages %}[{{ p.title }}]{% endfor %}",
}

private IGNORE_CONTENT = {
  "README.md"              => "# Read me\n",
  "_templates/note.md"     => "# {{title}}\n",
  "_templates/t.json"      => "{}",
  "blog/_index.md"         => "+++\ntitle = \"Blog\"\n+++\n",
  "blog/a.md"              => "+++\ntitle = \"A\"\n+++\n",
  "blog/b.excalidraw.md"   => "excalidraw",
  "blog/post/index.md"     => "+++\ntitle = \"Post\"\n+++\n",
  "blog/post/keep.png"     => "k",
  "blog/post/secret.png"   => "s",
  "data.json"              => "{}",
  "notes/_index.md"        => "+++\ntitle = \"Notes\"\n+++\n",
  "notes/n1.md"            => "+++\ntitle = \"N1\"\n+++\n",
  "files/private/doc.pdf"  => "pdf",
  "files/public/guide.pdf" => "pdf",
}

private def ignore_config(patterns : String) : String
  <<-TOML
    title = "t"
    base_url = "https://example.com"
    sitemap = true
    [content]
    ignore = #{patterns}
    [content.files]
    allow_extensions = ["pdf", "png"]
    TOML
end

describe "[content] ignore in the build" do
  it "publishes none of the ignored pages, sections, assets or content files" do
    patterns = %(["README.md", "_templates", "**/*.excalidraw.md", "blog/post/secret.png", "notes/_index.md", "files/private/**"])
    build_site(ignore_config(patterns), content_files: IGNORE_CONTENT, template_files: IGNORE_TEMPLATES) do
      File.exists?("public/README/index.html").should be_false
      Dir.exists?("public/_templates").should be_false
      File.exists?("public/blog/b.excalidraw/index.html").should be_false
      File.exists?("public/blog/post/secret.png").should be_false
      File.exists?("public/notes/index.html").should be_false
      File.exists?("public/files/private/doc.pdf").should be_false

      # Everything else is untouched.
      File.read("public/blog/index.html").should contain("[A]")
      File.read("public/blog/index.html").should_not contain("excalidraw")
      File.exists?("public/blog/post/index.html").should be_true
      File.exists?("public/blog/post/keep.png").should be_true
      File.exists?("public/data.json").should be_true
      File.exists?("public/files/public/guide.pdf").should be_true
      # A page whose `_index.md` is ignored still builds, as in a directory
      # that never had one.
      File.exists?("public/notes/n1/index.html").should be_true

      sitemap = File.read("public/sitemap.xml")
      sitemap.should_not contain("README")
      sitemap.should_not contain("_templates")
      sitemap.should_not contain("/notes/<")
    end
  end

  it "treats an ignored nested index as no bundle, so its files stay the parent's" do
    content = {
      "gallery/index.md"     => "+++\ntitle = \"G\"\n+++\n",
      "gallery/sub/index.md" => "+++\ntitle = \"Sub\"\n+++\n",
      "gallery/sub/pic.png"  => "p",
    }
    # No [content.files] here: the raw lane would publish pic.png on its own
    # and hide whether the bundle took it.
    config = %(title = "t"\nbase_url = "https://example.com"\n[content]\nignore = ["gallery/sub/index.md"]\n)
    build_site(config, content_files: content, template_files: IGNORE_TEMPLATES) do |_, builder|
      File.exists?("public/gallery/sub/index.html").should be_false
      File.exists?("public/gallery/sub/pic.png").should be_true
      gallery = builder.site.not_nil!.pages.find! { |p| p.path == "gallery/index.md" }
      gallery.assets.should eq(["gallery/sub/pic.png"])
    end
  end

  it "lets a [[content.generate]] page take a path only an ignored file claims" do
    config = <<-TOML
      title = "t"
      base_url = "https://example.com"
      [content]
      ignore = ["items/a.md"]
      [[content.generate]]
      source = "items"
      section = "items"
      slug = "slug"
      title = "title"
      TOML
    content = {"items/a.md" => "+++\ntitle = \"Authored\"\n+++\n"}
    build_site(config, content_files: content, template_files: {"page.html" => "{{ page.title }}"}, data_files: {"items.json" => %([{"slug": "a", "title": "Generated"}])}) do
      File.read("public/items/a/index.html").should eq("Generated")
    end
  end

  it "keeps a page under a folder named content/ that a root pattern does not name" do
    content = {"x.md" => "+++\ntitle = \"Root\"\n+++\n", "content/x.md" => "+++\ntitle = \"Nested\"\n+++\n"}
    build_site(ignore_config(%(["x.md"])), content_files: content, template_files: IGNORE_TEMPLATES) do
      File.exists?("public/x/index.html").should be_false
      File.exists?("public/content/x/index.html").should be_true
    end
  end

  it "builds byte-identically when the key is unset" do
    plain = %(title = "t"\nbase_url = "https://example.com"\n[content.files]\nallow_extensions = ["pdf", "png"]\n)
    build_site(plain, content_files: IGNORE_CONTENT, template_files: IGNORE_TEMPLATES) do
      File.exists?("public/README/index.html").should be_true
      File.exists?("public/_templates/note/index.html").should be_true
      File.exists?("public/blog/post/secret.png").should be_true
      File.exists?("public/files/private/doc.pdf").should be_true
    end
  end

  it "removes a page's output under --cache once it becomes ignored" do
    content = {"README.md" => "# R\n", "_templates/t.json" => "{}", "b/index.md" => "+++\ntitle = \"B\"\n+++\n", "b/s.png" => "s"}
    plain = %(title = "t"\nbase_url = "https://example.com"\n)
    build_site(plain, content_files: content, template_files: IGNORE_TEMPLATES, cache: true) do |_, builder|
      File.exists?("public/README/index.html").should be_true
      File.exists?("public/_templates/t.json").should be_true
      File.exists?("public/b/s.png").should be_true

      File.write("config.toml", plain + %([content]\nignore = ["README.md", "_templates/", "b/s.png"]\n))
      builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true)).should be_true

      File.exists?("public/README/index.html").should be_false
      File.exists?("public/_templates/t.json").should be_false
      File.exists?("public/b/s.png").should be_false
      File.exists?("public/b/index.html").should be_true
    end
  end
end
