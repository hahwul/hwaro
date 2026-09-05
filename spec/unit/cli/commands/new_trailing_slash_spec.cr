require "../../../spec_helper"
require "../../../../src/models/config"
require "../../../../src/cli/commands/new_command"
require "../../../../src/services/creator"

# Path normalization drops a trailing separator, so `hwaro new notes/` was
# indistinguishable from `hwaro new notes` by the time the Creator chose a
# layout. The result then depended on whether content/notes/ happened to
# exist yet: the first call scaffolded the page content/notes.md, and the
# second call for the same section failed with "File already exists".
describe "hwaro new trailing-slash path intent" do
  describe "NewCommand#run" do
    it "records the trailing separator on the options" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost:3000\"\n")
          FileUtils.mkdir_p("content")

          with_captured_log do
            Hwaro::CLI::Commands::NewCommand.new.run(["notes/", "-t", "First Note"])
          end

          File.exists?("content/notes/first-note.md").should be_true
          File.exists?("content/notes.md").should be_false
        end
      end
    end

    it "creates a second page in the same brand-new section" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost:3000\"\n")
          FileUtils.mkdir_p("content")

          with_captured_log do
            cmd = Hwaro::CLI::Commands::NewCommand.new
            cmd.run(["notes/", "-t", "First Note"])
            Hwaro::CLI::Commands::NewCommand.new.run(["notes/", "-t", "Second Note"])
          end

          File.exists?("content/notes/first-note.md").should be_true
          File.exists?("content/notes/second-note.md").should be_true
        end
      end
    end

    it "leaves the no-slash form untouched (still a page stem)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost:3000\"\n")
          FileUtils.mkdir_p("content")

          with_captured_log do
            Hwaro::CLI::Commands::NewCommand.new.run(["journal", "-t", "Journal Entry"])
          end

          File.exists?("content/journal.md").should be_true
          File.exists?("content/journal/journal-entry.md").should be_false
        end
      end
    end
  end

  describe "Creator#run" do
    it "routes a nested trailing-slash path into the directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(
            path: "deep/sub", title: "Deep One", path_is_dir: true
          )
          result = Hwaro::Services::Creator.new.run(options)

          result.should eq("content/deep/sub/deep-one.md")
          File.exists?("content/deep/sub.md").should be_false
        end
      end
    end

    it "keeps the nested no-slash path flat" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "deep/sub", title: "Deep One")
          Hwaro::Services::Creator.new.run(options).should eq("content/deep/sub.md")
        end
      end
    end

    it "keeps today's behaviour when the bare directory already exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content/posts")

          options = Hwaro::Config::Options::NewOptions.new(path: "posts", title: "Inside Posts")
          Hwaro::Services::Creator.new.run(options).should eq("content/posts/inside-posts.md")
        end
      end
    end

    it "does not disturb --bundle" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          flat = Hwaro::Config::Options::NewOptions.new(path: "x", title: "Ex", bundle: true)
          Hwaro::Services::Creator.new.run(flat).should eq("content/x/index.md")

          slashed = Hwaro::Config::Options::NewOptions.new(
            path: "y", title: "Why", bundle: true, path_is_dir: true
          )
          Hwaro::Services::Creator.new.run(slashed).should eq("content/y/index.md")
        end
      end
    end

    it "still requires a title when the directory form has nothing to name the file after" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")

          options = Hwaro::Config::Options::NewOptions.new(path: "notes", path_is_dir: true)
          err = expect_raises(Hwaro::HwaroError) { Hwaro::Services::Creator.new.run(options) }
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          (err.message || "").should contain("--title is not set")
        end
      end
    end
  end
end
