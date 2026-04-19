require "../spec_helper"
require "../../src/content/hooks/image_hooks"

# =============================================================================
# Unit specs for ImageHooks. Covers:
# - Class-level resize_map / lqip_map snapshot semantics
# - find_resized exact / miss
# - find_closest exact / round-up / fallback-to-largest / unknown URL
# - find_lqip dup semantics (mutation isolation)
# - register_hooks wiring (point, name, priority)
# - process_images skip paths via the BeforeRender hook (no fixtures
#   loaded → registered hook returns Continue and is a no-op)
# =============================================================================

# The hook stores @@resize_map and @@lqip_map at class scope. Snapshot the
# global state before each test and restore on exit so we don't pollute other
# specs (e.g., functional builds that exercise real image pipelines).
#
# NOTES:
# - resize_map / lqip_map already return a `.dup` of the internal hash, so
#   `prior_*` is a copy. set_resize_map / set_lqip_map then store that copy
#   as the new internal state — content is preserved, but identity will
#   differ from the pre-test ivar. Tests must not assert reference identity
#   on the class-level maps.
# - The snapshot is captured before `yield`. Tests must not mutate the
#   captured `prior_*` hashes mid-test (and they shouldn't have a reference
#   to them anyway — they're locals here).
private def with_image_hook_state(&)
  prior_resize = Hwaro::Content::Hooks::ImageHooks.resize_map
  prior_lqip = Hwaro::Content::Hooks::ImageHooks.lqip_map
  begin
    yield
  ensure
    Hwaro::Content::Hooks::ImageHooks.set_resize_map(prior_resize)
    Hwaro::Content::Hooks::ImageHooks.set_lqip_map(prior_lqip)
  end
end

describe Hwaro::Content::Hooks::ImageHooks do
  describe ".resize_map" do
    it "returns a duplicated snapshot (caller mutations don't leak back)" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/img.png" => {320 => "/img-320.png"}}
        )
        snapshot = Hwaro::Content::Hooks::ImageHooks.resize_map
        snapshot["/intruder.png"] = {1 => "/intruder-1.png"}

        # Class state must be unchanged
        Hwaro::Content::Hooks::ImageHooks.resize_map
          .has_key?("/intruder.png").should be_false
      end
    end
  end

  describe ".set_resize_map" do
    it "replaces the entire resize map" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/a.png" => {1 => "/a-1.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/b.png" => {2 => "/b-2.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.resize_map.keys.should eq(["/b.png"])
      end
    end
  end

  describe ".find_resized" do
    it "returns the resized URL when both URL and width are present" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/cat.png" => {320 => "/cat-320.png", 640 => "/cat-640.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.find_resized("/cat.png", 320)
          .should eq("/cat-320.png")
      end
    end

    it "returns nil when the URL is unknown" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {} of String => Hash(Int32, String)
        )
        Hwaro::Content::Hooks::ImageHooks.find_resized("/missing.png", 320)
          .should be_nil
      end
    end

    it "returns nil when the URL is known but the requested width is not" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/cat.png" => {320 => "/cat-320.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.find_resized("/cat.png", 999)
          .should be_nil
      end
    end
  end

  describe ".find_closest" do
    it "returns the exact width when it exists" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png", 1280 => "/p-1280.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest("/p.png", 640)
          .should eq("/p-640.png")
      end
    end

    it "rounds up to the smallest width >= requested" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png", 1280 => "/p-1280.png"}}
        )
        # 500 → next available is 640
        Hwaro::Content::Hooks::ImageHooks.find_closest("/p.png", 500)
          .should eq("/p-640.png")
      end
    end

    it "falls back to the largest width when none are >= requested" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png"}}
        )
        # 9999 has nothing larger → largest available (640)
        Hwaro::Content::Hooks::ImageHooks.find_closest("/p.png", 9999)
          .should eq("/p-640.png")
      end
    end

    it "returns nil for an unknown URL" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {} of String => Hash(Int32, String)
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest("/missing.png", 320)
          .should be_nil
      end
    end

    it "returns nil for a URL whose width-map is empty" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/empty.png" => {} of Int32 => String}
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest("/empty.png", 320)
          .should be_nil
      end
    end
  end

  describe ".lqip_map / .find_lqip" do
    it "returns nil for an unknown URL" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_lqip_map(
          {} of String => Hash(String, String)
        )
        Hwaro::Content::Hooks::ImageHooks.find_lqip("/missing.png").should be_nil
      end
    end

    it "returns the lqip data hash for a known URL" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_lqip_map(
          {"/p.png" => {"lqip" => "data:image/jpeg;base64,...", "dominant_color" => "#abcdef"}}
        )
        data = Hwaro::Content::Hooks::ImageHooks.find_lqip("/p.png")
        data.should_not be_nil
        data.not_nil!["lqip"].should start_with("data:")
        data.not_nil!["dominant_color"].should eq("#abcdef")
      end
    end

    it "returns a duplicated entry — mutation does not leak back" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_lqip_map(
          {"/p.png" => {"lqip" => "x", "dominant_color" => "#000000"}}
        )
        data = Hwaro::Content::Hooks::ImageHooks.find_lqip("/p.png").not_nil!
        data["lqip"] = "tampered"

        Hwaro::Content::Hooks::ImageHooks.find_lqip("/p.png").not_nil!["lqip"]
          .should eq("x")
      end
    end

    it ".lqip_map returns a duplicated snapshot" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_lqip_map(
          {"/p.png" => {"lqip" => "x", "dominant_color" => "#000"}}
        )
        snapshot = Hwaro::Content::Hooks::ImageHooks.lqip_map
        snapshot["/intruder.png"] = {"lqip" => "y", "dominant_color" => "#fff"}

        Hwaro::Content::Hooks::ImageHooks.lqip_map.has_key?("/intruder.png")
          .should be_false
      end
    end
  end

  describe "#register_hooks" do
    it "registers a single hook at BeforeRender with name 'image:resize'" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)

      hooks = manager.hooks_at(Hwaro::Core::Lifecycle::HookPoint::BeforeRender)
      hooks.size.should eq(1)
      hooks.first.name.should eq("image:resize")
      hooks.first.priority.should eq(20)
    end

    it "does not register hooks at any other point" do
      manager = Hwaro::Core::Lifecycle::Manager.new
      Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
      manager.hook_count.should eq(1)
    end
  end

  describe "process_images via the registered hook" do
    # All four skip-paths seed the resize_map with a sentinel entry so the
    # assertion is "the hook DID NOT TOUCH state", not just "state ended
    # empty" (which would also pass if the hook silently cleared the map).
    sentinel_map = {"sentinel.png" => {1 => "sentinel-1.png"}}

    it "is a no-op (Continue) when ctx.options.skip_image_processing is true" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)

        config = Hwaro::Models::Config.new
        config.image_processing.enabled = true
        config.image_processing.widths = [320, 640]

        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public",
          skip_image_processing: true,
        )
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = config

        manager = Hwaro::Core::Lifecycle::Manager.new
        Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)

        result = manager.trigger(
          Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx
        )
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        Hwaro::Content::Hooks::ImageHooks.resize_map.should eq(sentinel_map)
      end
    end

    it "is a no-op when image_processing.enabled is false" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)

        config = Hwaro::Models::Config.new
        config.image_processing.enabled = false
        config.image_processing.widths = [320]

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = config

        manager = Hwaro::Core::Lifecycle::Manager.new
        Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
        manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

        Hwaro::Content::Hooks::ImageHooks.resize_map.should eq(sentinel_map)
      end
    end

    it "is a no-op when widths is empty" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)

        config = Hwaro::Models::Config.new
        config.image_processing.enabled = true
        config.image_processing.widths = [] of Int32

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = config

        manager = Hwaro::Core::Lifecycle::Manager.new
        Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
        manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

        Hwaro::Content::Hooks::ImageHooks.resize_map.should eq(sentinel_map)
      end
    end

    it "is a no-op when ctx.config is nil" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        # ctx.config is left nil intentionally

        manager = Hwaro::Core::Lifecycle::Manager.new
        Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
        result = manager.trigger(
          Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx
        )
        result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
        Hwaro::Content::Hooks::ImageHooks.resize_map.should eq(sentinel_map)
      end
    end
  end

  # Regression coverage for #389: on watch rebuilds we want the hook to
  # skip images whose source is unchanged and whose resized files already
  # exist. These tests cover the pure predicate; end-to-end reuse is
  # exercised by `process_images` via the path through this helper.
  describe ".reusable_widths" do
    it "returns a width => filename map when all destinations are fresh" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_320w.jpg"), "320")
        File.write(File.join(dest_dir, "photo_640w.jpg"), "640")

        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320, 640])
        result.should_not be_nil
        result.not_nil![320].should eq("photo_320w.jpg")
        result.not_nil![640].should eq("photo_640w.jpg")
      end
    end

    it "returns nil when any destination is missing" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        # Only the 320w variant exists
        File.write(File.join(dest_dir, "photo_320w.jpg"), "320")

        Hwaro::Content::Hooks::ImageHooks
          .reusable_widths(source, dest_dir, [320, 640])
          .should be_nil
      end
    end

    it "returns nil when a destination is older than the source" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        dest = File.join(dest_dir, "photo_320w.jpg")

        # Write the destination first, then touch the source to be newer.
        File.write(dest, "old")
        File.touch(dest, Time.utc - 5.minutes)
        File.write(source, "src")

        Hwaro::Content::Hooks::ImageHooks
          .reusable_widths(source, dest_dir, [320])
          .should be_nil
      end
    end

    it "returns nil when the source file is missing" do
      Dir.mktmpdir do |dir|
        Hwaro::Content::Hooks::ImageHooks
          .reusable_widths(File.join(dir, "missing.jpg"), dir, [320])
          .should be_nil
      end
    end

    it "returns nil when a destination is zero bytes" do
      # Defends against a killed serve leaving a half-written resized file:
      # mtime is valid but the file is empty, and reusing it would serve a
      # corrupt image. Cheaper to reprocess than to serve broken bytes.
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_320w.jpg"), "")

        Hwaro::Content::Hooks::ImageHooks
          .reusable_widths(source, dest_dir, [320])
          .should be_nil
      end
    end
  end
end
