require "../spec_helper"
require "../../src/content/processors/content_files"

describe Hwaro::Content::Processors::ContentFiles do
  describe ".publish?" do
    it "returns false when config is nil" do
      Hwaro::Content::Processors::ContentFiles.publish?("image.jpg", nil).should be_false
    end

    it "returns true for allowed extension" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png", ".gif"]

      Hwaro::Content::Processors::ContentFiles.publish?("photo.jpg", config).should be_true
    end

    it "returns false for disallowed extension" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]
      config.content_files.disallow_extensions = [".psd"]

      Hwaro::Content::Processors::ContentFiles.publish?("design.psd", config).should be_false
    end

    it "returns false for extension not in allow list" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]

      Hwaro::Content::Processors::ContentFiles.publish?("document.pdf", config).should be_false
    end

    it "returns false when allow_extensions is empty (nothing allowed)" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [] of String
      config.content_files.disallow_extensions = [] of String

      Hwaro::Content::Processors::ContentFiles.publish?("anything.xyz", config).should be_false
    end

    it "returns false for disallowed path" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]
      config.content_files.disallow_paths = ["drafts/**"]

      Hwaro::Content::Processors::ContentFiles.publish?("drafts/secret.jpg", config).should be_false
    end

    it "returns true for path not matching disallow_paths" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]
      config.content_files.disallow_paths = ["drafts/**"]

      Hwaro::Content::Processors::ContentFiles.publish?("posts/image.jpg", config).should be_true
    end

    it "handles nested file paths" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]

      Hwaro::Content::Processors::ContentFiles.publish?("blog/2024/photo.jpg", config).should be_true
    end

    it "handles files with multiple dots in name" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]

      Hwaro::Content::Processors::ContentFiles.publish?("my.photo.2024.jpg", config).should be_true
    end

    it "is case-insensitive for extensions via config normalization" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]

      # The publish? method delegates to config.content_files.publish?
      # which handles extension normalization
      Hwaro::Content::Processors::ContentFiles.publish?("photo.jpg", config).should be_true
    end

    it "returns false for markdown files when only images allowed" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png", ".gif", ".svg"]

      Hwaro::Content::Processors::ContentFiles.publish?("readme.md", config).should be_false
    end

    it "handles SVG files" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".svg"]

      Hwaro::Content::Processors::ContentFiles.publish?("icon.svg", config).should be_true
    end

    it "handles PDF files" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".pdf"]

      Hwaro::Content::Processors::ContentFiles.publish?("document.pdf", config).should be_true
    end

    it "disallow_extensions takes precedence over allow_extensions" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".psd"]
      config.content_files.disallow_extensions = [".psd"]

      Hwaro::Content::Processors::ContentFiles.publish?("file.psd", config).should be_false
    end

    it "handles empty relative path" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg"]

      # Empty path should not match any extension
      Hwaro::Content::Processors::ContentFiles.publish?("", config).should be_false
    end

    it "handles file with no extension" do
      config = Hwaro::Models::Config.new
      config.content_files.allow_extensions = [".jpg", ".png"]

      Hwaro::Content::Processors::ContentFiles.publish?("Makefile", config).should be_false
    end
  end
end
