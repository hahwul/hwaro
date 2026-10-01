require "../../spec_helper"
require "../../../src/services/deployer"
require "../../../src/models/config"
require "../../../src/config/options/deploy_options"

class Hwaro::Services::Deployer
  def dest_spec_nested_path?(a : String, b : String) : Bool
    nested_path?(a, b)
  end

  def dest_spec_local_directory_destination(url : String) : String?
    local_directory_destination(url)
  end
end

private def dest_spec_config(dest_dir : String, strip : Bool = false, name : String = "local") : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  target = Hwaro::Models::DeploymentTarget.new
  target.name = name
  target.url = dest_dir
  target.strip_index_html = strip
  config.deployment.targets << target
  config
end

private def dest_spec_command_config(command : String) : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  target = Hwaro::Models::DeploymentTarget.new
  target.name = "cmd"
  target.command = command
  config.deployment.targets << target
  config
end

private def dest_spec_site(dir : String) : String
  src = File.join(dir, "src")
  FileUtils.mkdir_p(File.join(src, "foo"))
  File.write(File.join(src, "index.html"), "home")
  File.write(File.join(src, "foo", "index.html"), "foo page")
  src
end

describe Hwaro::Services::Deployer do
  describe "destination handling" do
    it "does not create a missing destination on a dry run" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        config = dest_spec_config(dest)

        Hwaro::Services::Deployer.new.run(
          Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"], dry_run: true), config)
        Dir.exists?(dest).should be_false

        Hwaro::Services::Deployer.new.deploy_structured(
          Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"], dry_run: true), config)
        Dir.exists?(dest).should be_false
      end
    end

    it "keeps the .git file of a worktree destination" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(dest)
        File.write(File.join(dest, ".git"), "gitdir: /repo/.git/worktrees/out\n")
        File.write(File.join(dest, "stale.html"), "old")

        Hwaro::Services::Deployer.new.run(
          Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"]), dest_spec_config(dest))

        File.read(File.join(dest, ".git")).should eq("gitdir: /repo/.git/worktrees/out\n")
        File.exists?(File.join(dest, "stale.html")).should be_false
        File.read(File.join(dest, "foo", "index.html")).should eq("foo page")
      end
    end

    it "reads file://localhost/abs as the absolute path" do
      deployer = Hwaro::Services::Deployer.new
      deployer.dest_spec_local_directory_destination("file://localhost/var/www").should eq("/var/www")
      deployer.dest_spec_local_directory_destination("file://LOCALHOST/var/www").should eq("/var/www")
      deployer.dest_spec_local_directory_destination("file://relative/out").should eq("relative/out")
    end

    it "treats the filesystem root as overlapping every source" do
      deployer = Hwaro::Services::Deployer.new
      deployer.dest_spec_nested_path?("/", "/srv/site/public").should be_true
      deployer.dest_spec_nested_path?("/srv/site/public", "/").should be_false
      deployer.dest_spec_nested_path?("/", "/").should be_true
      deployer.dest_spec_nested_path?("/srv", "/srvx").should be_false
    end

    it "refuses a destination that is a file with a classified error" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        File.write(dest, "not a directory")
        config = dest_spec_config(dest)

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Services::Deployer.new.run(
            Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"]), config)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        (err.message || "").should contain("not a directory")

        # The plan used to promise a clean "create" for every page here.
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Services::Deployer.new.plan(
            Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"], dry_run: true), config)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
      end
    end

    it "classifies an unreadable destination directory as HWARO_E_IO" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        locked = File.join(dest, "locked")
        FileUtils.mkdir_p(locked)
        File.chmod(locked, 0o000)
        begin
          # Root reads through mode 000; nothing to assert there.
          readable = begin
            Dir.children(locked)
            true
          rescue File::Error
            false
          end
          next if readable
          config = dest_spec_config(dest)
          options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])

          err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
          err.code.should eq(Hwaro::Errors::HWARO_E_IO)

          results = Hwaro::Services::Deployer.new.deploy_structured(options, config)
          results.first.error.not_nil!["code"].should eq(Hwaro::Errors::HWARO_E_IO)
        ensure
          File.chmod(locked, 0o755)
        end
      end
    end
  end

  describe "stale entries in the way of the new tree" do
    it "replaces foo/ with foo when strip_index_html is turned on" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))
        File.write(File.join(dest, "foo", ".DS_Store"), "finder")

        plan = Hwaro::Services::Deployer.new.plan(options, dest_spec_config(dest, strip: true))
        plan.map { |op| {op.action, op.path} }.should eq([{"create", "foo"}, {"delete", "foo/index.html"}])

        results = Hwaro::Services::Deployer.new.deploy_structured(options, dest_spec_config(dest, strip: true))
        results.first.status.should eq("ok")
        results.first.created.should eq(1)
        results.first.deleted.should eq(1)
        File.read(File.join(dest, "foo")).should eq("foo page")
        File.read(File.join(dest, "index.html")).should eq("home")
      end
    end

    it "replaces foo with foo/ when strip_index_html is turned off" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest, strip: true))
        File.file?(File.join(dest, "foo")).should be_true

        plan = Hwaro::Services::Deployer.new.plan(options, dest_spec_config(dest))
        plan.map { |op| {op.action, op.path} }.should eq([{"create", "foo/index.html"}, {"delete", "foo"}])

        results = Hwaro::Services::Deployer.new.deploy_structured(options, dest_spec_config(dest))
        results.first.status.should eq("ok")
        results.first.created.should eq(1)
        results.first.deleted.should eq(1)
        File.read(File.join(dest, "foo", "index.html")).should eq("foo page")
      end
    end

    it "still refuses when the directory in the way holds something the sync keeps" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))
        FileUtils.mkdir_p(File.join(dest, "foo", ".keep"))

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest, strip: true))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        (err.message || "").should contain("is a directory but needs a file")
        # Refused before writing anything.
        File.read(File.join(dest, "foo", "index.html")).should eq("foo page")
        Dir.exists?(File.join(dest, "foo", ".keep")).should be_true
      end
    end

    it "plans a create, not an update, for a path behind a destination symlink" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        elsewhere = File.join(dir, "elsewhere")
        FileUtils.mkdir_p(elsewhere)
        File.write(File.join(elsewhere, "index.html"), "other")
        FileUtils.mkdir_p(dest)
        File.write(File.join(dest, "index.html"), "old home")
        File.symlink(elsewhere, File.join(dest, "foo"))

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        plan = Hwaro::Services::Deployer.new.plan(options, dest_spec_config(dest))
        plan.map { |op| {op.action, op.path} }.should eq([{"create", "foo/index.html"}, {"update", "index.html"}])
      end
    end
  end

  describe "command targets" do
    it "reports a signal-terminated command as a classified failure" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"], force: true)
        config = dest_spec_command_config("kill -TERM $$")

        err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Deployer.new.run(options, config) }
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        (err.message || "").should contain("signal")

        results = Hwaro::Services::Deployer.new.deploy_structured(options, config)
        results.first.error.not_nil!["code"].should eq(Hwaro::Errors::HWARO_E_IO)
      end
    end

    it "shows the command's stderr even when it succeeds" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"], force: true)
        # printf keeps the expected text out of the echoed "Command:" line.
        config = dest_spec_command_config("printf 'out-%s\\n' line; printf 'warn-%s\\n' line >&2")

        log = with_captured_log { Hwaro::Services::Deployer.new.run(options, config) }
        log.should contain("out-line")
        log.should contain("warn-line")
      end
    end

    it "judges shell metacharacters on the template, not the quoted source path" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(File.join(dir, "r&d $work"))
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"])
        # Non-interactive: a metacharacter hit would demand a confirmation
        # that cannot be given, and fail.
        log = with_captured_log do
          Hwaro::Services::Deployer.new.run(options, dest_spec_command_config("ls {source}"))
        end
        log.should contain("index.html")
      end
    end

    it "leaves shell ${VAR} expansion to the shell instead of rejecting it" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"], dry_run: true)
        ops = Hwaro::Services::Deployer.new.plan(options, dest_spec_command_config("echo ${HWARO_DEPLOY_TARGET} {target}"))
        ops.first.path.should eq("echo ${HWARO_DEPLOY_TARGET} 'cmd'")
      end
    end
  end

  describe "selection" do
    it "keeps a stripped page whose source path is excluded" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest, strip: true))
        File.read(File.join(dest, "foo")).should eq("foo page")

        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.exclude = "foo/index.html"
        Hwaro::Services::Deployer.new.plan(options, config).none? { |op| op.action == "delete" }.should be_true
        Hwaro::Services::Deployer.new.run(options, config)
        File.read(File.join(dest, "foo")).should eq("foo page")
      end
    end

    it "prunes only the directories its own deletes emptied" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(dest, "uploads", "2026"))
        FileUtils.mkdir_p(File.join(dest, "old", "deep"))
        File.write(File.join(dest, "old", "deep", "page.html"), "stale")

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))

        Dir.exists?(File.join(dest, "uploads", "2026")).should be_true
        Dir.exists?(File.join(dest, "old")).should be_false
      end
    end

    it "deploys hidden source directories but never VCS metadata" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        FileUtils.mkdir_p(File.join(src, ".well-known"))
        FileUtils.mkdir_p(File.join(src, ".circleci"))
        FileUtils.mkdir_p(File.join(src, ".git"))
        File.write(File.join(src, ".well-known", "security.txt"), "sec")
        File.write(File.join(src, ".circleci", "config.yml"), "ci")
        File.write(File.join(src, ".git", "HEAD"), "ref")
        dest = File.join(dir, "out")

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))

        File.read(File.join(dest, ".well-known", "security.txt")).should eq("sec")
        File.read(File.join(dest, ".circleci", "config.yml")).should eq("ci")
        Dir.exists?(File.join(dest, ".git")).should be_false
      end
    end

    it "applies force matchers to the source path of a stripped page" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest, strip: true))

        config = dest_spec_config(dest, strip: true)
        matcher = Hwaro::Models::DeploymentMatcher.new
        matcher.pattern = "^.+\\.html$"
        matcher.force = true
        config.deployment.matchers << matcher
        Hwaro::Services::Deployer.new.plan(options, config).map(&.path).should eq(["foo", "index.html"])
      end
    end

    it "emits a null source for delete ops in the JSON plan" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(dest)
        File.write(File.join(dest, "stale.html"), "old")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"], dry_run: true)
        ops = Hwaro::Services::Deployer.new.plan(options, dest_spec_config(dest))
        delete = ops.find! { |op| op.action == "delete" }
        JSON.parse(delete.to_json).as_h.has_key?("source").should be_true
      end
    end
  end
end
