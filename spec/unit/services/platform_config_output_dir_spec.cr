require "../../spec_helper"
require "../../../src/services/platform_config"

# `hwaro tool platform` hardcoded "public" as the publish directory, so a site
# with a customized `[build] output_dir` generated a config pointing at a
# directory the build never writes. Nothing errored anywhere: the build
# succeeded, the host published an empty (or stale) tree, and the only symptom
# was a blank site.
private def platform_config_with(output_dir : String?) : Hwaro::Services::PlatformConfig
  config = Hwaro::Models::Config.new
  config.build.output_dir = output_dir
  Hwaro::Services::PlatformConfig.new(config)
end

describe "PlatformConfig honors [build] output_dir" do
  it "points netlify's publish at the configured output_dir" do
    generator = platform_config_with("dist")
    generator.generate("netlify").should contain(%(publish = "dist"))
  end

  it "points vercel's outputDirectory at the configured output_dir" do
    generator = platform_config_with("dist")
    JSON.parse(generator.generate("vercel"))["outputDirectory"].as_s.should eq("dist")
  end

  it "points cloudflare's bucket and dashboard note at the configured output_dir" do
    generator = platform_config_with("dist")
    result = generator.generate("cloudflare")
    result.should contain(%(bucket = "./dist"))
    result.should contain("# Build output directory: /dist")
  end

  it "publishes the configured output_dir from the gitlab-ci pages job" do
    generator = platform_config_with("dist")
    result = generator.generate("gitlab-ci")
    # `pages.publish` is what points GitLab Pages away from `public/`;
    # the artifact has to carry the same directory.
    result.should contain("  publish: dist")
    result.should contain("      - dist")
    result.should_not contain("      - public")
  end

  it "cds into the configured output_dir in the codeberg-pages workflow" do
    generator = platform_config_with("dist")
    result = generator.generate("codeberg-pages")
    result.should contain("cd dist")
    result.should_not contain("cd public")
  end

  # The default site must keep generating exactly what it generated before,
  # including staying free of the `pages.publish` key that older GitLab
  # instances do not understand.
  it "leaves the default (unset) output_dir rendering as public" do
    generator = platform_config_with(nil)
    generator.generate("netlify").should contain(%(publish = "public"))
    JSON.parse(generator.generate("vercel"))["outputDirectory"].as_s.should eq("public")
    generator.generate("cloudflare").should contain(%(bucket = "./public"))
    generator.generate("codeberg-pages").should contain("cd public")

    gitlab = generator.generate("gitlab-ci")
    gitlab.should contain("      - public")
    gitlab.should_not contain("publish:")
  end

  # `[build] output_dir` is trusted config, but a directory name may still
  # legitimately contain a space or a quote — the emitted file has to stay
  # parseable/runnable rather than splitting mid-value.
  it "quotes an awkward output_dir for each output format" do
    generator = platform_config_with(%(my "site" out))

    netlify_fm = generator.generate("netlify").match!(/\A(.*?)\n\[build\.environment\]/m)[1]
    TOML.parse(netlify_fm)["build"].as_h["publish"].as_s.should eq(%(my "site" out))

    JSON.parse(generator.generate("vercel"))["outputDirectory"].as_s.should eq(%(my "site" out))
    generator.generate("codeberg-pages").should contain(%(cd 'my "site" out'))
    generator.generate("gitlab-ci").should contain(%(      - "my \\"site\\" out"))
  end
end

describe "PlatformConfig normalizes [build] output_dir" do
  it "treats ./public and public/ as the default directory" do
    %w[./public public/ ./public/].each do |dir|
      generator = platform_config_with(dir)
      generator.generate("gitlab-ci").should_not contain("publish:")
      generator.generate("cloudflare").should contain(%(bucket = "./public"))
      generator.generate("netlify").should contain(%(publish = "public"))
    end
  end

  it "normalizes a ./-prefixed custom directory" do
    generator = platform_config_with("./build/out/")
    generator.generate("netlify").should contain(%(publish = "build/out"))
    generator.generate("cloudflare").should contain(%(bucket = "./build/out"))
  end

  it "falls back to public for an absolute output_dir and says so" do
    generator = platform_config_with("/tmp/hwaro-abs-out")
    log = with_captured_log do
      generator.generate("netlify").should contain(%(publish = "public"))
    end
    log.should contain("absolute")
    generator.generate("gitlab-ci").should_not contain("/tmp/hwaro-abs-out")
  end
end
