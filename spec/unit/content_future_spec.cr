require "../spec_helper"
require "../../src/models/config"
require "../../src/models/page"
require "../../src/config/options/build_options"
require "../../src/config/options/serve_options"

describe "Future-dated content filtering" do
  describe "BuildOptions" do
    it "has include_future defaulting to false" do
      options = Hwaro::Config::Options::BuildOptions.new
      options.include_future.should be_false
    end

    it "can be set to true" do
      options = Hwaro::Config::Options::BuildOptions.new(include_future: true)
      options.include_future.should be_true
    end
  end

  describe "ServeOptions" do
    it "has include_future defaulting to false" do
      options = Hwaro::Config::Options::ServeOptions.new
      options.include_future.should be_false
    end

    it "passes include_future to BuildOptions" do
      options = Hwaro::Config::Options::ServeOptions.new(include_future: true)
      build_options = options.to_build_options
      build_options.include_future.should be_true
    end
  end

  describe "Page date" do
    it "identifies future-dated page" do
      page = Hwaro::Models::Page.new("future.md")
      page.date = Time.utc(2099, 12, 31)
      now = Time.utc
      (page.date.not_nil! > now).should be_true
    end

    it "identifies past-dated page" do
      page = Hwaro::Models::Page.new("past.md")
      page.date = Time.utc(2020, 1, 1)
      now = Time.utc
      (page.date.not_nil! > now).should be_false
    end

    it "page without date is not considered future" do
      page = Hwaro::Models::Page.new("nodate.md")
      page.date.should be_nil
      (page.date.try { |d| d > Time.utc } || false).should be_false
    end
  end
end
