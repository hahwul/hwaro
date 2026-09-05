require "../../../../spec_helper"

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

    it "rejects a second positional instead of silently exporting to the default directory" do
      cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
      ex = expect_raises(Hwaro::HwaroError) { cmd.run(["hugo", "/tmp/dest"]) }
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.to_s.should contain("unexpected extra argument(s): '/tmp/dest'")
      ex.hint.to_s.should contain("--output")
    end

    # Regression: `-o .` (and `-o ""`) used to resolve every destination back
    # onto the source file the exporter had just read, so the command rewrote
    # the project's own content/ in place — YAML front matter re-emitted as
    # TOML, comment lines dropped, `@/` links flattened — and still exited 0.
    it "refuses to export into the project directory and leaves content untouched" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          source = File.join("content", "post.md")
          original = "---\ntitle: My Post\n# a comment explaining the next key\ncustom_field: keep-me\n---\n\nSee [the guide](@/guide.md#intro).\n"
          File.write(source, original)

          cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
          ex = expect_raises(Hwaro::HwaroError) { cmd.run(["hugo", "-o", "."]) }
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)

          File.read(source).should eq(original)
        end
      end
    end

    it "refuses to export into the content directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          File.write(File.join("content", "post.md"), "+++\ntitle = \"P\"\n+++\n\nbody\n")

          cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
          ex = expect_raises(Hwaro::HwaroError) { cmd.run(["jekyll", "-o", "content"]) }
          ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        end
      end
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

  # Stability audit 2026-08-23. A run with per-file errors used to exit 0 as
  # long as one file exported; it must fail with the classified IO error the
  # sibling `tool convert` already uses.
  describe "#run partial failure" do
    it "raises a classified IO error when some files fail to export" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "good.md"), "+++\ntitle = \"G\"\n+++\n\nBody.\n")
        File.write(File.join(content_dir, "bad.md"), "+++\ntitle = = broken\n+++\n\nBody.\n")

        cmd = Hwaro::CLI::Commands::Tool::ExportCommand.new
        ex = expect_raises(Hwaro::HwaroError) do
          with_captured_log { cmd.run(["hugo", "-c", content_dir, "-o", output_dir]) }
        end

        ex.code.should eq(Hwaro::Errors::HWARO_E_IO)
        # The good file still exported before the failure was reported.
        File.exists?(File.join(output_dir, "content", "good.md")).should be_true
      end
    end
  end
end
