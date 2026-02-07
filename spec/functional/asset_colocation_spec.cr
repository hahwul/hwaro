require "../spec_helper"

describe "Asset Colocation" do
  it "copies assets co-located with index.md (Page Bundle)" do
    Dir.mktmpdir do |dir|
      FileUtils.cd(dir) do
        # Setup basic structure
        FileUtils.mkdir_p("content/blog/my-post")
        File.write("config.toml", "base_url = 'http://example.com/'\ntitle = 'Test Site'")
        File.write("content/blog/my-post/index.md", "+++\ntitle = 'My Post'\n+++\nContent")
        File.write("content/blog/my-post/image.png", "dummy image content")

        # Build
        Hwaro::Core::Build::Builder.new.run(output_dir: "public")

        # Verify
        File.exists?("public/blog/my-post/index.html").should be_true
        File.exists?("public/blog/my-post/image.png").should be_true
        File.read("public/blog/my-post/image.png").should eq("dummy image content")
      end
    end
  end

  it "copies assets co-located with section _index.md (Section Bundle)" do
    Dir.mktmpdir do |dir|
      FileUtils.cd(dir) do
        # Setup basic structure
        FileUtils.mkdir_p("content/gallery")
        File.write("config.toml", "base_url = 'http://example.com/'\ntitle = 'Test Site'")
        File.write("content/gallery/_index.md", "+++\ntitle = 'Gallery'\n+++\nContent")
        File.write("content/gallery/logo.png", "dummy logo content")

        # Build
        Hwaro::Core::Build::Builder.new.run(output_dir: "public")

        # Verify
        File.exists?("public/gallery/index.html").should be_true
        File.exists?("public/gallery/logo.png").should be_true
        File.read("public/gallery/logo.png").should eq("dummy logo content")
      end
    end
  end

  it "copies nested assets recursively" do
    Dir.mktmpdir do |dir|
      FileUtils.cd(dir) do
        # Setup basic structure
        FileUtils.mkdir_p("content/project")
        FileUtils.mkdir_p("content/project/assets/css")
        File.write("config.toml", "base_url = 'http://example.com/'\ntitle = 'Test Site'")
        File.write("content/project/index.md", "+++\ntitle = 'Project'\n+++\nContent")
        File.write("content/project/assets/css/style.css", "body { color: red; }")

        # Build
        Hwaro::Core::Build::Builder.new.run(output_dir: "public")

        # Verify
        File.exists?("public/project/index.html").should be_true
        File.exists?("public/project/assets/css/style.css").should be_true
        File.read("public/project/assets/css/style.css").should eq("body { color: red; }")
      end
    end
  end

  it "does NOT copy assets for regular markdown files (not bundles)" do
    Dir.mktmpdir do |dir|
      FileUtils.cd(dir) do
        # Setup structure with a regular file and a sibling file
        FileUtils.mkdir_p("content/about")
        File.write("config.toml", "base_url = 'http://example.com/'\ntitle = 'Test Site'")
        # content/about.md is NOT a bundle
        File.write("content/about.md", "+++\ntitle = 'About'\n+++\nContent")
        # sibling file - should NOT be copied to public/about/sibling.txt
        File.write("content/sibling.txt", "sibling content")

        # Build
        Hwaro::Core::Build::Builder.new.run(output_dir: "public")

        # Verify page exists
        File.exists?("public/about/index.html").should be_true

        # Verify sibling asset was NOT copied to the page output
        File.exists?("public/about/sibling.txt").should be_false
      end
    end
  end
end
