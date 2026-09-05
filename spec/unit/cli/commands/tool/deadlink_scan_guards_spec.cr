require "../../../../spec_helper"

# Review findings 5, 6, 11, 13 — all about WHAT the scanner treats as a link.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def scan_guard_internal_for_test(dir : String) : Array(Link)
    find_internal_links(dir)
  end

  def scan_guard_external_for_test(dir : String) : Array(Link)
    find_external_links(dir)
  end
end

private def guard_urls(body : String) : Array(String)
  urls = [] of String
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, "a.md"), "+++\ntitle = \"A\"\n+++\n#{body}\n")
    urls = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.scan_guard_internal_for_test(dir).map(&.url)
  end
  urls
end

describe "check-links scan guards" do
  # Finding 5: the definition guard was shape-only, so a prose line whose first
  # token happens to be path-shaped was scanned as a link definition.
  describe "reference definitions require a matching reference (finding 5)" do
    it "ignores a prose line that merely looks like a definition" do
      guard_urls("[Note]: /usr/bin is where the binary lives on most systems").should be_empty
    end

    it "ignores a definition whose label is never referenced" do
      guard_urls("Body text.\n\n[unused]: /never-referenced/").should be_empty
    end

    it "still finds a definition used by a full reference" do
      guard_urls("See [docs][d].\n\n[d]: /guide/").should eq(["/guide/"])
    end

    it "still finds a definition used by a collapsed reference" do
      guard_urls("See [d][].\n\n[d]: /guide/").should eq(["/guide/"])
    end

    it "still finds a definition used by a shortcut reference" do
      guard_urls("See [d] here.\n\n[d]: /guide/").should eq(["/guide/"])
    end

    it "matches labels case-insensitively, as CommonMark does" do
      guard_urls("See [Docs][D].\n\n[d]: /guide/").should eq(["/guide/"])
    end
  end

  # Finding 6: `strip_code` handled fenced blocks and inline spans only.
  describe "indented code and HTML comments are not links (finding 6)" do
    it "ignores links inside an indented code block" do
      guard_urls("Example:\n\n    <a href=\"/indented-html/\">x</a>\n    [md](/indented-md/)\n")
        .should be_empty
    end

    it "ignores links inside an HTML comment" do
      guard_urls("<!-- <img src=\"/commented.png\"> -->").should be_empty
    end

    it "ignores links inside a multi-line HTML comment" do
      guard_urls("<!--\n<a href=\"/c1/\">x</a>\n[m](/c2/)\n-->").should be_empty
    end

    it "keeps text on either side of an inline comment" do
      guard_urls("[before](/b/) <!-- [hidden](/h/) --> [after](/a/)")
        .should eq(["/b/", "/a/"])
    end

    it "does NOT treat a list-item continuation as indented code" do
      # The reason the sibling validator gave up on indented blocks: a 4-space
      # continuation under a list item is prose, and its links are real.
      guard_urls("- item\n    continuation with [real](/guide/)\n")
        .should eq(["/guide/"])
    end

    it "still finds links in ordinary indented-but-not-code context" do
      guard_urls("1. step\n    see [here](/guide/)\n").should eq(["/guide/"])
    end
  end

  # Finding 13: `<source>` and `srcset` are the common hand-written HTML in
  # docs content, and an unquoted attribute is legal HTML.
  describe "HTML link forms (finding 13)" do
    it "finds every candidate in an img srcset" do
      guard_urls(%(<img srcset="/a.webp 1x, /b.webp 2x" src="/c.png">))
        .should eq(["/a.webp", "/b.webp", "/c.png"])
    end

    it "finds source src and srcset inside picture/video" do
      guard_urls(%(<picture><source srcset="/s1.webp"><source src="/s2.mp4"></picture>))
        .should eq(["/s1.webp", "/s2.mp4"])
    end

    it "finds an unquoted attribute value" do
      guard_urls("<a href=/unquoted/>x</a>").should eq(["/unquoted/"])
    end

    it "still skips template expressions and schemes" do
      guard_urls(%(<img src="{{ page.image }}"><a href="mailto:a@b.com">m</a>))
        .should be_empty
    end
  end

  # Finding 11: `run` scans the tree twice, so an unreadable file warned twice.
  describe "unreadable files warn once (finding 11)" do
    it "reads and reports each file a single time per invocation" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "bad.md"), Bytes[0x2B, 0x2B, 0x2B, 0x0A, 0xFF, 0x0A])

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        output = with_captured_log do
          cmd.scan_guard_external_for_test(dir)
          cmd.scan_guard_internal_for_test(dir)
        end

        output.scan(/Skipping .*bad\.md/).size.should eq(1)
      end
    end
  end
end
