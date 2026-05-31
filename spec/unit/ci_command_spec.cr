require "../spec_helper"

# Command-level tests for `hwaro tool ci` (deprecated alias for
# `tool platform github-pages`).
#
# The CIConfig service is exercised in spec/unit/ci_config_spec.cr; these tests
# cover the command wrapper: metadata, the deprecation warning, and writing the
# generated workflow file. Paths that call `exit` (missing/unsupported
# provider, refusing to overwrite) are intentionally not exercised here.
describe Hwaro::CLI::Commands::Tool::CICommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      meta.name.should eq("ci")
      meta.description.should_not be_empty
    end

    it "lists every supported provider as a positional choice" do
      meta = Hwaro::CLI::Commands::Tool::CICommand.metadata
      Hwaro::Services::CIConfig::SUPPORTED_PROVIDERS.each do |provider|
        meta.positional_choices.should contain(provider)
      end
    end
  end

  describe "#run" do
    it "emits a deprecation warning and writes the workflow file" do
      Dir.mktmpdir do |dir|
        out_path = File.join(dir, "deploy.yml")

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::CICommand.new
          cmd.run(["github-actions", "-o", out_path])
        end

        output.should contain("DEPRECATED")
        output.should contain("Generated")
        File.exists?(out_path).should be_true
        File.read(out_path).should_not be_empty
      end
    end

    it "auto-detects the workflow path and creates intermediate directories" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          with_captured_log do
            cmd = Hwaro::CLI::Commands::Tool::CICommand.new
            cmd.run(["github-actions"])
          end

          File.exists?(File.join(dir, ".github", "workflows", "deploy.yml")).should be_true
        end
      end
    end
  end
end
