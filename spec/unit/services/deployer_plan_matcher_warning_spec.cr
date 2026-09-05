require "../../spec_helper"

# Regression: `hwaro deploy --dry-run` compiled (and warned about) the
# deployment matcher patterns ONCE per plan; a refactor moved the
# compilation into the per-target preparation, so an invalid pattern
# warned once per directory target and never for command-only targets.
describe "Deployer#plan invalid matcher warning" do
  it "warns exactly once for the whole plan, regardless of target kinds" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("public")
        File.write("public/index.html", "hi")
        config = Hwaro::Models::Config.new
        config.deployment.source_dir = "public"
        matcher = Hwaro::Models::DeploymentMatcher.new
        matcher.pattern = "("
        matcher.force = true
        config.deployment.matchers << matcher
        %w[a b].each do |name|
          t = Hwaro::Models::DeploymentTarget.new
          t.name = name
          t.url = "file://#{File.join(dir, "out-#{name}")}"
          config.deployment.targets << t
        end
        c = Hwaro::Models::DeploymentTarget.new
        c.name = "cmd"
        c.command = "echo hi"
        config.deployment.targets << c

        options = Hwaro::Config::Options::DeployOptions.new(dry_run: true, targets: ["a", "b", "cmd"])
        log = with_captured_log { Hwaro::Services::Deployer.new.plan(options, config) }
        log.scan("Ignoring invalid deployment matcher pattern").size.should eq(1)
      end
    end
  end
end
