require "../../../spec_helper"

describe "deploy command output" do
  # A deploy tool printing a long stretch without a newline (a progress bar)
  # used to be buffered whole as one "line" per stream.
  it "never holds more than a bounded chunk of a newline-less stream" do
    posix_only!("the target command is POSIX shell (head, tr, /dev/zero)")
    Dir.mktmpdir do |dir|
      project = File.join(dir, "project")
      FileUtils.mkdir_p(File.join(project, "public"))
      File.write(File.join(project, "public", "index.html"), "x")

      config = Hwaro::Models::Config.new
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "cmd"
      target.command = "head -c 300000 /dev/zero | tr '\\0' Q; head -c 300000 /dev/zero | tr '\\0' W >&2"
      config.deployment.targets << target
      options = Hwaro::Config::Options::DeployOptions.new(source_dir: File.join(project, "public"), targets: ["cmd"], force: true)

      log = with_captured_log do
        Dir.cd(project) do
          Hwaro::Services::Deployer.new.run(options, config).should be_true
        end
      end

      log.each_line.max_of(&.bytesize).should be < 100_000
      log.count('Q').should be >= 300_000
      log.count('W').should be >= 300_000
    end
  end
end
