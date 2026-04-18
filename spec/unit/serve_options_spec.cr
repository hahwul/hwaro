require "../spec_helper"
require "../../src/config/options/serve_options"

describe Hwaro::Config::Options::ServeOptions do
  describe "#initialize" do
    it "has sensible defaults" do
      opts = Hwaro::Config::Options::ServeOptions.new
      opts.host.should eq("127.0.0.1")
      opts.port.should eq(3000)
      opts.base_url.should be_nil
      opts.drafts.should be_false
      opts.include_expired.should be_false
      opts.include_future.should be_false
      opts.minify.should be_false
      opts.open_browser.should be_false
      opts.verbose.should be_false
      opts.debug.should be_false
      opts.access_log.should be_false
      opts.error_overlay.should be_true
      opts.live_reload.should be_true
      opts.profile.should be_false
      opts.cache_busting.should be_true
      opts.env.should be_nil
    end

    it "accepts custom values" do
      opts = Hwaro::Config::Options::ServeOptions.new(
        host: "0.0.0.0",
        port: 8080,
        drafts: true,
        open_browser: true,
        live_reload: true,
      )
      opts.host.should eq("0.0.0.0")
      opts.port.should eq(8080)
      opts.drafts.should be_true
      opts.open_browser.should be_true
      opts.live_reload.should be_true
    end
  end

  describe "#to_build_options" do
    it "converts to BuildOptions with matching fields" do
      serve = Hwaro::Config::Options::ServeOptions.new(
        base_url: "https://example.com",
        drafts: true,
        include_expired: true,
        include_future: true,
        minify: true,
        verbose: true,
        profile: true,
        debug: true,
        error_overlay: false,
        cache_busting: false,
        env: "staging",
      )

      build = serve.to_build_options
      build.output_dir.should eq("public")
      build.base_url.should eq("https://example.com")
      build.drafts.should be_true
      build.include_expired.should be_true
      build.include_future.should be_true
      build.minify.should be_true
      build.parallel.should be_true
      build.verbose.should be_true
      build.profile.should be_true
      build.debug.should be_true
      build.error_overlay.should be_false
      build.cache_busting.should be_false
      build.stream.should be_false
      build.memory_limit.should be_nil
      build.env.should eq("staging")
    end

    it "defaults produce valid BuildOptions" do
      serve = Hwaro::Config::Options::ServeOptions.new
      build = serve.to_build_options
      build.should_not be_nil
      build.streaming?.should be_false
    end

    it "derives base_url from host and port when not explicitly set" do
      serve = Hwaro::Config::Options::ServeOptions.new(host: "0.0.0.0", port: 8080)
      build = serve.to_build_options
      build.base_url.should eq("http://0.0.0.0:8080")
    end

    it "uses default host:port for base_url when no options provided" do
      serve = Hwaro::Config::Options::ServeOptions.new
      build = serve.to_build_options
      build.base_url.should eq("http://127.0.0.1:3000")
    end

    it "preserves explicit --base-url over derived host:port" do
      serve = Hwaro::Config::Options::ServeOptions.new(port: 8080, base_url: "https://example.com")
      build = serve.to_build_options
      build.base_url.should eq("https://example.com")
    end
  end
end
