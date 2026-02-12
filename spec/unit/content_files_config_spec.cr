require "../spec_helper"

describe Hwaro::Models::ContentFilesConfig do
  describe "#initialize" do
    it "has default empty arrays" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions.should eq([] of String)
      config.disallow_extensions.should eq([] of String)
      config.disallow_paths.should eq([] of String)
    end
  end

  describe "#enabled?" do
    it "returns false when allow_extensions is empty" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.enabled?.should be_false
    end

    it "returns true when allow_extensions has entries" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg", ".png"]
      config.enabled?.should be_true
    end

    it "returns true with a single extension" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".pdf"]
      config.enabled?.should be_true
    end
  end

  describe "#publish?" do
    it "returns false when extension is empty" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg"]
      config.publish?("no_extension").should be_false
    end

    it "returns false for .md files regardless of allow list" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".md", ".jpg"]
      config.publish?("blog/post.md").should be_false
    end

    it "returns false when extension is not in allow list" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg", ".png"]
      config.publish?("blog/file.gif").should be_false
    end

    it "returns true when extension is in allow list" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg", ".png", ".gif"]
      config.publish?("blog/image.jpg").should be_true
    end

    it "returns false when extension is in disallow list" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg", ".png", ".bak"]
      config.disallow_extensions = [".bak"]
      config.publish?("blog/backup.bak").should be_false
    end

    it "returns false when path matches disallow pattern" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg"]
      config.disallow_paths = ["private/*"]
      config.publish?("private/secret.jpg").should be_false
    end

    it "returns true when path does not match disallow pattern" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg"]
      config.disallow_paths = ["private/*"]
      config.publish?("public/image.jpg").should be_true
    end

    it "is case-insensitive for extensions" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg"]
      config.publish?("photo.JPG").should be_true
    end

    it "handles nested paths correctly" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".png"]
      config.publish?("blog/posts/2024/cover.png").should be_true
    end

    it "normalizes backslashes to forward slashes" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".png"]
      config.publish?("blog\\posts\\cover.png").should be_true
    end

    it "strips leading slash from path" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg"]
      config.publish?("/blog/image.jpg").should be_true
    end

    it "strips content/ prefix from path" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg"]
      config.publish?("content/blog/image.jpg").should be_true
    end

    it "handles multiple disallow paths" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg", ".png"]
      config.disallow_paths = ["drafts/*", "private/*", "temp/*"]

      config.publish?("drafts/img.jpg").should be_false
      config.publish?("private/photo.png").should be_false
      config.publish?("temp/tmp.jpg").should be_false
      config.publish?("public/photo.jpg").should be_true
    end

    it "disallow_extensions takes precedence over allow" do
      config = Hwaro::Models::ContentFilesConfig.new
      config.allow_extensions = [".jpg", ".tmp"]
      config.disallow_extensions = [".tmp"]
      config.publish?("file.tmp").should be_false
      config.publish?("file.jpg").should be_true
    end
  end

  describe ".normalize_extensions" do
    it "adds dot prefix when missing" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions(["jpg", "png"])
      result.should eq([".jpg", ".png"])
    end

    it "preserves existing dot prefix" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions([".jpg", ".png"])
      result.should eq([".jpg", ".png"])
    end

    it "lowercases extensions" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions(["JPG", ".PNG"])
      result.should eq([".jpg", ".png"])
    end

    it "removes duplicates" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions([".jpg", "jpg", ".JPG"])
      result.should eq([".jpg"])
    end

    it "strips whitespace" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions(["  jpg  ", " .png "])
      result.should eq([".jpg", ".png"])
    end

    it "handles empty array" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions([] of String)
      result.should eq([] of String)
    end

    it "filters out empty strings" do
      result = Hwaro::Models::ContentFilesConfig.normalize_extensions(["", "  ", "jpg"])
      result.should eq([".jpg"])
    end
  end

  describe ".normalize_paths" do
    it "normalizes backslashes to forward slashes" do
      result = Hwaro::Models::ContentFilesConfig.normalize_paths(["blog\\posts\\*"])
      result.should eq(["blog/posts/*"])
    end

    it "strips leading slash" do
      result = Hwaro::Models::ContentFilesConfig.normalize_paths(["/blog/*"])
      result.should eq(["blog/*"])
    end

    it "strips content/ prefix" do
      result = Hwaro::Models::ContentFilesConfig.normalize_paths(["content/blog/*"])
      result.should eq(["blog/*"])
    end

    it "strips whitespace" do
      result = Hwaro::Models::ContentFilesConfig.normalize_paths(["  blog/*  "])
      result.should eq(["blog/*"])
    end

    it "filters out empty results" do
      result = Hwaro::Models::ContentFilesConfig.normalize_paths(["", "  ", "blog/*"])
      result.should eq(["blog/*"])
    end

    it "handles empty array" do
      result = Hwaro::Models::ContentFilesConfig.normalize_paths([] of String)
      result.should eq([] of String)
    end
  end

  describe ".normalize_path" do
    it "normalizes backslashes" do
      result = Hwaro::Models::ContentFilesConfig.normalize_path("blog\\post\\img.jpg")
      result.should eq("blog/post/img.jpg")
    end

    it "strips leading slash" do
      result = Hwaro::Models::ContentFilesConfig.normalize_path("/blog/img.jpg")
      result.should eq("blog/img.jpg")
    end

    it "strips content/ prefix" do
      result = Hwaro::Models::ContentFilesConfig.normalize_path("content/blog/img.jpg")
      result.should eq("blog/img.jpg")
    end

    it "handles combined normalization" do
      result = Hwaro::Models::ContentFilesConfig.normalize_path("/content/blog\\img.jpg")
      result.should eq("blog/img.jpg")
    end

    it "handles plain path without normalization needed" do
      result = Hwaro::Models::ContentFilesConfig.normalize_path("blog/img.jpg")
      result.should eq("blog/img.jpg")
    end

    it "strips whitespace" do
      result = Hwaro::Models::ContentFilesConfig.normalize_path("  blog/img.jpg  ")
      result.should eq("blog/img.jpg")
    end
  end
end

describe Hwaro::Models::HighlightConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled.should be_true
      config.theme.should eq("github")
      config.use_cdn.should be_true
    end
  end

  describe "#css_tag" do
    it "returns CDN link when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      tag = config.css_tag
      tag.should contain("cdnjs.cloudflare.com")
      tag.should contain("highlight.js")
      tag.should contain("github.min.css")
      tag.should contain("<link rel=\"stylesheet\"")
    end

    it "returns local link when use_cdn is false" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      tag = config.css_tag
      tag.should contain("/assets/css/highlight/github.min.css")
      tag.should contain("<link rel=\"stylesheet\"")
      tag.should_not contain("cdnjs.cloudflare.com")
    end

    it "uses configured theme name" do
      config = Hwaro::Models::HighlightConfig.new
      config.theme = "monokai"
      tag = config.css_tag
      tag.should contain("monokai.min.css")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      tag = config.css_tag
      tag.should eq("")
    end
  end

  describe "#js_tag" do
    it "returns CDN script when use_cdn is true" do
      config = Hwaro::Models::HighlightConfig.new
      tag = config.js_tag
      tag.should contain("cdnjs.cloudflare.com")
      tag.should contain("highlight.min.js")
      tag.should contain("<script")
      tag.should contain("hljs.highlightAll()")
    end

    it "returns local script when use_cdn is false" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      tag = config.js_tag
      tag.should contain("/assets/js/highlight.min.js")
      tag.should contain("<script")
      tag.should contain("hljs.highlightAll()")
      tag.should_not contain("cdnjs.cloudflare.com")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      tag = config.js_tag
      tag.should eq("")
    end
  end

  describe "#tags" do
    it "returns combined CSS and JS tags" do
      config = Hwaro::Models::HighlightConfig.new
      combined = config.tags
      combined.should contain("<link rel=\"stylesheet\"")
      combined.should contain("<script")
      combined.should contain("hljs.highlightAll()")
    end

    it "returns empty string when disabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      combined = config.tags
      combined.should eq("")
    end

    it "contains both css_tag and js_tag output" do
      config = Hwaro::Models::HighlightConfig.new
      css = config.css_tag
      js = config.js_tag
      combined = config.tags
      combined.should eq("#{css}\n#{js}")
    end
  end

  describe "property setters" do
    it "can set enabled" do
      config = Hwaro::Models::HighlightConfig.new
      config.enabled = false
      config.enabled.should be_false
    end

    it "can set theme" do
      config = Hwaro::Models::HighlightConfig.new
      config.theme = "dracula"
      config.theme.should eq("dracula")
    end

    it "can set use_cdn" do
      config = Hwaro::Models::HighlightConfig.new
      config.use_cdn = false
      config.use_cdn.should be_false
    end
  end
end
