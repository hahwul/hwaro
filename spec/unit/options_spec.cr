require "../spec_helper"

describe Hwaro::Config::Options::BuildOptions do
  it "has default values" do
    options = Hwaro::Config::Options::BuildOptions.new
    options.output_dir.should eq("public")
    options.drafts.should eq(false)
    options.minify.should eq(false)
    options.parallel.should eq(true)
    options.cache.should eq(false)
  end

  it "accepts custom values" do
    options = Hwaro::Config::Options::BuildOptions.new(
      output_dir: "dist",
      drafts: true,
      minify: true,
      parallel: false,
      cache: true
    )
    options.output_dir.should eq("dist")
    options.drafts.should eq(true)
    options.minify.should eq(true)
    options.parallel.should eq(false)
    options.cache.should eq(true)
  end
end

describe Hwaro::Config::Options::ServeOptions do
  it "has default values" do
    options = Hwaro::Config::Options::ServeOptions.new
    options.host.should eq("0.0.0.0")
    options.port.should eq(3000)
    options.drafts.should eq(false)
    options.open_browser.should eq(false)
  end

  it "converts to build options" do
    options = Hwaro::Config::Options::ServeOptions.new(drafts: true)
    build_options = options.to_build_options
    build_options.drafts.should eq(true)
    build_options.output_dir.should eq("public")
  end
end

describe Hwaro::Config::Options::InitOptions do
  it "has default values" do
    options = Hwaro::Config::Options::InitOptions.new
    options.path.should eq(".")
    options.force.should eq(false)
  end
end
