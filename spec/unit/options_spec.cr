require "../spec_helper"

describe Hwaro::Config::Options::BuildOptions do
  it "has default values" do
    options = Hwaro::Config::Options::BuildOptions.new
    options.output_dir.should eq("public")
    options.base_url.should be_nil
    options.drafts.should eq(false)
    options.minify.should eq(false)
    options.parallel.should eq(true)
    options.cache.should eq(false)
    options.profile.should eq(false)
  end

  it "accepts custom values" do
    options = Hwaro::Config::Options::BuildOptions.new(
      output_dir: "dist",
      base_url: "https://example.com",
      drafts: true,
      minify: true,
      parallel: false,
      cache: true,
      profile: true
    )
    options.output_dir.should eq("dist")
    options.base_url.should eq("https://example.com")
    options.drafts.should eq(true)
    options.minify.should eq(true)
    options.parallel.should eq(false)
    options.cache.should eq(true)
    options.profile.should eq(true)
  end
end

describe Hwaro::Config::Options::ServeOptions do
  it "has default values" do
    options = Hwaro::Config::Options::ServeOptions.new
    options.host.should eq("0.0.0.0")
    options.port.should eq(3000)
    options.base_url.should be_nil
    options.drafts.should eq(false)
    options.open_browser.should eq(false)
  end

  it "converts to build options" do
    options = Hwaro::Config::Options::ServeOptions.new(drafts: true, base_url: "https://example.com")
    build_options = options.to_build_options
    build_options.drafts.should eq(true)
    build_options.output_dir.should eq("public")
    build_options.base_url.should eq("https://example.com")
  end
end

describe Hwaro::Config::Options::InitOptions do
  it "has default values" do
    options = Hwaro::Config::Options::InitOptions.new
    options.path.should eq(".")
    options.force.should eq(false)
  end
end

describe Hwaro::Config::Options::NewOptions do
  it "has default values" do
    options = Hwaro::Config::Options::NewOptions.new
    options.path.should be_nil
    options.title.should be_nil
    options.archetype.should be_nil
  end

  it "accepts all parameters" do
    options = Hwaro::Config::Options::NewOptions.new(
      path: "posts/my-post.md",
      title: "My Post",
      archetype: "posts"
    )
    options.path.should eq("posts/my-post.md")
    options.title.should eq("My Post")
    options.archetype.should eq("posts")
  end

  it "accepts partial parameters" do
    options = Hwaro::Config::Options::NewOptions.new(title: "Test Title")
    options.path.should be_nil
    options.title.should eq("Test Title")
    options.archetype.should be_nil
  end
end
