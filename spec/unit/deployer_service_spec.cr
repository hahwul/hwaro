require "../spec_helper"
require "../../src/services/deployer"
require "../../src/models/config"
require "../../src/config/options/deploy_options"

describe Hwaro::Services::Deployer do
  describe "#run" do
    it "raises HwaroError(HWARO_E_CONFIG) if no targets configured" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: dir,
          targets: [] of String,
        )

        err = expect_raises(Hwaro::HwaroError) { deployer.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("No deployment targets")
      end
    end

    it "raises HwaroError(HWARO_E_USAGE) if an unknown target is specified" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "production"
        target.url = "file:///tmp/prod"
        config.deployment.targets << target

        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: dir,
          targets: ["staging"],
        )

        err = expect_raises(Hwaro::HwaroError) { deployer.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        (err.message || "").should contain("Unknown deploy target: staging")
        (err.hint || "").should contain("production")
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) if the source directory is missing" do
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

        err = expect_raises(Hwaro::HwaroError) { deployer.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("Source directory not found")
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

  describe "classified error surface" do
    it "raises HwaroError(HWARO_E_CONFIG) when target has neither url nor command" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "bare"
        target.url = ""
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["bare"])
        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("missing 'url'")
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) on an unsupported URL scheme with no command override" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "unknown"
        target.url = "gopher://example.com"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["unknown"])
        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("Unsupported deploy target URL scheme")
      end
    end

    it "raises HwaroError(HWARO_E_USAGE) when --max-deletes limit is exceeded" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "keep.html"), "x")
        FileUtils.mkdir_p(dest_dir)
        # Seed the destination with more files than the limit.
        10.times { |i| File.write(File.join(dest_dir, "extra-#{i}.html"), "y") }

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = "file://#{dest_dir}"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir, targets: ["local"], max_deletes: 5,
        )
        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        (err.message || "").should contain("Refusing to delete")
        (err.message || "").should contain("max_deletes: 5")
        # The existing "extra-*" files must remain on disk — the safety
        # limit aborted the plan before any deletion happened.
        Dir.children(dest_dir).count(&.starts_with?("extra-")).should eq(10)
      end
    end

    it "raises HwaroError(HWARO_E_USAGE) when source and destination overlap" do
      Dir.mktmpdir do |dir|
        # Deploy INTO a subdirectory of the source — classic overlap that
        # could wipe the source files during a delete pass.
        src_dir = dir
        dest_dir = File.join(dir, "nested")
        File.write(File.join(src_dir, "keep.html"), "x")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "nested"
        target.url = "file://#{dest_dir}"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src_dir, targets: ["nested"])
        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        (err.message || "").should contain("source and destination overlap")
      end
    end

    it "raises HwaroError(HWARO_E_CONFIG) on unknown command placeholders" do
      # Typos like `{srouce}` and forward-looking tokens like `{bucket}`
      # used to reach the shell as literals and cause confusing
      # downstream errors. The validator now rejects anything that still
      # matches `\{name\}` after expansion.
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "typo"
        target.url = "custom://"
        target.command = "echo src={srouce} bucket={bucket}"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["typo"])
        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("Unknown placeholder(s)")
        (err.message || "").should contain("{srouce}")
        (err.message || "").should contain("{bucket}")
        # Supported-placeholder list in the hint for discoverability.
        (err.hint || "").should contain("{source}")
        (err.hint || "").should contain("{url}")
        (err.hint || "").should contain("{target}")
      end
    end

    it "leaves commands with only supported placeholders alone" do
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "good"
        target.url = "custom://"
        # {target} inside a comment-style literal string should also pass
        target.command = "true # {source} {url} {target}"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["good"])
        # Does not raise — `true` exits 0, no HwaroError surfaces.
        Hwaro::Services::Deployer.new.run(options, config).should be_true
      end
    end

    it "catches unknown placeholders even during --dry-run" do
      # Dry-run still needs to expand + validate the template so typos
      # are caught without waiting for the user to trigger a real deploy.
      Dir.mktmpdir do |dir|
        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "typo"
        target.url = "custom://"
        target.command = "echo {unknown}"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: dir, targets: ["typo"], dry_run: true,
        )
        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("{unknown}")
      end
    end

    it "propagates HwaroError from deploy_structured as per-target payload with the correct code" do
      # Regression: a `--max-deletes` refusal used to surface in --json as
      # HWARO_E_NETWORK with the generic "Deploy target '<name>' failed"
      # message; now it carries the classified HWARO_E_USAGE code and the
      # real "Refusing to delete N files" text.
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "keep.html"), "x")
        FileUtils.mkdir_p(dest_dir)
        10.times { |i| File.write(File.join(dest_dir, "extra-#{i}.html"), "y") }

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = "file://#{dest_dir}"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: src_dir, targets: ["local"], max_deletes: 5,
        )
        results = Hwaro::Services::Deployer.new.deploy_structured(options, config)
        results.size.should eq(1)
        result = results.first
        result.status.should eq("error")
        err = result.error.not_nil!
        err["code"].should eq(Hwaro::Errors::HWARO_E_USAGE)
        (err["message"] || "").should contain("Refusing to delete")
      end
    end
  end
end
