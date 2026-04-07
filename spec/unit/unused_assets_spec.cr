require "../spec_helper"

describe Hwaro::Services::UnusedAssets do
  describe "#run" do
    it "returns empty result when no directories exist" do
      service = Hwaro::Services::UnusedAssets.new(
        content_dir: "/nonexistent/content",
        static_dir: "/nonexistent/static",
      )
      result = service.run
      result.total_assets.should eq(0)
      result.unused_count.should eq(0)
    end

    it "detects unused static assets" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        # Create assets
        File.write(File.join(static_dir, "used.png"), "png data")
        File.write(File.join(static_dir, "unused.png"), "png data")

        # Content references only used.png
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\n![Image](used.png)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(2)
        result.referenced_count.should eq(1)
        result.unused_count.should eq(1)
        result.unused_files.should contain(File.join(static_dir, "unused.png"))
      end
    end

    it "counts template references" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        templates_dir = File.join(dir, "templates")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(templates_dir)

        File.write(File.join(static_dir, "logo.svg"), "svg data")
        File.write(File.join(templates_dir, "base.html"), "<img src=\"logo.svg\">")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: templates_dir)
        result = service.run

        result.referenced_count.should eq(1)
        result.unused_count.should eq(0)
      end
    end

    it "detects co-located content assets" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        post_dir = File.join(content_dir, "my-post")
        FileUtils.mkdir_p(post_dir)

        File.write(File.join(post_dir, "index.md"), "---\ntitle: Post\n---\n\n![Image](photo.jpg)\n")
        File.write(File.join(post_dir, "photo.jpg"), "jpg data")
        File.write(File.join(post_dir, "unused.jpg"), "jpg data")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: File.join(dir, "static"), templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(2)
        result.unused_count.should eq(1)
        result.unused_files.any? { |f| f.ends_with?("unused.jpg") }.should be_true
      end
    end

    it "all assets referenced returns zero unused" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "image.png"), "png data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\n![Pic](image.png)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.unused_count.should eq(0)
        result.unused_files.should be_empty
      end
    end

    it "serializes to JSON" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "orphan.css"), "body {}")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run
        json = JSON.parse(result.to_json)

        json["total_assets"].as_i.should eq(1)
        json["unused_count"].as_i.should eq(1)
      end
    end

    it "ignores non-asset file extensions" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "data.json"), "{}")
        File.write(File.join(static_dir, "notes.txt"), "notes")
        File.write(File.join(static_dir, "real.png"), "png")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(1)
      end
    end

    it "handles nested static directories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        nested = File.join(static_dir, "images", "photos")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(nested)

        File.write(File.join(nested, "deep.jpg"), "jpg data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\n\n![](deep.jpg)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(1)
        result.referenced_count.should eq(1)
      end
    end

    it "handles filenames with multiple dots" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "app.min.js"), "js code")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\n\n<script src=\"app.min.js\"></script>\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.referenced_count.should eq(1)
        result.unused_count.should eq(0)
      end
    end

    it "handles recursive template directories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        templates_dir = File.join(dir, "templates")
        partials = File.join(templates_dir, "partials")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(partials)

        File.write(File.join(static_dir, "icon.svg"), "svg")
        File.write(File.join(partials, "header.html"), "<img src=\"icon.svg\">")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: templates_dir)
        result = service.run

        result.referenced_count.should eq(1)
      end
    end

    it "delete_unused removes files" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(static_dir)

        path1 = File.join(static_dir, "old.png")
        path2 = File.join(static_dir, "stale.css")
        File.write(path1, "data")
        File.write(path2, "data")

        service = Hwaro::Services::UnusedAssets.new(content_dir: File.join(dir, "content"), static_dir: static_dir)
        service.delete_unused([path1, path2])

        File.exists?(path1).should be_false
        File.exists?(path2).should be_false
      end
    end

    it "delete_unused skips already-deleted files" do
      Dir.mktmpdir do |dir|
        service = Hwaro::Services::UnusedAssets.new(content_dir: File.join(dir, "content"), static_dir: File.join(dir, "static"))
        # Should not raise
        service.delete_unused([File.join(dir, "nonexistent.png")])
      end
    end

    it "handles uppercase file extensions" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "PHOTO.JPG"), "jpg data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\n\n![](PHOTO.JPG)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(1)
        result.referenced_count.should eq(1)
      end
    end
  end
end
