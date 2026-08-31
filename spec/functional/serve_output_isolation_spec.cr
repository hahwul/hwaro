require "digest/md5"
require "../spec_helper"
require "../../src/services/server/server"
require "../../src/services/deployer"
require "../../src/config/options/deploy_options"

# Regression coverage for issue #756: deploying serve output leaked the dev
# base_url (http://127.0.0.1:3000) into links because serve and build shared
# the same output directory.
#
# - Serve builds into its own `.hwaro/serve/` and the configured output_dir
#   stays byte-identical during a serve session (the core regression).
# - Serve stamps its output with the `.hwaro-dev` marker.
# - `hwaro build` removes a marker left in its output dir (older versions
#   shared the directory) and warns.
# - `hwaro deploy` refuses a source directory carrying the marker.

# Reopened for the private seams; names are prefixed so they can't collide
# with the shims other spec files install.
module Hwaro
  module Services
    class Server
      def isolation_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def isolation_serve_build_options(options : Config::Options::ServeOptions) : Config::Options::BuildOptions
        serve_build_options(options)
      end
    end
  end
end

# The serve session's effective build options, derived exactly as
# `Server#run` derives them (to_build_options + serve_mode + the `[build]`
# merge). Inlined rather than calling the server seam so the core regression
# test below compiles — and demonstrably fails — on pre-#756 sources too.
private def isolation_session_options : Hwaro::Config::Options::BuildOptions
  opts = Hwaro::Config::Options::ServeOptions.new.to_build_options
  opts.serve_mode = true
  begin
    opts.apply_build_config!(Hwaro::Models::Config.load.build)
  rescue Hwaro::HwaroError
  end
  opts
end

private def write_isolation_site(extra_config = "")
  File.write("config.toml", <<-TOML
    title = "Serve Isolation"
    base_url = "https://example.com"

    [sitemap]
    enabled = true
    #{extra_config}
    TOML
  )
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ content }}</body></html>")
  File.write("content/hello.md", "---\ntitle: Hello\n---\nBody")
end

private def isolation_build_options : Hwaro::Config::Options::BuildOptions
  Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
end

private def isolation_production_builder : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder
end

# Every regular file under `root` with a digest of its bytes — the
# "untouched" comparison must catch overwrites, deletions AND additions.
private def isolation_tree_snapshot(root : String) : Hash(String, String)
  snapshot = {} of String => String
  Dir.glob(File.join(root, "**", "*"), match: File::MatchOptions.glob_default | File::MatchOptions::DotFiles) do |path|
    next unless File.file?(path)
    snapshot[path] = Digest::MD5.hexdigest(File.read(path))
  end
  snapshot
end

describe "serve output isolation (issue #756)" do
  # THE regression: a serve session must never touch the deployable tree.
  # Pre-fix, serve built straight into `public/` and this failed on the
  # snapshot comparison — every page and the sitemap were rewritten with
  # http://127.0.0.1:3000 URLs.
  it "serve builds into .hwaro/serve and leaves the configured output_dir untouched" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site

        with_captured_log do
          isolation_production_builder.run(isolation_build_options).should be_true
        end
        File.exists?("public/sitemap.xml").should be_true
        File.read("public/sitemap.xml").should contain("https://example.com")
        before = isolation_tree_snapshot("public")
        before.empty?.should be_false

        serve_options = isolation_session_options
        serve_options.output_dir.should eq(".hwaro/serve")
        server = Hwaro::Services::Server.new
        with_captured_log do
          server.isolation_builder.run(serve_options).should be_true
        end

        # The deployable tree is byte-identical — no dev URL leaked into it.
        isolation_tree_snapshot("public").should eq(before)

        # The serve session's pages carry the dev base_url, in the dev dir.
        File.exists?(".hwaro/serve/sitemap.xml").should be_true
        File.read(".hwaro/serve/sitemap.xml").should contain("http://127.0.0.1:3000")

        # Defense in depth: the dev dir is stamped, the deployable one is not.
        File.exists?(".hwaro/serve/.hwaro-dev").should be_true
        File.exists?("public/.hwaro-dev").should be_false
      end
    end
  end

  # `[build] output_dir` must not pull the serve session back into the
  # deployable tree — the dev dir is pinned the way an explicit `-o` is.
  it "ignores [build] output_dir for the serve session" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site(extra_config: "[build]\noutput_dir = \"dist\"")

        serve_options = isolation_session_options
        serve_options.output_dir.should eq(".hwaro/serve")

        server = Hwaro::Services::Server.new
        with_captured_log do
          server.isolation_builder.run(serve_options).should be_true
        end
        File.exists?(".hwaro/serve/hello/index.html").should be_true
        Dir.exists?("dist").should be_false
      end
    end
  end

  # Guard against the spec-local derivation above drifting from what
  # `Server#run` actually computes.
  it "Server#serve_build_options matches the session derivation" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site

        from_server = Hwaro::Services::Server.new.isolation_serve_build_options(
          Hwaro::Config::Options::ServeOptions.new
        )
        from_server.output_dir.should eq(isolation_session_options.output_dir)
        from_server.serve_mode.should be_true
        from_server.output_dir_explicit.should be_true
      end
    end
  end

  # A cold serve start must not serve a previous session's pages: the dev
  # dir is wiped exactly like any cold build output.
  it "a new serve session wipes stale files from the previous one" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site
        FileUtils.mkdir_p(".hwaro/serve/removed-page")
        File.write(".hwaro/serve/removed-page/index.html", "stale dev output")

        server = Hwaro::Services::Server.new
        with_captured_log do
          server.isolation_builder.run(isolation_session_options).should be_true
        end

        File.exists?(".hwaro/serve/removed-page/index.html").should be_false
        File.exists?(".hwaro/serve/hello/index.html").should be_true
      end
    end
  end

  # Older hwaro versions let serve write into the build output dir. A cold
  # `hwaro build` wipes the leftovers, but must still say a dev session had
  # been there, and the marker must not survive into deployable output.
  it "hwaro build removes a leftover dev marker and warns (cold build)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site
        FileUtils.mkdir_p("public")
        File.write("public/.hwaro-dev", "leftover from an old serve session")

        log = with_captured_log do
          isolation_production_builder.run(isolation_build_options).should be_true
        end

        log.should contain("previous `hwaro serve` session")
        File.exists?("public/.hwaro-dev").should be_false
      end
    end
  end

  # The `--cache` path never wipes the output dir, so the marker has to be
  # removed explicitly there.
  it "hwaro build --cache removes a leftover dev marker too" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site
        FileUtils.mkdir_p("public")
        File.write("public/.hwaro-dev", "leftover from an old serve session")
        File.write("public/keep.txt", "cached artifact")

        options = isolation_build_options
        options.cache = true
        log = with_captured_log do
          isolation_production_builder.run(options).should be_true
        end

        log.should contain("previous `hwaro serve` session")
        File.exists?("public/.hwaro-dev").should be_false
        # Proof the incremental path ran (nothing wiped the directory).
        File.exists?("public/keep.txt").should be_true
      end
    end
  end

  it "hwaro build neither warns nor stamps when no marker is present" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_isolation_site

        log = with_captured_log do
          isolation_production_builder.run(isolation_build_options).should be_true
        end

        log.should_not contain("hwaro serve` session")
        File.exists?("public/.hwaro-dev").should be_false
      end
    end
  end

  describe "deploy refusal" do
    it "refuses to deploy a directory carrying the dev marker" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "site")
        FileUtils.mkdir_p(source)
        File.write(File.join(source, "index.html"), "x")
        File.write(File.join(source, ".hwaro-dev"), "dev output")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "production"
        target.url = "file://#{dir}/dest"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: source,
          targets: ["production"],
        )

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Services::Deployer.new.run(options, config)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("hwaro serve")
        (err.hint || "").should contain("hwaro build")
        # Escape hatch is deleting the marker by hand — the hint must name it.
        (err.hint || "").should contain(".hwaro-dev")

        # Nothing reached the destination.
        Dir.exists?(File.join(dir, "dest")).should be_false
      end
    end

    it "refuses in the --dry-run plan the same way" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "site")
        FileUtils.mkdir_p(source)
        File.write(File.join(source, "index.html"), "x")
        File.write(File.join(source, ".hwaro-dev"), "dev output")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "production"
        target.url = "file://#{dir}/dest"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: source,
          targets: ["production"],
          dry_run: true,
        )

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Services::Deployer.new.plan(options, config)
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      end
    end

    it "deploys normally once the marker is gone" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "site")
        FileUtils.mkdir_p(source)
        File.write(File.join(source, "index.html"), "x")

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "production"
        target.url = "file://#{dir}/dest"
        config.deployment.targets << target

        options = Hwaro::Config::Options::DeployOptions.new(
          source_dir: source,
          targets: ["production"],
        )

        with_captured_log do
          Hwaro::Services::Deployer.new.run(options, config).should be_true
        end
        File.exists?(File.join(dir, "dest", "index.html")).should be_true
      end
    end
  end
end
