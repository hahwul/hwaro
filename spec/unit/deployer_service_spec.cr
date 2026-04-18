require "../spec_helper"
require "../../src/services/deployer"
require "../../src/models/config"
require "../../src/config/options/deploy_options"

describe Hwaro::Services::Deployer do
  describe "#run" do
    it "fails if no targets configured" do
      config = Hwaro::Models::Config.new
      deployer = Hwaro::Services::Deployer.new
      options = Hwaro::Config::Options::DeployOptions.new(targets: [] of String)

      result = deployer.run(options, config)
      result.should be_false
    end

    it "fails if unknown target specified" do
      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "production"
      target.url = "file:///tmp/prod"
      config.deployment.targets << target

      deployer = Hwaro::Services::Deployer.new
      options = Hwaro::Config::Options::DeployOptions.new(targets: ["staging"])

      result = deployer.run(options, config)
      result.should be_false
    end

    it "fails if source directory missing" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "production"
        target.url = "file://#{dir}/dest"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: "#{dir}/missing_src",
          targets: ["production"]
        )

        result = deployer.run(options, config)
        result.should be_false
      end
    end

    it "deploys to local directory" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "index.html"), "Hello World")
        File.write(File.join(src_dir, "style.css"), "body { color: red; }")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = "file://#{dest_dir}"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["local"]
        )

        result = deployer.run(options, config)
        result.should be_true

        File.exists?(File.join(dest_dir, "index.html")).should be_true
        File.read(File.join(dest_dir, "index.html")).should eq("Hello World")
        File.exists?(File.join(dest_dir, "style.css")).should be_true
      end
    end

    it "deploys via command" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)
        output_file = File.join(dir, "output.txt")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "cmd"
        # We use a simple command that writes to a file
        target.command = "echo 'deployed' > #{output_file}"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["cmd"]
        )

        result = deployer.run(options, config)
        result.should be_true

        File.exists?(output_file).should be_true
        File.read(output_file).strip.should eq("deployed")
      end
    end

    it "dry_run for directory deployment does not copy files" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "index.html"), "Hello World")
        File.write(File.join(src_dir, "style.css"), "body { color: red; }")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = "file://#{dest_dir}"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["local"],
          dry_run: true
        )

        result = deployer.run(options, config)
        result.should be_true

        # Files should not have been copied to destination
        File.exists?(File.join(dest_dir, "index.html")).should be_false
        File.exists?(File.join(dest_dir, "style.css")).should be_false
      end
    end

    it "dry_run for command deployment does not execute command" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)
        sentinel_file = File.join(dir, "sentinel.txt")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "cmd"
        target.command = "echo 'executed' > #{sentinel_file}"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["cmd"],
          dry_run: true
        )

        result = deployer.run(options, config)
        result.should be_true

        # Sentinel file should not exist
        File.exists?(sentinel_file).should be_false
      end
    end

    it "strips index.html when configured" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(File.join(src_dir, "foo"))
        File.write(File.join(src_dir, "foo", "index.html"), "Foo Content")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = "file://#{dest_dir}"
        target.strip_index_html = true
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["local"]
        )

        result = deployer.run(options, config)
        result.should be_true

        # index.html should be stripped to just "foo"
        # Since it is a file deployment, "foo" should become a file in dest_dir
        dest_file = File.join(dest_dir, "foo")
        File.exists?(dest_file).should be_true
        File.file?(dest_file).should be_true
        File.read(dest_file).should eq("Foo Content")
      end
    end
    it "auto-generates command for s3:// URL in dry_run" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "s3"
        target.url = "s3://my-bucket"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["s3"],
          dry_run: true
        )

        result = deployer.run(options, config)
        result.should be_true
      end
    end

    it "returns per-target DeployResult list for #deploy_structured happy path" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "index.html"), "Hello")
        File.write(File.join(src_dir, "style.css"), "body{}")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = "file://#{dest_dir}"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["local"]
        )

        results = deployer.deploy_structured(options, config)
        results.size.should eq(1)
        r = results.first
        r.name.should eq("local")
        r.status.should eq("ok")
        r.created.should eq(2)
        r.updated.should eq(0)
        r.deleted.should eq(0)
        r.duration_ms.should be >= 0.0
        r.error.should be_nil

        # Second run: same content should produce all-skipped (no create/update/delete)
        results2 = deployer.deploy_structured(options, config)
        r2 = results2.first
        r2.status.should eq("ok")
        r2.created.should eq(0)
        r2.updated.should eq(0)
        r2.deleted.should eq(0)
      end
    end

    it "serializes DeployResult as JSON with required fields" do
      result = Hwaro::Services::Deployer::DeployResult.new(
        name: "production",
        status: "ok",
        created: 3,
        updated: 7,
        deleted: 0,
        duration_ms: 2410.0,
        error: nil,
      )
      json = result.to_json
      parsed = JSON.parse(json)
      parsed["name"].as_s.should eq("production")
      parsed["status"].as_s.should eq("ok")
      parsed["created"].as_i.should eq(3)
      parsed["updated"].as_i.should eq(7)
      parsed["deleted"].as_i.should eq(0)
      parsed["duration_ms"].as_f.should eq(2410.0)
    end

    it "captures per-target error without aborting siblings in #deploy_structured" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "index.html"), "Hi")

        config = Hwaro::Models::Config.new

        # First target succeeds, second fails (missing url + command).
        ok_target = Hwaro::Models::DeploymentTarget.new
        ok_target.name = "ok"
        ok_target.url = "file://#{dest_dir}"
        config.deployment.targets << ok_target

        bad_target = Hwaro::Models::DeploymentTarget.new
        bad_target.name = "bad"
        bad_target.url = ""
        config.deployment.targets << bad_target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["ok", "bad"]
        )

        results = deployer.deploy_structured(options, config)
        results.size.should eq(2)
        results[0].name.should eq("ok")
        results[0].status.should eq("ok")
        results[1].name.should eq("bad")
        results[1].status.should eq("error")
        results[1].error.should_not be_nil
      end
    end

    it "auto-generates command for gs:// URL in dry_run" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "gcs"
        target.url = "gs://my-bucket"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir,
          targets: ["gcs"],
          dry_run: true
        )

        result = deployer.run(options, config)
        result.should be_true
      end
    end
  end
end

# Reopen Deployer to expose private methods for testing
class Hwaro::Services::Deployer
  def test_shell_escape(value : String) : String
    shell_escape(value)
  end

  def test_expand_placeholders(command : String, source_dir : String, target : Hwaro::Models::DeploymentTarget) : String
    expand_placeholders(command, source_dir, target)
  end

  def test_auto_command_for_url(url : String, source_dir : String) : String?
    auto_command_for_url(url, source_dir)
  end

  def test_local_directory_destination(url : String) : String?
    local_directory_destination(url)
  end

  def test_included_by_target?(rel : String, target : Hwaro::Models::DeploymentTarget) : Bool
    included_by_target?(rel, target)
  end
end

describe "Deployer private helpers" do
  describe "#shell_escape" do
    it "wraps value in single quotes" do
      deployer = Hwaro::Services::Deployer.new
      deployer.test_shell_escape("hello").should eq("'hello'")
    end

    it "escapes embedded single quotes" do
      deployer = Hwaro::Services::Deployer.new
      deployer.test_shell_escape("it's").should eq("'it'\\''s'")
    end

    it "strips null bytes" do
      deployer = Hwaro::Services::Deployer.new
      deployer.test_shell_escape("hel\0lo").should eq("'hello'")
    end

    it "handles empty string" do
      deployer = Hwaro::Services::Deployer.new
      deployer.test_shell_escape("").should eq("''")
    end

    it "escapes multiple single quotes" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_shell_escape("a'b'c")
      result.should eq("'a'\\''b'\\''c'")
    end
  end

  describe "#expand_placeholders" do
    it "replaces source, url, and target placeholders" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "prod"
      target.url = "s3://my-bucket"

      result = deployer.test_expand_placeholders("deploy {source} to {url} as {target}", "/tmp/out", target)
      result.should contain("'/tmp/out'")
      result.should contain("'s3://my-bucket'")
      result.should contain("'prod'")
    end

    it "shell-escapes placeholder values" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "it's a test"
      target.url = "file:///tmp/dest"

      result = deployer.test_expand_placeholders("cmd {target}", "/tmp", target)
      result.should contain("'\\''")
    end

    it "handles command with no placeholders" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "prod"
      target.url = "s3://bucket"

      result = deployer.test_expand_placeholders("echo done", "/tmp", target)
      result.should eq("echo done")
    end
  end

  describe "#auto_command_for_url" do
    it "returns aws command for s3:// URL" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_auto_command_for_url("s3://my-bucket", "/tmp")
      result.should eq("aws s3 sync {source}/ {url} --delete")
    end

    it "returns gsutil command for gs:// URL" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_auto_command_for_url("gs://my-bucket", "/tmp")
      result.should eq("gsutil -m rsync -r -d {source}/ {url}")
    end

    it "returns az command for az:// URL" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_auto_command_for_url("az://my-container", "/tmp")
      result.should eq("az storage blob sync --source {source} --container {url}")
    end

    it "returns nil for unknown scheme" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_auto_command_for_url("https://example.com", "/tmp")
      result.should be_nil
    end

    it "returns nil for invalid URL" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_auto_command_for_url("://broken", "/tmp")
      result.should be_nil
    end
  end

  describe "#local_directory_destination" do
    it "extracts path from file:// URL" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_local_directory_destination("file:///tmp/dest")
      result.should eq("/tmp/dest")
    end

    it "returns nil for non-file scheme" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_local_directory_destination("s3://bucket")
      result.should be_nil
    end

    it "treats plain path as local directory" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_local_directory_destination("/tmp/output")
      result.should eq("/tmp/output")
    end

    it "treats relative path as local directory" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_local_directory_destination("dist/public")
      result.should eq("dist/public")
    end

    it "returns nil for file:// with empty path" do
      deployer = Hwaro::Services::Deployer.new
      result = deployer.test_local_directory_destination("file://")
      result.should be_nil
    end
  end

  describe "#included_by_target?" do
    it "returns true when no include/exclude patterns" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "prod"
      target.url = "file:///tmp"

      deployer.test_included_by_target?("index.html", target).should be_true
    end

    it "includes files matching include pattern" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "prod"
      target.url = "file:///tmp"
      target.include = "*.html"

      deployer.test_included_by_target?("index.html", target).should be_true
      deployer.test_included_by_target?("style.css", target).should be_false
    end

    it "excludes files matching exclude pattern" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "prod"
      target.url = "file:///tmp"
      target.exclude = "*.map"

      deployer.test_included_by_target?("app.js", target).should be_true
      deployer.test_included_by_target?("app.js.map", target).should be_false
    end

    it "normalizes backslashes to forward slashes" do
      deployer = Hwaro::Services::Deployer.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "prod"
      target.url = "file:///tmp"
      target.exclude = "assets\\style.css"

      # After normalization, "assets\style.css" becomes "assets/style.css"
      # which should NOT match the exclude (exclude is also a literal pattern)
      deployer.test_included_by_target?("assets\\style.css", target).should be_true
    end
  end
end
