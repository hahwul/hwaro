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
  end
end
