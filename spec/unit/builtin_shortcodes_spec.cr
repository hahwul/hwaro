require "../spec_helper"
require "../../src/core/build/builtin_shortcodes"

describe Hwaro::Core::Build::BuiltinShortcodes do
  describe ".templates" do
    it "returns a non-empty hash" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.should_not be_empty
    end

    it "contains youtube shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/youtube").should be_true
      templates["shortcodes/youtube"].should contain("youtube.com/embed")
    end

    it "contains vimeo shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/vimeo").should be_true
      templates["shortcodes/vimeo"].should contain("player.vimeo.com/video")
    end

    it "contains gist shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/gist").should be_true
      templates["shortcodes/gist"].should contain("gist.github.com")
    end

    it "contains alert shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/alert").should be_true
      templates["shortcodes/alert"].should contain("sc-alert")
    end

    it "contains callout as alias for alert" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/callout").should be_true
      templates["shortcodes/callout"].should eq(templates["shortcodes/alert"])
    end

    it "contains figure shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/figure").should be_true
      templates["shortcodes/figure"].should contain("sc-figure")
      templates["shortcodes/figure"].should contain("<figcaption>")
    end

    it "contains tweet shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/tweet").should be_true
      templates["shortcodes/tweet"].should contain("twitter-tweet")
    end

    it "contains codepen shortcode" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates.has_key?("shortcodes/codepen").should be_true
      templates["shortcodes/codepen"].should contain("codepen.io")
    end

    it "all templates have safe defaults for optional attributes" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      # youtube, vimeo, codepen use default() filter for width/height
      templates["shortcodes/youtube"].should contain("default(value=")
      templates["shortcodes/vimeo"].should contain("default(value=")
      templates["shortcodes/codepen"].should contain("default(value=")
    end

    it "all templates use HTML escaping with | e filter" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      ["shortcodes/youtube", "shortcodes/vimeo", "shortcodes/gist",
       "shortcodes/figure", "shortcodes/tweet", "shortcodes/codepen"].each do |key|
        templates[key].should contain("| e ")
      end
    end

    it "youtube template uses lazy loading" do
      templates = Hwaro::Core::Build::BuiltinShortcodes.templates
      templates["shortcodes/youtube"].should contain("loading=\"lazy\"")
    end

    it "returns the same instance on repeated calls (cached)" do
      t1 = Hwaro::Core::Build::BuiltinShortcodes.templates
      t2 = Hwaro::Core::Build::BuiltinShortcodes.templates
      t1.object_id.should eq(t2.object_id)
    end
  end

  # Backs the dispatcher-level alias from `_N` to the corresponding named
  # parameter — see https://github.com/hahwul/hwaro/issues/479.
  describe ".positional_params" do
    it "exposes positional names for every built-in template that has a documented positional form" do
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/youtube").should eq(["id"])
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/vimeo").should eq(["id"])
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/gist").should eq(["user", "id", "file"])
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/tweet").should eq(["user", "id"])
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/codepen").should eq(["user", "id"])
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/figure").should eq(["src", "alt", "caption"])
    end

    it "returns nil for unknown templates so user shortcodes keep using `_N` directly" do
      Hwaro::Core::Build::BuiltinShortcodes.positional_params("shortcodes/custom-thing").should be_nil
    end
  end
end
