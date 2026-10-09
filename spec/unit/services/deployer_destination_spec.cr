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
  File.write(File.join(src, "foo", "index.html"), "<p>foo page</p>")
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
        File.read(File.join(dest, "foo", "index.html")).should eq("<p>foo page</p>")
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
        File.read(File.join(dest, "foo")).should eq("<p>foo page</p>")
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
        File.read(File.join(dest, "foo", "index.html")).should eq("<p>foo page</p>")
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
        File.read(File.join(dest, "foo", "index.html")).should eq("<p>foo page</p>")
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
      posix_only!("no signals on Windows")
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
      posix_only!("sh syntax (printf, >&2)")
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
      posix_only!("sh single-quote escaping")
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
        File.read(File.join(dest, "foo")).should eq("<p>foo page</p>")

        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.exclude = "foo/index.html"
        Hwaro::Services::Deployer.new.plan(options, config).none? { |op| op.action == "delete" }.should be_true
        Hwaro::Services::Deployer.new.run(options, config)
        File.read(File.join(dest, "foo")).should eq("<p>foo page</p>")
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

  describe "review follow-ups" do
    it "checks a placeholder the template quotes by its expanded value" do
      posix_only!("the setup nests a drive path, colon included, inside a directory name")
      Dir.mktmpdir do |dir|
        src = dest_spec_site(File.join(dir, "x$(touch #{dir}/PWNED)"))
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"])
        ["ls \"{source}\"", "ls '{source}/'"].each do |template|
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::Services::Deployer.new.run(options, dest_spec_command_config(template))
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          File.exists?(File.join(dir, "PWNED")).should be_false
        end
      end
    end

    it "still expands ${source} like {source}" do
      posix_only!("sh single-quote escaping")
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"], dry_run: true)
        ops = Hwaro::Services::Deployer.new.plan(options, dest_spec_command_config("echo ${source}/"))
        ops.first.path.should eq("echo $'#{src}'/")
      end
    end

    it "never clears a stale directory behind a symlinked parent" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src")
        FileUtils.mkdir_p(File.join(src, "sub"))
        File.write(File.join(src, "sub", "foo"), "page")
        outside = File.join(dir, "outside", "sub", "foo")
        FileUtils.mkdir_p(File.join(outside, "x"))
        File.write(File.join(outside, ".DS_Store"), "finder")
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(dest)
        File.symlink(File.join(dir, "outside", "sub"), File.join(dest, "sub"))

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))

        Dir.exists?(File.join(outside, "x")).should be_true
        File.exists?(File.join(outside, ".DS_Store")).should be_true
        File.symlink?(File.join(dest, "sub")).should be_false
        File.read(File.join(dest, "sub", "foo")).should eq("page")
      end
    end

    it "does not read a stale asset as a stripped page" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(dest, "img"))
        File.write(File.join(dest, "img", "logo.png"), "png")
        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.include = "**/index.html"

        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.plan(options, config).none? { |op| op.action == "delete" }.should be_true
      end
    end

    it "reports what was already written when a later copy fails" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        unreadable = File.join(src, "zz.html")
        File.write(unreadable, "z")
        File.chmod(unreadable, 0o000)
        begin
          readable = begin
            File.read(unreadable)
            true
          rescue File::Error
            false
          end
          next if readable
          dest = File.join(dir, "out")
          FileUtils.mkdir_p(dest)
          File.write(File.join(dest, "foo"), "stripped page")

          options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
          result = Hwaro::Services::Deployer.new.deploy_structured(options, dest_spec_config(dest)).first
          result.status.should eq("error")
          result.error.not_nil!["code"].should eq(Hwaro::Errors::HWARO_E_IO)
          result.deleted.should eq(1)
          result.created.should eq(2)
        ensure
          File.chmod(unreadable, 0o644)
        end
      end
    end

    it "keeps draining a command whose stderr can no longer be echoed" do
      posix_only!("sh syntax")
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        sentinel = File.join(dir, "finished")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["cmd"], force: true)
        # ~400 KB on stderr: far past a pipe buffer, so a reader that stops
        # draining blocks the child.
        config = dest_spec_command_config("i=0; while [ $i -lt 4000 ]; do printf '%0100d\\n' 0 >&2; i=$((i+1)); done; touch #{sentinel}")
        closed = IO::Memory.new
        closed.close
        previous = Hwaro::Logger.err_io
        Hwaro::Logger.err_io = closed
        begin
          done = Channel(Nil).new(1)
          spawn do
            Hwaro::Services::Deployer.new.run(options, config)
          ensure
            done.send(nil)
          end
          select
          when done.receive
          when timeout(20.seconds)
            fail "deploy command hung after its stderr echo failed"
          end
        ensure
          Hwaro::Logger.err_io = previous
        end
        File.exists?(sentinel).should be_true
      end
    end
  end

  describe "stripped-page detection" do
    page = "<!doctype html><p>old</p>"

    it "judges a dotted-slug stripped page by its source spelling" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src")
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(src, "docs", "v1.2"))
        File.write(File.join(src, "index.html"), "home")
        File.write(File.join(src, "docs", "v1.2", "index.html"), page)
        FileUtils.mkdir_p(File.join(dest, "docs"))
        File.write(File.join(dest, "docs", "v1.2"), page)
        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.exclude = "docs/v1.2/index.html"
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])

        Hwaro::Services::Deployer.new.plan(options, config).none? { |op| op.action == "delete" }.should be_true
        Hwaro::Services::Deployer.new.run(options, config)
        File.exists?(File.join(dest, "docs", "v1.2")).should be_true
      end
    end

    it "still deletes a stale dotted-slug page but spares a dotted non-page file" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(dest, "docs"))
        File.write(File.join(dest, "docs", "v0.9"), page)
        File.write(File.join(dest, "docs", "jquery.min"), "var a=1;")
        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.include = "**/index.html"
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])

        deletes = Hwaro::Services::Deployer.new.plan(options, config).select { |op| op.action == "delete" }.map(&.path)
        deletes.should eq(["docs/v0.9"])
      end
    end

    it "does not read extensionless non-page files as stale stripped pages" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(dest)
        File.write(File.join(dest, "CNAME"), "example.com\n")
        File.write(File.join(dest, "LICENSE"), "MIT")
        File.write(File.join(dest, "old"), page)
        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.include = "**/*.html"
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])

        deletes = Hwaro::Services::Deployer.new.plan(options, config).select { |op| op.action == "delete" }.map(&.path)
        deletes.should eq(["old"])
        Hwaro::Services::Deployer.new.run(options, config)
        File.exists?(File.join(dest, "CNAME")).should be_true
        File.exists?(File.join(dest, "LICENSE")).should be_true
      end
    end
  end

  describe "stripped-page detection on files with an extension" do
    it "spares markup assets and hand-placed .html files an include does not name" do
      Dir.mktmpdir do |dir|
        src = dest_spec_site(dir)
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(dest, "docs"))
        File.write(File.join(dest, "logo.svg"), "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
        File.write(File.join(dest, "feed.xml"), "<?xml version=\"1.0\"?><rss/>")
        File.write(File.join(dest, "about.html"), "<!doctype html><p>hand placed</p>")
        File.write(File.join(dest, "docs", "v0.9"), "<!doctype html><p>old</p>")
        config = dest_spec_config(dest, strip: true)
        config.deployment.targets.first.include = "**/index.html"
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])

        deletes = Hwaro::Services::Deployer.new.plan(options, config).select { |op| op.action == "delete" }.map(&.path)
        deletes.should eq(["docs/v0.9"])
      end
    end
  end

  describe "aliased and case-renamed paths" do
    it "deploys a real directory and every symlink alias of it" do
      posix_only!("symlinks")
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src")
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(src, "v2"))
        File.write(File.join(src, "v2", "x.html"), "x")
        File.write(File.join(src, "index.html"), "i")
        File.symlink("v2", File.join(src, "latest"))
        File.symlink("v2", File.join(src, "aaa"))
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))

        %w[v2 latest aaa].each { |name| File.read(File.join(dest, name, "x.html")).should eq("x") }
      end
    end

    it "does not delete a page whose directory was only re-cased" do
      Dir.mktmpdir do |dir|
        probe = File.join(dir, "Probe")
        File.write(probe, "")
        pending!("case-sensitive filesystem") unless File.exists?(File.join(dir, "probe"))
        src = File.join(dir, "src")
        dest = File.join(dir, "out")
        FileUtils.mkdir_p(File.join(src, "Docs"))
        File.write(File.join(src, "Docs", "Intro.html"), "a")
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"])
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))

        FileUtils.rm_rf(File.join(src, "Docs"))
        FileUtils.mkdir_p(File.join(src, "docs"))
        File.write(File.join(src, "docs", "intro.html"), "a2")
        Hwaro::Services::Deployer.new.plan(options, dest_spec_config(dest)).none? { |op| op.action == "delete" }.should be_true
        Hwaro::Services::Deployer.new.run(options, dest_spec_config(dest))
        File.read(File.join(dest, "docs", "intro.html")).should eq("a2")
      end
    end
  end
end
