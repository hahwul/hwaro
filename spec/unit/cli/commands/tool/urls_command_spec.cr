require "../../../../spec_helper"

# Command-level tests for `hwaro tool urls`. The plan itself is specced in
# spec/unit/core/build/builder/url_plan_spec.cr; `--json` and the exit codes
# in spec/functional/cli_tool_subcommands_spec.cr (they need a real stdout).
describe Hwaro::CLI::Commands::Tool::UrlsCommand do
  describe ".metadata" do
    it "reports the command name and its flags" do
      meta = Hwaro::CLI::Commands::Tool::UrlsCommand.metadata
      meta.name.should eq("urls")
      meta.description.should_not be_empty
      meta.flags.map(&.long).should eq(
        ["--input", "--env", "--drafts", "--include-expired", "--include-future", "--json", "--quiet", "--help"]
      )
    end
  end

  describe "#run" do
    it "prints one URL per line, sorted, and nothing else" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "config.toml"), "title = \"T\"\nbase_url = \"http://localhost\"\n")
        FileUtils.mkdir_p(File.join(dir, "content", "posts"))
        File.write(File.join(dir, "content", "index.md"), "+++\ntitle = \"Home\"\n+++\n")
        File.write(File.join(dir, "content", "posts", "b.md"), "+++\ntitle = \"B\"\naliases = [\"/old-b/\"]\n+++\n")
        File.write(File.join(dir, "content", "posts", "a.md"), "+++\ntitle = \"A\"\ndraft = true\n+++\n")

        original = Dir.current
        begin
          output = with_captured_log do
            Hwaro::CLI::Commands::Tool::UrlsCommand.new.run(["-i", dir])
          end
          output.should eq("/\n/old-b/\n/posts/b/\n")

          Dir.cd(original)
          output = with_captured_log do
            Hwaro::CLI::Commands::Tool::UrlsCommand.new.run(["-i", dir, "--drafts"])
          end
          output.should eq("/\n/old-b/\n/posts/a/\n/posts/b/\n")
        ensure
          Dir.cd(original)
        end
        Dir.exists?(File.join(dir, "public")).should be_false
      end
    end

    it "reads the config overlay named by HWARO_ENV, as the build does" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "config.toml"), "title = \"T\"\nbase_url = \"http://localhost\"\n")
        File.write(File.join(dir, "config.preview.toml"), "[build]\ndrafts = true\n")
        FileUtils.mkdir_p(File.join(dir, "content"))
        File.write(File.join(dir, "content", "wip.md"), "+++\ntitle = \"W\"\ndraft = true\n+++\n")

        original = Dir.current
        previous = ENV["HWARO_ENV"]?
        begin
          ENV["HWARO_ENV"] = "preview"
          output = with_captured_log do
            Hwaro::CLI::Commands::Tool::UrlsCommand.new.run(["-i", dir])
          end
          output.should eq("/wip/\n")
        ensure
          ENV["HWARO_ENV"] = previous
          Dir.cd(original)
        end
      end
    end

    it "rejects positional arguments" do
      expect_raises(Hwaro::HwaroError, /unexpected extra argument/) do
        Hwaro::CLI::Commands::Tool::UrlsCommand.new.run(["extra"])
      end
    end

    it "fails when the input directory does not exist" do
      error = expect_raises(Hwaro::HwaroError, /Input directory does not exist/) do
        Hwaro::CLI::Commands::Tool::UrlsCommand.new.run(["-i", "/nonexistent/hwaro-urls"])
      end
      error.code.should eq(Hwaro::Errors::HWARO_E_IO)
    end
  end
end
