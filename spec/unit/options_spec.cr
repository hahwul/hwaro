require "../spec_helper"

describe Hwaro::Config::Options::BuildOptions do
  it "has default values" do
    options = Hwaro::Config::Options::BuildOptions.new
    options.output_dir.should eq("public")
    options.base_url.should be_nil
    options.drafts.should be_false
    options.minify.should be_false
    options.parallel.should be_true
    options.cache.should be_false
    options.profile.should be_false
    options.cache_busting.should be_true
    options.stream.should be_false
    options.memory_limit.should be_nil
  end

  it "accepts custom values" do
    options = Hwaro::Config::Options::BuildOptions.new(
      output_dir: "dist",
      base_url: "https://example.com",
      drafts: true,
      minify: true,
      parallel: false,
      cache: true,
      profile: true,
      cache_busting: false
    )
    options.output_dir.should eq("dist")
    options.base_url.should eq("https://example.com")
    options.drafts.should be_true
    options.minify.should be_true
    options.parallel.should be_false
    options.cache.should be_true
    options.profile.should be_true
    options.cache_busting.should be_false
  end

  describe "#streaming?" do
    it "returns false by default" do
      options = Hwaro::Config::Options::BuildOptions.new
      options.streaming?.should be_false
    end

    it "returns true when stream is set" do
      options = Hwaro::Config::Options::BuildOptions.new(stream: true)
      options.streaming?.should be_true
    end

    it "returns true when memory_limit is set" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "512M")
      options.streaming?.should be_true
    end

    it "returns true when both stream and memory_limit are set" do
      options = Hwaro::Config::Options::BuildOptions.new(stream: true, memory_limit: "2G")
      options.streaming?.should be_true
    end
  end

  describe "#batch_size" do
    it "returns 500 by default (stream without memory_limit)" do
      options = Hwaro::Config::Options::BuildOptions.new(stream: true)
      options.batch_size.should eq(500)
    end

    it "calculates batch size from gigabytes" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "2G")
      # 2G = 2*1024*1024*1024 bytes / (50*1024) = ~41943
      options.batch_size.should eq(41943)
    end

    it "calculates batch size from megabytes" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "512M")
      # 512M = 512*1024*1024 bytes / (50*1024) = 10485
      options.batch_size.should eq(10485)
    end

    it "calculates batch size from kilobytes" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "256K")
      # 256K = 256*1024 bytes / (50*1024) = 5
      options.batch_size.should eq(5)
    end

    it "returns minimum batch size of 1 for very small limits" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "1K")
      options.batch_size.should eq(1)
    end

    it "raises on invalid memory limit format" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "abc")
      expect_raises(Exception, /Invalid memory limit format/) do
        options.batch_size
      end
    end

    it "handles lowercase unit suffixes" do
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "1g")
      options.batch_size.should eq(20971)
    end

    it "clamps to Int32::MAX for very large limits" do
      # Need bytes / (50*1024) > Int32::MAX (~2.1B), so > ~102TB
      options = Hwaro::Config::Options::BuildOptions.new(memory_limit: "999999G")
      options.batch_size.should eq(Int32::MAX)
    end
  end
end

describe Hwaro::Config::Options::ServeOptions do
  it "has default values" do
    options = Hwaro::Config::Options::ServeOptions.new
    options.host.should eq("127.0.0.1")
    options.port.should eq(3000)
    options.base_url.should be_nil
    options.drafts.should be_false
    options.open_browser.should be_false
    options.cache_busting.should be_true
  end

  it "converts to build options" do
    options = Hwaro::Config::Options::ServeOptions.new(drafts: true, base_url: "https://example.com")
    build_options = options.to_build_options
    build_options.drafts.should be_true
    build_options.output_dir.should eq("public")
    build_options.base_url.should eq("https://example.com")
    build_options.cache_busting.should be_true
    build_options.stream.should be_false
    build_options.memory_limit.should be_nil
  end

  it "passes cache_busting to build options" do
    options = Hwaro::Config::Options::ServeOptions.new(cache_busting: false)
    build_options = options.to_build_options
    build_options.cache_busting.should be_false
  end
end

describe Hwaro::Config::Options::ScaffoldType do
  describe ".from_string" do
    it "parses 'simple'" do
      Hwaro::Config::Options::ScaffoldType.from_string("simple").should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end

    it "parses 'blog'" do
      Hwaro::Config::Options::ScaffoldType.from_string("blog").should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    end

    it "parses 'docs'" do
      Hwaro::Config::Options::ScaffoldType.from_string("docs").should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end

    it "is case-insensitive" do
      Hwaro::Config::Options::ScaffoldType.from_string("BLOG").should eq(Hwaro::Config::Options::ScaffoldType::Blog)
      Hwaro::Config::Options::ScaffoldType.from_string("Docs").should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end

    it "raises for unknown type" do
      expect_raises(ArgumentError, /Unknown scaffold type/) do
        Hwaro::Config::Options::ScaffoldType.from_string("unknown")
      end
    end
  end

  describe "#to_s" do
    it "converts Simple to 'simple'" do
      Hwaro::Config::Options::ScaffoldType::Simple.to_s.should eq("simple")
    end

    it "converts Blog to 'blog'" do
      Hwaro::Config::Options::ScaffoldType::Blog.to_s.should eq("blog")
    end

    it "converts Docs to 'docs'" do
      Hwaro::Config::Options::ScaffoldType::Docs.to_s.should eq("docs")
    end
  end
end

describe Hwaro::Config::Options::InitOptions do
  it "has default values" do
    options = Hwaro::Config::Options::InitOptions.new
    options.path.should eq(".")
    options.force.should be_false
    options.skip_agents_md.should be_false
    options.skip_sample_content.should be_false
    options.skip_taxonomies.should be_false
    options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    options.scaffold_remote.should be_nil
  end

  describe "#multilingual?" do
    it "returns false when no languages are set" do
      options = Hwaro::Config::Options::InitOptions.new
      options.multilingual?.should be_false
    end

    it "returns false when only one language is set" do
      options = Hwaro::Config::Options::InitOptions.new(multilingual_languages: ["en"])
      options.multilingual?.should be_false
    end

    it "returns true when multiple languages are set" do
      options = Hwaro::Config::Options::InitOptions.new(multilingual_languages: ["en", "ko"])
      options.multilingual?.should be_true
    end
  end
end

describe Hwaro::Config::Options::ImportOptions do
  it "has default values" do
    options = Hwaro::Config::Options::ImportOptions.new
    options.source_type.should eq("")
    options.path.should eq("")
    options.output_dir.should eq("content")
    options.drafts.should be_false
    options.verbose.should be_false
  end

  it "accepts all parameters" do
    options = Hwaro::Config::Options::ImportOptions.new(
      source_type: "jekyll",
      path: "/tmp/jekyll-site",
      output_dir: "imported",
      drafts: true,
      verbose: true
    )
    options.source_type.should eq("jekyll")
    options.path.should eq("/tmp/jekyll-site")
    options.output_dir.should eq("imported")
    options.drafts.should be_true
    options.verbose.should be_true
  end

  it "accepts partial parameters" do
    options = Hwaro::Config::Options::ImportOptions.new(source_type: "hugo", path: "/tmp/hugo")
    options.source_type.should eq("hugo")
    options.path.should eq("/tmp/hugo")
    options.output_dir.should eq("content")
    options.drafts.should be_false
  end
end

describe Hwaro::Config::Options::DeployOptions do
  it "has default values" do
    options = Hwaro::Config::Options::DeployOptions.new
    options.source_dir.should be_nil
    options.targets.should be_empty
    options.dry_run.should be_nil
    options.confirm.should be_nil
    options.force.should be_nil
    options.max_deletes.should be_nil
    options.env.should be_nil
  end

  it "accepts all parameters" do
    options = Hwaro::Config::Options::DeployOptions.new(
      source_dir: "dist",
      targets: ["production", "staging"],
      dry_run: true,
      confirm: false,
      force: true,
      max_deletes: 100,
      env: "production"
    )
    options.source_dir.should eq("dist")
    options.targets.should eq(["production", "staging"])
    options.dry_run.should be_true
    options.confirm.should be_false
    options.force.should be_true
    options.max_deletes.should eq(100)
    options.env.should eq("production")
  end

  it "accepts partial parameters" do
    options = Hwaro::Config::Options::DeployOptions.new(
      targets: ["staging"],
      dry_run: true
    )
    options.source_dir.should be_nil
    options.targets.should eq(["staging"])
    options.dry_run.should be_true
    options.force.should be_nil
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
