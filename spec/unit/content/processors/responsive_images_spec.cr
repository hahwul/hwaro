require "../../../spec_helper"
require "../../../../src/core/build/builder"
require "../../../../src/content/hooks/image_hooks"

# =============================================================================
# Unit specs for responsive content-image rewriting (srcset/sizes injection).
#
# When image_processing generated width variants for an <img>, the render
# phase rewrites the tag to add `srcset`/`sizes` so browsers can pick an
# appropriately-sized variant instead of always loading the full-size source.
# =============================================================================

# Expose the private render-phase helper for direct testing.
module Hwaro::Core::Build
  class Builder
    def test_apply_responsive_images(html : String, page : Hwaro::Models::Page, config : Hwaro::Models::Config) : String
      apply_responsive_images(html, page, config)
    end
  end
end

private def with_resize_map(map, &)
  prior = Hwaro::Content::Hooks::ImageHooks.resize_map
  Hwaro::Content::Hooks::ImageHooks.set_resize_map(map)
  begin
    yield
  ensure
    Hwaro::Content::Hooks::ImageHooks.set_resize_map(prior)
  end
end

private def enabled_config : Hwaro::Models::Config
  c = Hwaro::Models::Config.new
  c.image_processing.enabled = true
  c
end

private def bundle_page : Hwaro::Models::Page
  p = Hwaro::Models::Page.new("posts/foo/index.md")
  p.url = "/posts/foo/"
  p
end

SAMPLE_MAP = {
  "/posts/foo/photo.png" => {400 => "/posts/foo/photo_400w.png", 800 => "/posts/foo/photo_800w.png"},
}

describe "Responsive content images" do
  it "adds srcset + sizes to a relative content image with variants" do
    with_resize_map(SAMPLE_MAP) do
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<p><img src="photo.png" alt="A"></p>), bundle_page, enabled_config)
      out.should contain(%(srcset="/posts/foo/photo_400w.png 400w, /posts/foo/photo_800w.png 800w"))
      out.should contain(%(sizes="100vw"))
      out.should contain(%(src="photo.png")) # original src preserved
    end
  end

  it "resolves ./ and ../ relative srcs like the plain relative path" do
    map = SAMPLE_MAP.merge({"/posts/bar/z.png" => {400 => "/posts/bar/z_400w.png"}})
    with_resize_map(map) do
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<img src="./photo.png"><img src="../bar/z.png">), bundle_page, enabled_config)
      out.should contain(%(srcset="/posts/foo/photo_400w.png 400w, /posts/foo/photo_800w.png 800w"))
      out.should contain(%(srcset="/posts/bar/z_400w.png 400w"))
    end
  end

  it "resolves an absolute src against the resize map" do
    with_resize_map(SAMPLE_MAP) do
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<img src="/posts/foo/photo.png">), bundle_page, enabled_config)
      out.should contain(%(srcset="/posts/foo/photo_400w.png 400w, /posts/foo/photo_800w.png 800w"))
    end
  end

  it "leaves images without generated variants untouched" do
    with_resize_map(SAMPLE_MAP) do
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<img src="other.png" alt="x">), bundle_page, enabled_config)
      out.should eq(%(<img src="other.png" alt="x">))
    end
  end

  it "skips external images" do
    with_resize_map(SAMPLE_MAP) do
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<img src="https://cdn.example.com/posto.png">), bundle_page, enabled_config)
      out.should_not contain("srcset")
    end
  end

  it "does not double-process an <img> that already has a srcset" do
    with_resize_map(SAMPLE_MAP) do
      html = %(<img src="photo.png" srcset="preset.png 100w">)
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(html, bundle_page, enabled_config)
      out.should eq(html)
    end
  end

  it "is a no-op when image_processing is disabled" do
    with_resize_map(SAMPLE_MAP) do
      disabled = Hwaro::Models::Config.new # enabled defaults to false
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<img src="photo.png">), bundle_page, disabled)
      out.should_not contain("srcset")
    end
  end
end

# A project with `static/img/a.png` (6×3) and `static/photo.png` (4×2),
# cwd'd for the block.
private def with_image_project(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      Dir.mkdir_p("static/img")
      px = Bytes.new(6 * 3 * 3, 128_u8)
      LibStb.stbi_write_png("static/img/a.png", 6, 3, 3, px.to_unsafe.as(Void*), 6 * 3)
      LibStb.stbi_write_png("static/photo.png", 4, 2, 3, px.to_unsafe.as(Void*), 4 * 3)
      Hwaro::Content::Hooks::ImageHooks.clear_intrinsic_sizes
      begin
        yield
      ensure
        Hwaro::Content::Hooks::ImageHooks.clear_intrinsic_sizes
      end
    end
  end
end

private def dimensions_config : Hwaro::Models::Config
  c = Hwaro::Models::Config.new
  c.image_processing.dimensions = true
  c
end

describe "Content image dimensions" do
  it "adds intrinsic width/height to a local image without image_processing.enabled" do
    with_image_project do
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<p><img src="/img/a.png" alt="A"></p>), bundle_page, dimensions_config)
      out.should eq(%(<p><img width="6" height="3" src="/img/a.png" alt="A"></p>))
    end
  end

  it "leaves a tag alone when the author set width or height" do
    with_image_project do
      builder = Hwaro::Core::Build::Builder.new
      html = %(<img src="/img/a.png" width="10"><img src="/img/a.png" HEIGHT='5'>)
      builder.test_apply_responsive_images(html, bundle_page, dimensions_config).should eq(html)
    end
  end

  it "skips external, missing and unreadable sources" do
    with_image_project do
      File.write("static/img/broken.png", "nope")
      html = %(<img src="https://cdn.example.com/a.png"><img src="/img/none.png"><img src="/img/broken.png">)
      Hwaro::Core::Build::Builder.new.test_apply_responsive_images(html, bundle_page, dimensions_config).should eq(html)
    end
  end

  it "strips base_path before resolving a subpath-prefixed src" do
    with_image_project do
      config = dimensions_config
      config.base_url = "https://example.com/blog"
      out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
        %(<img src="/blog/img/a.png">), bundle_page, config)
      out.should eq(%(<img width="6" height="3" src="/blog/img/a.png">))
    end
  end

  it "uses the original's size alongside generated srcset variants" do
    with_image_project do
      config = dimensions_config
      config.image_processing.enabled = true
      with_resize_map({"/photo.png" => {2 => "/photo_2w.png"}}) do
        out = Hwaro::Core::Build::Builder.new.test_apply_responsive_images(
          %(<img src="/photo.png">), bundle_page, config)
        out.should eq(%(<img srcset="/photo_2w.png 2w" sizes="100vw" width="4" height="2" src="/photo.png">))
      end
    end
  end

  it "is a no-op when dimensions is off" do
    with_image_project do
      html = %(<img src="/img/a.png">)
      Hwaro::Core::Build::Builder.new.test_apply_responsive_images(html, bundle_page, Hwaro::Models::Config.new).should eq(html)
    end
  end
end
