require "../../../spec_helper"
require "../../../../src/content/hooks/image_hooks"
require "../../../../src/content/processors/template"
require "../../../support/build_helper"

# =============================================================================
# Unit specs for ImageHooks. Covers:
# - find_closest_variant exact / round-up / fallback-to-largest / unknown URL
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
    Hwaro::Content::Hooks::ImageHooks.set_processing_state(false)
    Hwaro::Content::Hooks::ImageHooks.set_resize_map(prior_resize)
    Hwaro::Content::Hooks::ImageHooks.set_lqip_map(prior_lqip)
  end
end

describe Hwaro::Content::Hooks::ImageHooks do
  describe ".find_closest_variant URL choice" do
    it "returns the exact width when it exists" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png", 1280 => "/p-1280.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/p.png", 640)
          .try(&.[1]).should eq("/p-640.png")
      end
    end

    it "rounds up to the smallest width >= requested" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png", 1280 => "/p-1280.png"}}
        )
        # 500 → next available is 640
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/p.png", 500)
          .try(&.[1]).should eq("/p-640.png")
      end
    end

    it "falls back to the largest width when none are >= requested" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png"}}
        )
        # 9999 has nothing larger → largest available (640)
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/p.png", 9999)
          .try(&.[1]).should eq("/p-640.png")
      end
    end

    it "returns nil for an unknown URL" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {} of String => Hash(Int32, String)
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/missing.png", 320)
          .should be_nil
      end
    end

    it "returns nil for a URL whose width-map is empty" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/empty.png" => {} of Int32 => String}
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/empty.png", 320)
          .should be_nil
      end
    end
  end

  # Variants are never upscaled, so the file a request resolves to can be
  # narrower than what was asked for. `resize_image()` reported the REQUESTED
  # width, which templates write into `<img width=…>` — telling the browser to
  # lay out the image at a size it isn't.
  describe ".find_closest_variant" do
    it "reports the actual width of the chosen variant" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(
          {"/p.png" => {320 => "/p-320.png", 640 => "/p-640.png"}}
        )
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/p.png", 640)
          .should eq({640, "/p-640.png"})
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/p.png", 500)
          .should eq({640, "/p-640.png"})
        # Nothing is large enough — the widest variant, at its real width.
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/p.png", 9999)
          .should eq({640, "/p-640.png"})
      end
    end

    it "returns nil for an unknown URL" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map({} of String => Hash(Int32, String))
        Hwaro::Content::Hooks::ImageHooks.find_closest_variant("/missing.png", 320).should be_nil
      end
    end
  end

  describe "resize_image()" do
    it "reports the variant's width, not the requested one" do
      with_image_hook_state do
        # A 10px-wide source: no variant is upscaled, so 640 resolves to 10.
        Hwaro::Content::Hooks::ImageHooks.set_resize_map({"/img/tiny.png" => {10 => "/img/tiny_10w.png"}})
        out = render_crinja(
          %({{ resize_image(path="/img/tiny.png", width=640).width }}|{{ resize_image(path="/img/tiny.png", width=640).url }}),
          {"base_url" => "https://example.com"}
        ).strip
        out.should eq("10|https://example.com/img/tiny_10w.png")
      end
    end

    it "keeps a ?query or #fragment out of the lookup and on the returned url" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map({"/img/p.png" => {100 => "/img/p_100w.png"}})
        env = {"base_url" => "https://example.com"}
        render_crinja(%({{ resize_image(path="/img/p.png?v=1", width=100).url }}), env).strip
          .should eq("https://example.com/img/p_100w.png?v=1")
        render_crinja(%({{ resize_image(path="/img/p.png#top", width=100).url }}), env).strip
          .should eq("https://example.com/img/p_100w.png#top")
        # No variant: the original URL comes back unchanged, not %3F-encoded.
        render_crinja(%({{ resize_image(path="/img/none.png?v=1", width=100).url }}), env).strip
          .should eq("https://example.com/img/none.png?v=1")
        render_crinja(%({{ resize_image(path="/img/none.png?v=1#a", width=100, height=50, op="fill").url }}), env).strip
          .should eq("https://example.com/img/none.png?v=1#a")
      end
    end

    it "collapses . and .. segments of the path" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map({"/img/p.png" => {100 => "/img/p_100w.png"}})
        env = {"base_url" => "https://example.com"}
        render_crinja(%({{ resize_image(path="/img/x/../p.png", width=100).url }}), env).strip
          .should eq("https://example.com/img/p_100w.png")
        render_crinja(%({{ resize_image(path="/./img/none.png", width=100).url }}), env).strip
          .should eq("https://example.com/img/none.png")
      end
    end

    it "falls back to the requested width when no variant exists" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map({} of String => Hash(Int32, String))
        render_crinja(
          %({{ resize_image(path="/img/a.png", width=800).width }}), {"base_url" => "https://example.com"}
        ).strip.should eq("800")
      end
    end
  end

  describe ".find_lqip" do
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
    # Every path seeds the resize_map with a sentinel entry. A run that does
    # not resize (skip flag, disabled, no widths) must DROP the previous run's
    # entries: they name variant files the build then prunes, and the maps
    # outlive the build in a `hwaro serve` process. Only a missing config
    # (nothing to decide from) leaves state alone.
    sentinel_map = {"sentinel.png" => {1 => "sentinel-1.png"}}

    it "forgets stale variants (Continue) when ctx.options.skip_image_processing is true" do
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
        # Nothing is processed, so the previous run's variants are dropped
        # rather than left for resize_image() to hand out (serve).
        Hwaro::Content::Hooks::ImageHooks.resize_map.should be_empty
      end
    end

    it "forgets stale variants when image_processing.enabled is false" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)

        config = Hwaro::Models::Config.new
        Hwaro::Content::Hooks::ImageHooks.set_lqip_map({"sentinel.png" => {"lqip" => "x"}})
        Hwaro::Content::Hooks::ImageHooks.set_processing_state(true, {"sentinel.png" => "static/sentinel.png"})
        config.image_processing.enabled = false
        config.image_processing.widths = [320]

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = config

        manager = Hwaro::Core::Lifecycle::Manager.new
        Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
        manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

        Hwaro::Content::Hooks::ImageHooks.resize_map.should be_empty
        Hwaro::Content::Hooks::ImageHooks.lqip_map.should be_empty
        Hwaro::Content::Hooks::ImageHooks.source_map.should be_empty
        Hwaro::Content::Hooks::ImageHooks.processing_active?.should be_false
      end
    end

    it "forgets stale variants, LQIP and sources when widths is empty" do
      with_image_hook_state do
        Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)

        config = Hwaro::Models::Config.new
        config.image_processing.enabled = true
        config.image_processing.widths = [] of Int32
        Hwaro::Content::Hooks::ImageHooks.set_lqip_map({"sentinel.png" => {"lqip" => "data:x"}})

        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
        ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
        ctx.config = config

        manager = Hwaro::Core::Lifecycle::Manager.new
        Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
        manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

        Hwaro::Content::Hooks::ImageHooks.resize_map.should be_empty
      end
    end

    it "drops the previous run's variants when no image is left to process" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          with_image_hook_state do
            Hwaro::Content::Hooks::ImageHooks.set_resize_map(sentinel_map.dup)
            Hwaro::Content::Hooks::ImageHooks.set_lqip_map({"sentinel.png" => {"lqip" => "x"}})

            config = Hwaro::Models::Config.new
            config.image_processing.enabled = true
            config.image_processing.widths = [320]

            options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
            ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
            ctx.config = config

            manager = Hwaro::Core::Lifecycle::Manager.new
            Hwaro::Content::Hooks::ImageHooks.new.register_hooks(manager)
            manager.trigger(Hwaro::Core::Lifecycle::HookPoint::BeforeRender, ctx)

            Hwaro::Content::Hooks::ImageHooks.resize_map.should be_empty
            Hwaro::Content::Hooks::ImageHooks.lqip_map.should be_empty
            render_crinja(%({{ resize_image(path="/sentinel.png", width=1).url }}), {"base_url" => "https://example.com"}).strip
              .should eq("https://example.com/sentinel.png")
          end
        end
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
    it "reuses stamped variants only for the same source version and encode settings" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          hooks = Hwaro::Content::Hooks::ImageHooks
          stamps = Hwaro::Content::Hooks::ImageVariantStamps
          File.write("photo.jpg", "src")
          File.touch("photo.jpg", Time.utc - 1.hour)
          Dir.mkdir_p("out")
          variant = File.join("out", "photo_320w.jpg")
          File.write(variant, "320")
          settings = hooks.encode_settings(85, 0, 20)

          # No stamp: not proven fresh (a cache from before stamps existed).
          hooks.reusable_widths("photo.jpg", "out", [320], nil, settings).should be_nil
          hooks.reusable_widths("photo.jpg", "out", [320]).should_not be_nil

          stamps.record(variant, stamps.fingerprint("photo.jpg", settings).not_nil!)
          hooks.reusable_widths("photo.jpg", "out", [320], nil, settings).should_not be_nil

          # A different quality is a different variant.
          hooks.reusable_widths("photo.jpg", "out", [320], nil, hooks.encode_settings(5, 0, 20)).should be_nil

          # A replaced source whose mtime moved BACKWARDS (still older than
          # the variant) is a different source version.
          File.write("photo.jpg", "other")
          File.touch("photo.jpg", Time.utc - 2.hours)
          hooks.reusable_widths("photo.jpg", "out", [320], nil, settings).should be_nil
        end
      end
    end

    it "returns a width => filename map when all destinations are fresh" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_320w.jpg"), "320")
        File.write(File.join(dest_dir, "photo_640w.jpg"), "640")

        # Variants made safely after the source (racy-git).
        File.touch(source, Time.utc - 1.hour)
        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320, 640])
        result.should_not be_nil
        result.not_nil![320].should eq("photo_320w.jpg")
        result.not_nil![640].should eq("photo_640w.jpg")
      end
    end

    it "finds the lowercased variants of an uppercase-extension source" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "B.JPG")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "B_320w.jpg"), "320")
        File.touch(source, Time.utc - 1.hour)

        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320])
        result.should_not be_nil
        result.not_nil![320].should eq("B_320w.jpg")
      end
    end

    # A `_<width>w` sibling whose number does not fit Int32 (a stray file
    # copied in from static/, a leftover from another tool) used to raise
    # `ArgumentError: Invalid Int32` out of the `image:resize` hook and abort
    # the build with exit 70 — on every cold build and every serve rebuild,
    # until the file was found and deleted.
    it "ignores a variant whose width overflows Int32 instead of raising" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_320w.jpg"), "320")
        File.write(File.join(dest_dir, "photo_640w.jpg"), "640")
        File.write(File.join(dest_dir, "photo_9999999999w.jpg"), "bogus")

        # Variants made safely after the source (racy-git).
        File.touch(source, Time.utc - 1.hour)
        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320, 640])
        result.should_not be_nil
        result.not_nil!.keys.sort!.should eq([320, 640])
      end
    end

    it "returns nil when a non-clamped variant is missing (config/output mismatch)" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        # The 320w and 1280w variants exist but the middle 640w is missing. The
        # largest on-disk variant (1280) implies the source is >= 1280px, so
        # 640w should exist and is NOT a clamp — the set is incomplete, so the
        # image must be reprocessed.
        File.write(File.join(dest_dir, "photo_320w.jpg"), "320")
        File.write(File.join(dest_dir, "photo_1280w.jpg"), "1280")

        Hwaro::Content::Hooks::ImageHooks
          .reusable_widths(source, dest_dir, [320, 640, 1280])
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

    # Racy-git (#857): a variant written inside the source's timestamp tick
    # cannot prove it was made from the current bytes — a same-size rewrite
    # of the source in that tick keeps `dest >= source`. Both mtimes are
    # pinned, so the spec does not depend on the clock.
    it "returns nil when a destination was written inside the source's mtime tick" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        dest = File.join(dest_dir, "photo_320w.jpg")
        File.write(source, "src")
        File.write(dest, "320")
        tick = Time.utc - 1.hour
        File.touch(source, tick)
        File.touch(dest, tick + 1.millisecond)

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

    it "reuses when a configured width exceeds the source (clamped to _<src_w>w)" do
      # #389 clamp branch: config asks for 9999 but the source is only 640px,
      # so resize_and_lqip wrote a single photo_640w.jpg. The on-disk set
      # {320, 640} must still match what the current config produces (9999
      # clamps to 640), so the image is reused — not re-decoded every rebuild.
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_320w.jpg"), "320")
        File.write(File.join(dest_dir, "photo_640w.jpg"), "640")

        # Variants made safely after the source (racy-git).
        File.touch(source, Time.utc - 1.hour)
        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320, 640, 9999])
        result.should_not be_nil
        result.not_nil!.should eq({320 => "photo_320w.jpg", 640 => "photo_640w.jpg"})
      end
    end

    it "reuses when two configured widths collapse onto one source width (.uniq!)" do
      # Both 640 and 1280 clamp to the 640px source, so .uniq! collapses them
      # to [640] — which matches the lone photo_640w.jpg on disk → reuse.
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.jpg")
        File.write(source, "src")
        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_640w.jpg"), "640")

        # Variants made safely after the source (racy-git).
        File.touch(source, Time.utc - 1.hour)
        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [640, 1280])
        result.should_not be_nil
        result.not_nil!.should eq({640 => "photo_640w.jpg"})
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

    # A11: the source width used to be inferred from the LARGEST on-disk
    # variant, so adding a bigger width to [image_processing] widths was
    # silently "satisfied" by clamping to the old largest variant — the new
    # variant never got generated on warm builds. The true source width now
    # comes from the image file itself.
    it "does not reuse when the config gains a width the true source can satisfy (A11)" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.png")
        pixels = Array(UInt8).new(1200 * 8 * 3, 128_u8)
        LibStb.stbi_write_png(source, 1200, 8, 3, pixels.to_unsafe.as(Void*), 1200 * 3)

        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        # Only the old config's [320] variant exists. The source is 1200px
        # wide, so a newly configured 1024 variant is NOT a clamp — the set
        # must be reprocessed.
        File.write(File.join(dest_dir, "photo_320w.png"), "320")

        Hwaro::Content::Hooks::ImageHooks
          .reusable_widths(source, dest_dir, [320, 1024])
          .should be_nil
      end
    end

    it "still reuses when the on-disk variants cover the config for the true source width (A11)" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.png")
        pixels = Array(UInt8).new(1200 * 8 * 3, 128_u8)
        LibStb.stbi_write_png(source, 1200, 8, 3, pixels.to_unsafe.as(Void*), 1200 * 3)

        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "photo_320w.png"), "320")
        File.write(File.join(dest_dir, "photo_1024w.png"), "1024")

        # Variants made safely after the source (racy-git).
        File.touch(source, Time.utc - 1.hour)
        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320, 1024])
        result.should_not be_nil
        result.not_nil!.should eq({320 => "photo_320w.png", 1024 => "photo_1024w.png"})
      end
    end

    it "reuses the clamped variant when a configured width exceeds the TRUE source width (A11)" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "photo.png")
        pixels = Array(UInt8).new(640 * 8 * 3, 128_u8)
        LibStb.stbi_write_png(source, 640, 8, 3, pixels.to_unsafe.as(Void*), 640 * 3)

        dest_dir = File.join(dir, "out")
        Dir.mkdir_p(dest_dir)
        # 1280 clamps to the 640px source, so the on-disk {320, 640} set is
        # exactly what the current config produces → reuse.
        File.write(File.join(dest_dir, "photo_320w.png"), "320")
        File.write(File.join(dest_dir, "photo_640w.png"), "640")

        # Variants made safely after the source (racy-git).
        File.touch(source, Time.utc - 1.hour)
        result = Hwaro::Content::Hooks::ImageHooks.reusable_widths(source, dest_dir, [320, 1280])
        result.should_not be_nil
        result.not_nil!.should eq({320 => "photo_320w.png", 640 => "photo_640w.png"})
      end
    end
  end
end

# Raw bytes of a w×h grey PNG, for build_site file maps.
private def png_body(w : Int32, h : Int32) : String
  Dir.mktmpdir do |dir|
    path = File.join(dir, "x.png")
    px = Bytes.new(w * h * 3, 90_u8)
    LibStb.stbi_write_png(path, w, h, 3, px.to_unsafe.as(Void*), w * 3)
    File.read(path)
  end
end

# Raw bytes of a noisy w×h JPEG (noise keeps the size sensitive to quality).
private def jpg_body(w : Int32, h : Int32, seed : Int32) : String
  Dir.mktmpdir do |dir|
    path = File.join(dir, "x.jpg")
    rng = Random.new(seed)
    px = Bytes.new(w * h * 3) { rng.rand(256).to_u8 }
    LibStb.stbi_write_jpg(path, w, h, 3, px.to_unsafe.as(Void*), 90)
    File.read(path)
  end
end

private def png_size(path : String) : {Int32, Int32}?
  Hwaro::Content::Processors::ImageProcessor.dimensions(path)
end

describe "resize_image fill/crop variants and content image dimensions (build)" do
  it "writes op variants at render time, sizes content images, and keeps both on warm builds" do
    page_tpl = <<-HTML
      {{ content }}
      {% set f = resize_image(path=page.url ~ "pic.png", width=20, height=20, op="fill", anchor="bottom_right") %}F={{ f.url }} {{ f.width }}x{{ f.height }}
      {% set c = resize_image(path="/img/a.png", width=8, height=50, op="crop") %}C={{ c.url }} {{ c.width }}x{{ c.height }}
      HTML
    build_site(
      %(title = "t"\nbase_url = "https://example.com/sub"\n[image_processing]\ndimensions = true\n),
      content_files: {"posts/b/index.md" => "+++\ntitle = \"B\"\n+++\n![p](pic.png) ![a](/img/a.png)\n", "posts/b/pic.png" => png_body(40, 10)},
      template_files: {"page.html" => page_tpl, "section.html" => "{{ content }}", "index.html" => "{{ content }}"},
      static_files: {"img/a.png" => png_body(12, 30)},
      cache: true,
    ) do
      html = File.read("public/posts/b/index.html")
      html.should contain(%(<img width="40" height="10" src="pic.png"))
      html.should contain(%(<img width="12" height="30" src="/sub/img/a.png"))
      html.should contain("F=https://example.com/sub/posts/b/pic_20x20_fill_bottom_right.png 20x20")
      html.should contain("C=https://example.com/sub/img/a_8x50_crop_center.png 8x30")
      png_size("public/posts/b/pic_20x20_fill_bottom_right.png").should eq({20, 20})
      png_size("public/img/a_8x50_crop_center.png").should eq({8, 30})

      # A warm build skips the page; its variants must survive the prune.
      2.times do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
        builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true, highlight: false, parallel: false))
      end
      File.exists?("public/posts/b/pic_20x20_fill_bottom_right.png").should be_true
      File.exists?("public/img/a_8x50_crop_center.png").should be_true
    end
  end
end

private def rebuild_cached : Nil
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true, highlight: false, parallel: false))
end

describe "ImageHooks render-time lookups (review fixes)" do
  it "resolves no source for a url carrying a NUL byte instead of raising" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        Dir.mkdir_p("static")
        File.write("static/a.png", png_body(2, 2))
        config = Hwaro::Models::Config.new
        Hwaro::Content::Hooks::ImageHooks.resolve_source("/a.png", config).should eq("static/a.png")
        Hwaro::Content::Hooks::ImageHooks.resolve_source("/a\0.png", config).should be_nil
      end
    end
  end

  it "writes a fill variant of a ../ path at its canonical place, with no stray directory" do
    build_site(
      %(title = "t"\nbase_url = "https://example.com"\n),
      content_files: {"about.md" => "+++\ntitle = \"About\"\n+++\nabout\n"},
      template_files: {
        "page.html" => %({% set v = resize_image(path="/sub/../img/a.png?v=3", width=10, height=10, op="fill") %}V={{ v.url }}),
        "section.html" => "{{ content }}", "index.html" => "{{ content }}",
      },
      static_files: {"img/a.png" => png_body(12, 30)},
    ) do
      File.read("public/about/index.html").should contain("V=https://example.com/img/a_10x10_fill_center.png?v=3")
      png_size("public/img/a_10x10_fill_center.png").should eq({10, 10})
      Dir.exists?("public/sub").should be_false
    end
  end

  it "regenerates warm variants after a quality change or a source swapped for an older-mtime file" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        config = ->(quality : Int32) {
          File.write("config.toml", %(title = "t"\nbase_url = "https://example.com"\n[image_processing]\nenabled = true\nwidths = [40]\nquality = #{quality}\n))
        }
        config.call(95)
        Dir.mkdir_p("content")
        Dir.mkdir_p("templates")
        Dir.mkdir_p("static")
        File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")
        tpl = %({% set v = resize_image(path="/p.jpg", width=30, height=20, op="fill") %}{{ v.url }}{{ content }})
        %w[index page section].each { |name| File.write("templates/#{name}.html", tpl) }
        File.write("static/p.jpg", jpg_body(120, 80, 1))
        File.touch("static/p.jpg", Time.utc - 1.hour)

        rebuild_cached
        wide = File.size("public/p_40w.jpg")
        fill = File.size("public/p_30x20_fill_center.jpg")

        config.call(5)
        rebuild_cached
        File.size("public/p_40w.jpg").should be < wide
        File.size("public/p_30x20_fill_center.jpg").should be < fill

        # Same quality again: nothing is rewritten.
        before = {File.read("public/p_40w.jpg"), File.info("public/p_40w.jpg").modification_time}
        rebuild_cached
        {File.read("public/p_40w.jpg"), File.info("public/p_40w.jpg").modification_time}.should eq(before)

        # rsync -a / tar -x / a restored revision: new bytes, OLDER mtime.
        File.write("static/p.jpg", jpg_body(120, 80, 2))
        File.touch("static/p.jpg", Time.utc - 2.hours)
        rebuild_cached
        File.read("public/p_40w.jpg").should_not eq(before[0])
      end
    end
  end

  it "never overwrites a published file that sits on a width variant's name" do
    build_site(
      %(title = "t"\nbase_url = "https://example.com"\n[image_processing]\nenabled = true\nwidths = [20, 40]\n),
      content_files: {"index.md" => "+++\ntitle = \"Home\"\n+++\n![h](/hero.png)\n"},
      template_files: {"page.html" => "{{ content }}", "section.html" => "{{ content }}", "index.html" => "{{ content }}"},
      static_files: {"hero.png" => png_body(100, 50), "hero_20w.png" => png_body(60, 30)},
      cache: true,
    ) do
      check = -> {
        png_size("public/hero_20w.png").should eq({60, 30})
        png_size("public/hero_40w.png").should eq({40, 20})
        html = File.read("public/index.html")
        html.should contain("hero_40w.png 40w")
        html.should_not contain("hero_20w.png 20w")
      }
      check.call
      # Warm builds reuse the variant set without regenerating the authored name.
      2.times do
        rebuild_cached
        check.call
      end
    end
  end

  it "never publishes a fill variant of a withheld (draft) bundle's image" do
    build_site(
      %(title = "t"\nbase_url = "https://example.com"\n[content.files]\nallow_extensions = ["png"]\n),
      content_files: {
        "posts/dr/index.md"   => "+++\ntitle = \"Draft\"\ndraft = true\n+++\nhidden\n",
        "posts/dr/secret.png" => png_body(20, 20),
        "about.md"            => "+++\ntitle = \"About\"\n+++\nabout\n",
      },
      template_files: {
        "page.html" => %({% set v = resize_image(path="/posts/dr/secret.png", width=10, height=10, op="fill") %}V={{ v.url }}),
        "section.html" => "{{ content }}", "index.html" => "{{ content }}",
      },
    ) do
      File.read("public/about/index.html").should contain("V=https://example.com/posts/dr/secret.png")
      Dir.exists?("public/posts/dr").should be_false
    end
  end

  it "re-reads an image's size when its bytes change at the same path" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        Hwaro::Content::Hooks::ImageHooks.clear_intrinsic_sizes
        File.write("a.png", png_body(6, 3))
        Hwaro::Content::Hooks::ImageHooks.intrinsic_size("a.png").should eq({6, 3})
        File.write("a.png", png_body(9, 5))
        File.touch("a.png", Time.local + 2.seconds)
        Hwaro::Content::Hooks::ImageHooks.intrinsic_size("a.png").should eq({9, 5})
        Hwaro::Content::Hooks::ImageHooks.clear_intrinsic_sizes
      end
    end
  end

  it "does not pass off a static file that sits on the variant's name as the variant" do
    build_site(
      %(title = "t"\nbase_url = "https://example.com"\n),
      content_files: {"about.md" => "+++\ntitle = \"About\"\n+++\nabout\n"},
      template_files: {
        "page.html" => %({% set v = resize_image(path="/img/a.png", width=10, height=10, op="fill") %}V={{ v.width }}x{{ v.height }}),
        "section.html" => "{{ content }}", "index.html" => "{{ content }}",
      },
      static_files: {"img/a.png" => png_body(12, 30), "img/a_10x10_fill_center.png" => png_body(4, 4)},
      cache: true,
    ) do
      File.read("public/about/index.html").should contain("V=10x10")
      png_size("public/img/a_10x10_fill_center.png").should eq({10, 10})
      rebuild_cached
      png_size("public/img/a_10x10_fill_center.png").should eq({10, 10})
    end
  end
end
