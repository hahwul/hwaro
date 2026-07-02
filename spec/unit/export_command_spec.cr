require "../spec_helper"

# Command-level tests for `hwaro tool export`.
#
# The exporters themselves are exercised in spec/unit/exporters/*; these tests
# cover the command wrapper: metadata, target validation, target → exporter
# dispatch, and the success logging path.
describe Hwaro::CLI::Commands::Tool::ExportCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::ExportCommand.metadata
      meta.name.should eq("export")
      meta.description.should_not be_empty
    end

    it "declares a target-type positional argument" do
      meta = Hwaro::CLI::Commands::Tool::ExportCommand.metadata
      meta.positional_args.should eq(["target-type"])
    end

    it "lists hugo and jekyll as supported targets" do
      meta = Hwaro::CLI::Commands::Tool::ExportCommand.metadata
      meta.positional_choices.should eq(["hugo", "jekyll"])
    end

    it "exposes the output flag" do
      meta = Hwaro::CLI::Commands::Tool::ExportCommand.metadata
      meta.flags.any? { |f| f.long == "--output" }.should be_true
    end
  end

  describe "#run argument validation" do
    it "raises a usage error when no target type is given" do
      cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
      ex = expect_raises(Hwaro::HwaroError) { cmd.run([] of String) }
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.to_s.should contain("missing <target-type>")
    end

    it "raises a usage error for an unknown target type" do
      cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
      ex = expect_raises(Hwaro::HwaroError) { cmd.run(["gatsby"]) }
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.to_s.should contain("unknown target type")
    end
  end

  describe "#run success path" do
    it "exports content to hugo and logs a completion summary" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)
        File.write(
          File.join(content_dir, "post.md"),
          "+++\ntitle = \"My Post\"\ndate = 2024-01-15T10:00:00Z\n+++\n\nHello world\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
          cmd.run(["hugo", "-c", content_dir, "-o", output_dir])
        end

        output.should contain("hwaro: export hugo")
        output.should contain("exported:")
        File.exists?(File.join(output_dir, "content", "post.md")).should be_true
      end
    end
  end
end
