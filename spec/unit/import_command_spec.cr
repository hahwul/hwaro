require "../spec_helper"

# Command-level tests for `hwaro tool import`.
#
# The individual importers are exercised in spec/unit/importers/*; these tests
# cover the command wrapper itself: metadata, argument validation, the
# source-type → importer dispatch, the source-specific hints, and the
# success/skip logging paths.
describe Hwaro::CLI::Commands::Tool::ImportCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::ImportCommand.metadata
      meta.name.should eq("import")
      meta.description.should_not be_empty
    end

    it "declares source-type and path positional arguments" do
      meta = Hwaro::CLI::Commands::Tool::ImportCommand.metadata
      meta.positional_args.should eq(["source-type", "path"])
    end

    it "lists every supported importer as a positional choice" do
      meta = Hwaro::CLI::Commands::Tool::ImportCommand.metadata
      %w[wordpress jekyll hugo notion obsidian hexo astro eleventy].each do |source|
        meta.positional_choices.should contain(source)
      end
    end

    it "exposes the output and force flags" do
      meta = Hwaro::CLI::Commands::Tool::ImportCommand.metadata
      meta.flags.any? { |f| f.long == "--output" }.should be_true
      meta.flags.any? { |f| f.long == "--force" }.should be_true
    end
  end

  describe "#run argument validation" do
    it "raises a usage error when no source type is given" do
      cmd = Hwaro::CLI::Commands::Tool::ImportCommand.new
      ex = expect_raises(Hwaro::HwaroError) { cmd.run([] of String) }
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.to_s.should contain("missing <source-type>")
    end

    it "raises a usage error for an unknown source type" do
      cmd = Hwaro::CLI::Commands::Tool::ImportCommand.new
      ex = expect_raises(Hwaro::HwaroError) { cmd.run(["bloggertool", "/tmp/x"]) }
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.to_s.should contain("unknown source type")
    end

    it "raises a usage error when the path is missing" do
      cmd = Hwaro::CLI::Commands::Tool::ImportCommand.new
      ex = expect_raises(Hwaro::HwaroError) { cmd.run(["jekyll"]) }
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.to_s.should contain("missing <path>")
    end

    it "includes a source-specific hint when nothing importable is found" do
      Dir.mktmpdir do |dir|
        # An empty directory: jekyll importer finds no _posts/, reports 0 items.
        cmd = Hwaro::CLI::Commands::Tool::ImportCommand.new
        ex = expect_raises(Hwaro::HwaroError) { cmd.run(["jekyll", dir, "-o", File.join(dir, "out")]) }
        ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        ex.message.to_s.should contain("no importable content found")
        ex.hint.to_s.should contain("_posts/")
      end
    end
  end

  describe "#run success path" do
    it "imports Jekyll posts and logs a completion summary" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "2024-01-15-hello-world.md"),
          "---\ntitle: \"Hello World\"\n---\nFirst post body.\n"
        )
        output_dir = File.join(dir, "out")

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::ImportCommand.new
          cmd.run(["jekyll", dir, "-o", output_dir])
        end

        output.should contain("hwaro: import jekyll")
        output.should contain("imported:")
        File.exists?(File.join(output_dir, "posts", "hello-world.md")).should be_true
      end
    end

    it "warns about skipped files when the destination already exists" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "2024-01-15-hello-world.md"),
          "---\ntitle: \"Hello World\"\n---\nFirst post body.\n"
        )
        output_dir = File.join(dir, "out")

        cmd = Hwaro::CLI::Commands::Tool::ImportCommand.new
        with_captured_log { cmd.run(["jekyll", dir, "-o", output_dir]) }

        # Second run without --force: the destination exists, so it is skipped.
        output = with_captured_log do
          cmd2 = Hwaro::CLI::Commands::Tool::ImportCommand.new
          cmd2.run(["jekyll", dir, "-o", output_dir])
        end

        output.should contain("skipped")
        output.should contain("--force")
        output.should contain("--drafts")
      end
    end
  end
end
