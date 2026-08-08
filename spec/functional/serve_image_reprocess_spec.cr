require "../spec_helper"
require "../../src/services/server/server"
require "../../src/ext/stb_bindings"

# Regression coverage for A12: modified image bytes under serve left the
# resized variants (and LQIP data) stale — the `image:resize` hook only runs
# on full builds, and the :static / :content_files watch strategies just
# copied the changed original. The change paths now re-run the resize
# pipeline for the changed image.

# Reopened seams (same pattern as serve_watch_fixes_spec; distinct names so
# the two files can't collide when compiled together).
module Hwaro
  module Services
    class Server
      def img_fix_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def img_fix_apply_changeset(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end
    end
  end
end

# Write a real, decodable PNG (solid color) via the stb bindings — the resize
# pipeline decodes with stbi_load, so a hand-rolled fake won't do.
private def write_solid_png(path : String, width : Int32, height : Int32, r : UInt8, g : UInt8, b : UInt8)
  pixels = Array(UInt8).new(width * height * 3) { |i| [r, g, b][i % 3] }
  FileUtils.mkdir_p(File.dirname(path))
  LibStb.stbi_write_png(path, width, height, 3, pixels.to_unsafe.as(Void*), width * 3)
end

private def img_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  options
end

private def write_image_site
  File.write("config.toml", <<-TOML
    title = "Image Site"
    base_url = "https://example.com"

    [image_processing]
    enabled = true
    widths = [32]

    [content.files]
    allow_extensions = ["png"]
    TOML
  )
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
  File.write("content/index.md", "---\ntitle: Home\n---\nhome body")
end

private def static_changeset(paths : Array(String)) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: [] of String,
    modified_templates: [] of String,
    modified_static: paths,
    added_files: [] of String,
    removed_files: [] of String,
    config_changed: false,
  )
end

private def content_files_changeset(paths : Array(String)) : Hwaro::Services::ChangeSet
  Hwaro::Services::ChangeSet.new(
    modified_content: [] of String,
    modified_templates: [] of String,
    modified_static: [] of String,
    added_files: [] of String,
    removed_files: [] of String,
    config_changed: false,
    modified_content_files: paths,
  )
end

describe "serve image reprocessing on changed bytes (A12)" do
  it "regenerates static image variants when the source bytes change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_image_site
        write_solid_png("static/img/photo.png", 64, 64, 255_u8, 0_u8, 0_u8)

        server = Hwaro::Services::Server.new
        options = img_options
        server.img_fix_builder.run(options).should be_true

        variant = "public/img/photo_32w.png"
        File.exists?(variant).should be_true
        before = File.read(variant)

        # Overwrite the source with different pixels and run the serve
        # static-change path.
        write_solid_png("static/img/photo.png", 64, 64, 0_u8, 0_u8, 255_u8)
        server.img_fix_apply_changeset(static_changeset(["static/img/photo.png"]), options)

        # Original was republished (pre-existing behavior) …
        File.read("public/img/photo.png").should eq(File.read("static/img/photo.png"))
        # … and the resized variant now reflects the new bytes too.
        File.read(variant).should_not eq(before)
      end
    end
  end

  it "regenerates content-file image variants when the source bytes change" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_image_site
        write_solid_png("content/media/pic.png", 64, 64, 255_u8, 0_u8, 0_u8)

        server = Hwaro::Services::Server.new
        options = img_options
        server.img_fix_builder.run(options).should be_true

        variant = "public/media/pic_32w.png"
        File.exists?(variant).should be_true
        before = File.read(variant)

        write_solid_png("content/media/pic.png", 64, 64, 0_u8, 255_u8, 0_u8)
        server.img_fix_apply_changeset(content_files_changeset(["content/media/pic.png"]), options)

        File.read(variant).should_not eq(before)
      end
    end
  end
end
