require "../../spec_helper"
require "../../../src/services/deployer"
require "../../../src/models/config"
require "../../../src/config/options/deploy_options"

# `include` / `exclude` / `strip_index_html` are honoured by the built-in
# file sync, which only runs for local `file://` and `path` destinations.
# Command-driven targets (an explicit `command`, or the auto-generated
# aws/gsutil/az sync for s3://, gs://, az://) hand the whole source tree to
# an external tool, so those keys silently had no effect — a target
# configured with `exclude = "**/*.map"` uploaded the sourcemaps anyway.
private def deploy_fixture(dir : String, &) : String
  source = File.join(dir, "public")
  FileUtils.mkdir_p(source)
  File.write(File.join(source, "index.html"), "<html></html>")
  File.write(File.join(source, "app.woff2"), "font")
  yield source
  source
end

private def run_dry(config : Hwaro::Models::Config, source : String, target : String) : String
  with_captured_log do
    Hwaro::Services::Deployer.new.run(
      Hwaro::Config::Options::DeployOptions.new(
        source_dir: source,
        targets: [target],
        dry_run: true,
      ),
      config
    )
  end
end

describe "deploy target options that the built-in sync cannot apply" do
  it "warns for a command-based target configured with exclude" do
    Dir.mktmpdir do |dir|
      deploy_fixture(dir) { }
      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "s3"
      target.url = "s3://mybucket"
      target.exclude = "**/*.woff2"
      config.deployment.targets << target

      log = run_dry(config, File.join(dir, "public"), "s3")
      log.should contain("not applied to command-based targets")
      log.should contain("exclude")
    end
  end

  it "names every unapplied key in one line" do
    Dir.mktmpdir do |dir|
      deploy_fixture(dir) { }
      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "gs"
      target.url = "gs://bucket"
      target.include = "**/*.html"
      target.exclude = "**/*.woff2"
      target.strip_index_html = true
      config.deployment.targets << target

      log = run_dry(config, File.join(dir, "public"), "gs")
      warn_lines = log.lines.select(&.includes?("not applied to command-based"))
      warn_lines.size.should eq(1)
      warn_lines.first.should contain("include/exclude/strip_index_html")
    end
  end

  it "warns for an explicit command target too" do
    Dir.mktmpdir do |dir|
      deploy_fixture(dir) { }
      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "custom"
      target.command = "echo deploying"
      target.strip_index_html = true
      config.deployment.targets << target

      log = run_dry(config, File.join(dir, "public"), "custom")
      log.should contain("not applied to command-based targets")
      log.should contain("strip_index_html")
    end
  end

  it "stays silent for a command target that configured none of them" do
    Dir.mktmpdir do |dir|
      deploy_fixture(dir) { }
      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "plain"
      target.url = "s3://plainbucket"
      config.deployment.targets << target

      log = run_dry(config, File.join(dir, "public"), "plain")
      log.should_not contain("not applied to command-based")
    end
  end

  it "stays silent for a local target, where the options do apply" do
    Dir.mktmpdir do |dir|
      deploy_fixture(dir) { }
      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "local"
      target.url = "file://#{File.join(dir, "out")}"
      target.exclude = "**/*.woff2"
      config.deployment.targets << target

      log = run_dry(config, File.join(dir, "public"), "local")
      log.should_not contain("not applied to command-based")
      # …and the exclusion really is honoured there.
      log.should_not contain("app.woff2")
      log.should contain("index.html")
    end
  end
end
