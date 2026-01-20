require "../spec_helper"

describe Hwaro::Models::Config do
  it "has default values" do
    config = Hwaro::Models::Config.new
    config.title.should eq("Hwaro Site")
    config.description.should eq("")
    config.base_url.should eq("")
    config.sitemap.enabled.should eq(false)
    config.feeds.enabled.should eq(false)
    config.search.enabled.should eq(false)
    config.taxonomies.should eq([] of Hwaro::Models::TaxonomyConfig)
  end

  it "has default search configuration" do
    config = Hwaro::Models::Config.new
    config.search.enabled.should eq(false)
    config.search.format.should eq("fuse_json")
    config.search.fields.should eq(["title", "content"])
    config.search.filename.should eq("search.json")
  end

  it "has default plugin configuration" do
    config = Hwaro::Models::Config.new
    config.plugins.processors.should eq(["markdown"])
  end

  it "has default pagination configuration" do
    config = Hwaro::Models::Config.new
    config.pagination.enabled.should eq(false)
    config.pagination.per_page.should eq(10)
  end

  it "has default highlight configuration" do
    config = Hwaro::Models::Config.new
    config.highlight.enabled.should eq(true)
    config.highlight.theme.should eq("github")
    config.highlight.use_cdn.should eq(true)
  end
end
