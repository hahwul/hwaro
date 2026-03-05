require "../spec_helper"

describe Hwaro::CLI::Commands::Tool::DeadlinkCommand do
  describe "#find_links" do
    it "extracts standard markdown links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "[Example](https://example.com)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.size.should eq(1)
        links[0].url.should eq("https://example.com")
        links[0].file.should contain("test.md")
      end
    end

    it "extracts image markdown links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "![Alt text](https://example.com/image.png)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.size.should eq(1)
        links[0].url.should eq("https://example.com/image.png")
      end
    end

    it "extracts multiple links from one file" do
      Dir.mktmpdir do |dir|
        content = <<-MD
        # Test
        [Link1](https://example.com/1)
        Some text here
        [Link2](https://example.com/2)
        ![Image](https://cdn.example.com/img.jpg)
        MD
        File.write(File.join(dir, "test.md"), content)

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.size.should eq(3)
        urls = links.map(&.url)
        urls.should contain("https://example.com/1")
        urls.should contain("https://example.com/2")
        urls.should contain("https://cdn.example.com/img.jpg")
      end
    end

    it "ignores relative links (non http/https)" do
      Dir.mktmpdir do |dir|
        content = <<-MD
        [Relative](/relative/path/)
        [Also Relative](../sibling/)
        [Absolute](https://example.com/abs)
        MD
        File.write(File.join(dir, "test.md"), content)

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.size.should eq(1)
        links[0].url.should eq("https://example.com/abs")
      end
    end

    it "returns empty array for empty directory" do
      Dir.mktmpdir do |dir|
        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.should be_empty
      end
    end

    it "returns empty array when files contain no links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "# Just a heading\nSome text without links.")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.should be_empty
      end
    end

    it "only scans .md files" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "[Link](https://example.com)")
        File.write(File.join(dir, "test.txt"), "[Link](https://other.com)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.size.should eq(1)
        links[0].url.should eq("https://example.com")
      end
    end

    it "scans nested directories" do
      Dir.mktmpdir do |dir|
        sub = File.join(dir, "sub")
        FileUtils.mkdir_p(sub)
        File.write(File.join(sub, "nested.md"), "[Nested](https://nested.example.com)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.size.should eq(1)
        links[0].url.should eq("https://nested.example.com")
      end
    end
  end
end

# Test helper to expose private find_links method
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def find_links_for_test(dir : String) : Array(Link)
    find_links(dir)
  end
end
