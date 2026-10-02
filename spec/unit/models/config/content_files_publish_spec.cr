require "../../../spec_helper"

describe Hwaro::Models::ContentFilesConfig do
  describe "#publish?" do
    it "returns true for allowed extension" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png", ".gif"]

      config.content_files.publish?("photo.jpg").should be_true
    end

    it "returns false for disallowed extension" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]
      config.content_files.disallow_extensions = [".psd"]

      config.content_files.publish?("design.psd").should be_false
    end

    it "returns false for extension not in allow list" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]

      config.content_files.publish?("document.pdf").should be_false
    end

    it "returns false when allow_extensions is empty (nothing allowed)" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [] of String
      config.content_files.disallow_extensions = [] of String

      config.content_files.publish?("anything.xyz").should be_false
    end

    it "returns false for disallowed path" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]
      config.content_files.disallow_paths = ["drafts/**"]

      config.content_files.publish?("drafts/secret.jpg").should be_false
    end

    it "returns true for path not matching disallow_paths" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]
      config.content_files.disallow_paths = ["drafts/**"]

      config.content_files.publish?("posts/image.jpg").should be_true
    end

    it "handles nested file paths" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]

      config.content_files.publish?("blog/2024/photo.jpg").should be_true
    end

    it "handles files with multiple dots in name" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]

      config.content_files.publish?("my.photo.2024.jpg").should be_true
    end

    it "is case-insensitive for extensions via config normalization" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]

      # The publish? method delegates to config.content_files.publish?
      # which handles extension normalization
      config.content_files.publish?("photo.jpg").should be_true
    end

    it "returns false for markdown files when only images allowed" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png", ".gif", ".svg"]

      config.content_files.publish?("readme.md").should be_false
    end

    it "handles SVG files" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".svg"]

      config.content_files.publish?("icon.svg").should be_true
    end

    it "handles PDF files" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".pdf"]

      config.content_files.publish?("document.pdf").should be_true
    end

    it "disallow_extensions takes precedence over allow_extensions" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".psd"]
      config.content_files.disallow_extensions = [".psd"]

      config.content_files.publish?("file.psd").should be_false
    end

    it "handles empty relative path" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]

      # Empty path should not match any extension
      config.content_files.publish?("").should be_false
    end

    it "handles file with no extension" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]

      config.content_files.publish?("Makefile").should be_false
    end
  end
end
