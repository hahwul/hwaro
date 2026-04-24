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

  describe "#find_internal_links" do
    it "extracts relative links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "[About](/about/)\n[Sibling](../other/)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_internal_links_for_test(dir)

        links.size.should eq(2)
        links.map(&.kind).uniq!.should eq([:internal])
      end
    end

    it "extracts internal image paths" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "![Screenshot](images/shot.png)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_internal_links_for_test(dir)

        links.size.should eq(1)
        links[0].kind.should eq(:image)
        links[0].url.should eq("images/shot.png")
      end
    end

    it "skips external links and anchors" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "[External](https://example.com)\n[Anchor](#section)\n[Internal](/page/)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_internal_links_for_test(dir)

        links.size.should eq(1)
        links[0].url.should eq("/page/")
      end
    end
  end

  describe "#private_host? (SSRF protection)" do
    it "blocks localhost" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_host_for_test?("localhost").should be_true
    end

    it "blocks .local domains" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_host_for_test?("myhost.local").should be_true
    end

    it "blocks .internal domains" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_host_for_test?("service.internal").should be_true
    end

    it "blocks 127.0.0.1 (loopback)" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_host_for_test?("127.0.0.1").should be_true
    end

    it "allows public domains" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_host_for_test?("example.com").should be_false
    end
  end

  describe "#private_172?" do
    it "returns true for 172.16.x.x" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_172_for_test?("172.16.0.1").should be_true
    end

    it "returns true for 172.31.x.x" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_172_for_test?("172.31.255.255").should be_true
    end

    it "returns false for 172.15.x.x (below range)" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_172_for_test?("172.15.0.1").should be_false
    end

    it "returns false for 172.32.x.x (above range)" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_172_for_test?("172.32.0.1").should be_false
    end

    it "returns false for non-172 addresses" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_172_for_test?("192.168.1.1").should be_false
    end
  end

  describe "#check_internal_links" do
    it "detects broken internal links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "content")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/nonexistent/", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)

        results.size.should eq(1)
        results[0].error.not_nil!.should contain("not found")
      end
    end

    it "resolves valid internal links" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "about"))
        File.write(File.join(dir, "about", "_index.md"), "about page")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/about/", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)

        results.should be_empty
      end
    end

    it "detects broken image paths" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "content")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "missing.png", kind: :image
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)

        results.size.should eq(1)
        results[0].error.not_nil!.should contain("Image not found")
      end
    end

    it "accepts taxonomy listing URLs that Hwaro generates at build time (issue #466)" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "content")
        tag_link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/tags/", kind: :internal
        )
        tag_term_link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/categories/hello/", kind: :internal
        )
        unknown_link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/not-a-taxonomy/", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test(
          [tag_link, tag_term_link, unknown_link], dir, ["tags", "categories", "authors"])

        # Known taxonomy listing/term URLs resolve; unknown ones still fail.
        results.size.should eq(1)
        results[0].link.url.should eq("/not-a-taxonomy/")
      end
    end

    it "does not treat taxonomy names as valid image paths" do
      # Images shouldn't fall through the taxonomy shortcut — an image
      # reference under `/tags/header.png` still has to exist on disk.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "content")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/tags/header.png", kind: :image
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir, ["tags"])

        results.size.should eq(1)
        results[0].error.not_nil!.should contain("Image not found")
      end
    end
  end
end

# Test helper to expose private methods
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def find_links_for_test(dir : String) : Array(Link)
    find_external_links(dir)
  end

  def find_internal_links_for_test(dir : String) : Array(Link)
    find_internal_links(dir)
  end

  def check_internal_links_for_test(links : Array(Link), content_dir : String, taxonomy_names : Array(String) = [] of String) : Array(Result)
    check_internal_links(links, content_dir, taxonomy_names)
  end

  def private_host_for_test?(host : String) : Bool
    private_host?(host)
  end

  def private_172_for_test?(ip : String) : Bool
    private_172?(ip)
  end
end
