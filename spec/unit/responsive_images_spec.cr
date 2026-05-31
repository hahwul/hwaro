require "../spec_helper"
require "../../src/core/build/builder"
require "../../src/content/hooks/image_hooks"

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
