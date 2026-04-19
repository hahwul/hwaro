require "../spec_helper"
require "../../src/config/options/build_options"

describe Hwaro::Config::Options::BuildOptions do
  describe "#initialize" do
    it "has sensible defaults" do
      opts = Hwaro::Config::Options::BuildOptions.new
      opts.output_dir.should eq("public")
      opts.base_url.should be_nil
      opts.drafts.should be_false
      opts.include_expired.should be_false
      opts.include_future.should be_false
      opts.minify.should be_false
      opts.parallel.should be_true
      opts.cache.should be_false
      opts.full.should be_false
      opts.highlight.should be_true
      opts.verbose.should be_false
      opts.profile.should be_false
      opts.debug.should be_false
      opts.error_overlay.should be_false
      opts.cache_busting.should be_true
      opts.stream.should be_false
      opts.memory_limit.should be_nil
      opts.env.should be_nil
      opts.preserve_output.should be_false
    end

    it "round-trips preserve_output" do
      # `preserve_output = true` is what `hwaro serve` flips on for watch
      # rebuilds so the output dir isn't wiped between keystrokes (see #389).
      opts = Hwaro::Config::Options::BuildOptions.new(preserve_output: true)
      opts.preserve_output.should be_true
    end

    it "accepts custom values" do
      opts = Hwaro::Config::Options::BuildOptions.new(
        output_dir: "dist",
        base_url: "https://example.com",
        drafts: true,
        minify: true,
        verbose: true,
        env: "production",
      )
      opts.output_dir.should eq("dist")
      opts.base_url.should eq("https://example.com")
      opts.drafts.should be_true
      opts.minify.should be_true
      opts.verbose.should be_true
      opts.env.should eq("production")
    end
  end

  describe "#streaming?" do
    it "returns false by default" do
      opts = Hwaro::Config::Options::BuildOptions.new
      opts.streaming?.should be_false
    end

    it "returns true when stream is set" do
      opts = Hwaro::Config::Options::BuildOptions.new(stream: true)
      opts.streaming?.should be_true
    end

    it "returns true when memory_limit is set" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "512M")
      opts.streaming?.should be_true
    end

    it "returns true when both stream and memory_limit are set" do
      opts = Hwaro::Config::Options::BuildOptions.new(stream: true, memory_limit: "1G")
      opts.streaming?.should be_true
    end
  end

  describe "#batch_size" do
    it "returns default batch size of 500 when no memory limit" do
      opts = Hwaro::Config::Options::BuildOptions.new
      opts.batch_size.should eq(500)
    end

    it "calculates batch size from gigabyte memory limit" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "1G")
      # 1GB / 50KB = ~20971
      opts.batch_size.should be > 1000
    end

    it "calculates batch size from megabyte memory limit" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "50M")
      # 50MB / 50KB = ~1024
      opts.batch_size.should be > 100
      opts.batch_size.should be <= 2000
    end

    it "calculates batch size from kilobyte memory limit" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "100K")
      # 100KB / 50KB = 2
      opts.batch_size.should eq(2)
    end

    it "clamps batch size to minimum 1" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "1K")
      # 1KB / 50KB would be 0, clamped to 1
      opts.batch_size.should eq(1)
    end

    it "handles plain bytes memory limit" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "51200")
      # 51200 bytes / 50KB = 1
      opts.batch_size.should eq(1)
    end

    it "raises on invalid memory limit format" do
      opts = Hwaro::Config::Options::BuildOptions.new(memory_limit: "invalid")
      expect_raises(Exception, /Invalid memory limit format/) do
        opts.batch_size
      end
    end
  end
end
