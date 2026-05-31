require "../spec_helper"

# Capture human-readable Logger output while running a block, restoring all
# global Logger state afterwards.
private def capture_platform_log(&)
  previous_io = Hwaro::Logger.io
  previous_level = Hwaro::Logger.level
  previous_quiet = Hwaro::Logger.quiet?
  sink = IO::Memory.new
  Hwaro::Logger.io = sink
  Hwaro::Logger.level = Hwaro::Logger::Level::Info
  Hwaro::Logger.quiet = false
  begin
    yield
    sink.to_s
  ensure
    Hwaro::Logger.io = previous_io
    Hwaro::Logger.level = previous_level
    Hwaro::Logger.quiet = previous_quiet
  end
end

# Command-level tests for `hwaro tool platform`.
#
# The PlatformConfig service is exercised in spec/unit/platform_config_spec.cr;
# these tests cover the command wrapper: metadata, writing the generated file
# to disk, and the warning emitted when run outside a Hwaro project (no
# config.toml). Paths that call `exit` (missing/unsupported platform, refusing
# to overwrite) are intentionally not exercised here since `exit` would abort
# the spec process.
describe Hwaro::CLI::Commands::Tool::PlatformCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.name.should eq("platform")
      meta.description.should_not be_empty
    end

    it "lists every supported platform as a positional choice" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      Hwaro::Services::PlatformConfig::SUPPORTED_PLATFORMS.each do |platform|
        meta.positional_choices.should contain(platform)
      end
    end

    it "exposes the output, stdout and force flags" do
      meta = Hwaro::CLI::Commands::Tool::PlatformCommand.metadata
      meta.flags.any? { |f| f.long == "--output" }.should be_true
      meta.flags.any? { |f| f.long == "--stdout" }.should be_true
      meta.flags.any? { |f| f.long == "--force" }.should be_true
    end
  end

  describe "#run" do
    it "writes the generated config to the requested output path" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "title = \"Test Site\"\nbase_url = \"https://example.com\"\n")
          out_path = File.join(dir, "netlify.toml")

          output = capture_platform_log do
            cmd = Hwaro::CLI::Commands::Tool::PlatformCommand.new
            cmd.run(["netlify", "-o", out_path])
          end

          output.should contain("Generated")
          File.exists?(out_path).should be_true
          File.read(out_path).should_not be_empty
        end
      end
    end

    it "creates intermediate directories for nested workflow paths" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "title = \"Test Site\"\n")

          capture_platform_log do
            cmd = Hwaro::CLI::Commands::Tool::PlatformCommand.new
            cmd.run(["github-pages"])
          end

          File.exists?(File.join(dir, ".github", "workflows", "deploy.yml")).should be_true
        end
      end
    end

    it "warns when run without a config.toml" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          out_path = File.join(dir, "netlify.toml")

          output = capture_platform_log do
            cmd = Hwaro::CLI::Commands::Tool::PlatformCommand.new
            cmd.run(["netlify", "-o", out_path])
          end

          output.should contain("config.toml not found")
          File.exists?(out_path).should be_true
        end
      end
    end
  end
end
