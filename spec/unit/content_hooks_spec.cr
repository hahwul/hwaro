require "../spec_helper"
require "../../src/content/hooks"

describe Hwaro::Content::Hooks do
  describe ".all" do
    it "returns an array of Hookable instances" do
      hooks = Hwaro::Content::Hooks.all
      hooks.should be_a(Array(Hwaro::Core::Lifecycle::Hookable))
    end

    it "returns exactly 8 hooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.size.should eq(8)
    end

    it "includes ImageHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::ImageHooks) }.should be_true
    end

    it "includes OgImageHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::OgImageHooks) }.should be_true
    end

    it "includes AmpHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::AmpHooks) }.should be_true
    end

    it "includes PwaHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::PwaHooks) }.should be_true
    end

    it "includes MarkdownHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::MarkdownHooks) }.should be_true
    end

    it "includes SeoHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::SeoHooks) }.should be_true
    end

    it "includes TaxonomyHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::TaxonomyHooks) }.should be_true
    end

    it "includes AssetHooks" do
      hooks = Hwaro::Content::Hooks.all
      hooks.any? { |h| h.is_a?(Hwaro::Content::Hooks::AssetHooks) }.should be_true
    end

    it "returns new instances each time" do
      hooks1 = Hwaro::Content::Hooks.all
      hooks2 = Hwaro::Content::Hooks.all
      hooks1.object_id.should_not eq(hooks2.object_id)
    end
  end
end
