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

    it "ignores links inside fenced code blocks and inline code" do
      Dir.mktmpdir do |dir|
        content = <<-MD
          Real link: [Real](https://real.example.com)

          ```markdown
          [Example](https://example.com/in-fence)
          ```

          Inline `[Inline](https://example.com/inline)` should be ignored too.
          MD
        File.write(File.join(dir, "test.md"), content)

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_links_for_test(dir)

        links.map(&.url).should eq(["https://real.example.com"])
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

    it "unwraps an angle-bracket destination" do
      # Regression: `[t](</about/>)` is a plain CommonMark destination that the
      # build resolves fine, but the extractor kept the angle brackets (and the
      # whitespace split turned `</my page.md>` into `</my`), so every one was
      # reported dead — a false positive that fails a CI link gate.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"),
          %([Angle](</about/>)\n[AngleTitle](</posts/b/> "T")\n![AngleImg](</img/a.png>)))

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        urls = cmd.find_internal_links_for_test(dir).map(&.url)

        urls.should contain("/about/")
        urls.should contain("/posts/b/")
        urls.should contain("/img/a.png")
        urls.none?(&.includes?("<")).should be_true
        urls.none?(&.includes?(">")).should be_true
      end
    end

    it "unwraps an angle-bracket destination containing spaces" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), %([Spaced](</my page/>)))

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.find_internal_links_for_test(dir).map(&.url).should eq(["/my page/"])
      end
    end

    it "keeps balanced parentheses inside a destination" do
      # `[^\)]+` stopped at the first `)`, so `/docs/foo_(bar)` was scanned as
      # `/docs/foo_(bar` — a link the build resolves, reported dead.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"),
          %([Paren](/docs/foo_(bar))\n![ParenImg](/img/a_(1).png)))

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        urls = cmd.find_internal_links_for_test(dir).map(&.url)

        urls.should contain("/docs/foo_(bar)")
        urls.should contain("/img/a_(1).png")
      end
    end

    it "strips an optional CommonMark title from the destination" do
      # Regression: `[t](/url "title")` captured `/url "title"`, which never
      # resolves on disk — every titled internal link was falsely flagged dead.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), %([Titled](/posts/b/ "Go to B")\n![Alt](/img/a.png 'Image title')))

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_internal_links_for_test(dir)

        urls = links.map(&.url)
        urls.should contain("/posts/b/")
        urls.should contain("/img/a.png")
        urls.none?(&.includes?("\"")).should be_true
      end
    end

    it "ignores internal links and images inside fenced code blocks" do
      # Regression: the docs scaffold ships an image-syntax example
      # `![Diagram](/images/diagram.png)` inside a ```markdown fence. It is a
      # snippet, not a real image, so it must not be reported as a dead link.
      Dir.mktmpdir do |dir|
        content = <<-MD
          Reference images like this:

          ```markdown
          ![Diagram](/images/diagram.png)
          [Guide](/guide/missing/)
          ```

          But [this real link](/page/) should still be found.
          MD
        File.write(File.join(dir, "test.md"), content)

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_internal_links_for_test(dir)

        links.map(&.url).should eq(["/page/"])
      end
    end

    it "keeps fence pairing after a 4-backtick fence nesting a 3-backtick fence" do
      # Regression (dogfooding find): the old non-greedy /```[\s\S]*?```/
      # treated the inner ``` of a ````markdown example as a closer, so every
      # fence after it flipped polarity and example links inside later fences
      # were reported as dead.
      Dir.mktmpdir do |dir|
        content = <<-MD
          Nested fence example:

          ````markdown
          ```mermaid
          graph TD
          ```
          ````

          A later documentation-only snippet:

          ```markdown
          ![Diagram](/images/does-not-exist.png)
          ```

          But [this real link](/page/) should still be found.
          MD
        File.write(File.join(dir, "test.md"), content)

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.find_internal_links_for_test(dir)

        links.map(&.url).should eq(["/page/"])
      end
    end
  end

  describe "#sanitize_for_terminal (terminal-injection protection)" do
    it "strips raw ANSI/control bytes from semi-trusted URLs/paths" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      out = cmd.sanitize_for_terminal_for_test("\e[31mred\e[0m/page")

      # The ESC byte itself is a control char and is removed; the printable
      # `[31m...` residue remains — assert on absence of the control byte.
      out.includes?('\e').should be_false
      out.should eq("[31mred[0m/page")
    end

    it "removes embedded CR and BEL control bytes while preserving printable text" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      out = cmd.sanitize_for_terminal_for_test("/posts\r\x07/hello")

      out.includes?('\r').should be_false
      out.includes?('\a').should be_false
      out.should eq("/posts/hello")
    end

    it "leaves a fully-printable URL untouched" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.sanitize_for_terminal_for_test("https://example.com/path").should eq(
        "https://example.com/path"
      )
    end
  end

  describe "#run option validation" do
    it "rejects --timeout 0 with HWARO_E_USAGE" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      ex = expect_raises(Hwaro::HwaroError) do
        cmd.run(["--timeout", "0"])
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.not_nil!.should contain("Invalid --timeout")
    end

    it "rejects a non-numeric --concurrency with HWARO_E_USAGE" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      ex = expect_raises(Hwaro::HwaroError) do
        cmd.run(["--concurrency", "abc"])
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.not_nil!.should contain("Invalid --concurrency")
    end

    it "rejects a non-positive --concurrency with HWARO_E_USAGE" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      ex = expect_raises(Hwaro::HwaroError) do
        cmd.run(["--concurrency", "-1"])
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.not_nil!.should contain("Invalid --concurrency")
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

  # 172.x classification now goes through Socket::IPAddress#private? inside
  # private_ip_address? (the string-prefix helper it replaced missed
  # IPv4-mapped IPv6 forms entirely).
  describe "172.16.0.0/12 classification" do
    it "classifies the range boundaries like the old helper" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.private_ip_for_test?(Socket::IPAddress.new("172.16.0.1", 0)).should be_true
      cmd.private_ip_for_test?(Socket::IPAddress.new("172.31.255.255", 0)).should be_true
      cmd.private_ip_for_test?(Socket::IPAddress.new("172.15.0.1", 0)).should be_false
      cmd.private_ip_for_test?(Socket::IPAddress.new("172.32.0.1", 0)).should be_false
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

    # Regression for https://github.com/hahwul/hwaro/issues/488
    # The previous resolver computed `target + ".md"` AFTER joining the
    # URL, so for a trailing-slash URL like `/about/` the candidate
    # became `content/about/.md` (note the stray slash). A leaf page
    # whose URL ends with `/` was therefore reported as a dead link
    # even though `content/about.md` clearly existed.
    it "resolves trailing-slash URLs to a sibling .md file (leaf page)" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "about.md"), "leaf page")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/about/", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)

        results.should be_empty
      end
    end

    it "resolves trailing-slash URLs nested under a section" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "posts"))
        File.write(File.join(dir, "posts", "hello.md"), "leaf page")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/posts/hello/", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)

        results.should be_empty
      end
    end

    # Regression (dogfooding find): the checker treated Zola-style `@/`
    # content-root links as paths relative to the source file, so a valid
    # `@/index.md` resolved to `content/@/index.md` and was reported dead
    # even though the build resolves it fine.
    it "resolves Zola-style @/ content-root links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.md"), "home")
        FileUtils.mkdir_p(File.join(dir, "posts"))
        File.write(File.join(dir, "posts", "hello.md"), "post")

        links = [
          Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
            file: File.join(dir, "posts", "other.md"), url: "@/index.md", kind: :internal
          ),
          Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
            file: File.join(dir, "posts", "other.md"), url: "@/posts/hello.md", kind: :internal
          ),
        ]

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.check_internal_links_for_test(links, dir).should be_empty
      end
    end

    it "still flags missing @/ content-root links" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.md"), "home")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.md"), url: "@/does-not-exist.md", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)
        results.size.should eq(1)
        results[0].error.not_nil!.should contain("not found")
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

    # Regression: `URI.decode` turns `%00` into a real NUL byte, and the first
    # `File.exists?` probe in `resolves?` then raised
    # `ArgumentError: String contains null byte` out of libc. That aborted the
    # entire run with exit 1 — the same code as "links are dead", so CI could
    # not tell the two apart — and left `--json` writing zero bytes to stdout.
    # The hostile link must degrade on its own, like an unreadable file does.
    it "reports a percent-encoded NUL as a dead link and keeps checking the others" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "content")
        nul_link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/a%00b", kind: :internal
        )
        dead_link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/does-not-exist/", kind: :internal
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([nul_link, dead_link], dir)

        results.size.should eq(2)
        results[0].link.url.should eq("/a%00b")
        results[0].error.not_nil!.should contain("Invalid link target")
        # The genuinely dead link that used to be swallowed by the abort.
        results[1].link.url.should eq("/does-not-exist/")
        results[1].error.not_nil!.should contain("not found")
      end
    end

    it "reports a percent-encoded NUL in an image path as dead" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.md"), "content")
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "test.md"), url: "/a%00b.png", kind: :image
        )

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        results = cmd.check_internal_links_for_test([link], dir)

        results.size.should eq(1)
        results[0].error.not_nil!.should contain("Invalid link target")
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
  @@disable_private_host_check = false

  def self.disable_private_host_check=(val : Bool)
    @@disable_private_host_check = val
  end

  # Delegate to the real implementation (memoization + structured
  # Socket::IPAddress classification) instead of duplicating it, so the spec
  # binary exercises exactly what ships; the flag only bypasses the guard for
  # examples that talk to a local test server.
  private def private_host?(host : String) : Bool
    return false if @@disable_private_host_check
    previous_def
  end

  def find_links_for_test(dir : String) : Array(Link)
    find_external_links(dir)
  end

  def find_internal_links_for_test(dir : String) : Array(Link)
    find_internal_links(dir)
  end

  def check_internal_links_for_test(links : Array(Link), content_dir : String, taxonomy_names : Array(String) = [] of String, base_path : String = "") : Array(Result)
    check_internal_links(links, content_dir, taxonomy_names, base_path)
  end

  def check_links_concurrently_for_test(links : Array(Link), timeout_seconds : Int32, max_concurrency : Int32) : Array(Result)
    check_links_concurrently(links, timeout_seconds, max_concurrency)
  end

  def private_host_for_test?(host : String) : Bool
    private_host?(host)
  end

  def private_ip_for_test?(ip : Socket::IPAddress) : Bool
    private_ip_address?(ip)
  end

  def sanitize_for_terminal_for_test(s : String) : String
    sanitize_for_terminal(s)
  end
end

describe "check-links ember output" do
  it "renders heading, scan context, and a healthy outcome for resolving internal links" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "target.md"), "---\ntitle: T\n---\nBody")
      File.write(File.join(dir, "index.md"), "---\ntitle: I\n---\n[t](/target)")

      output = with_captured_log do
        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.run(["-c", dir, "--internal-only"])
      end

      output.should contain("hwaro: check-links")
      output.should contain("scan: 0 external, 1 internal")
      output.should contain("checked: 1 link, all healthy")
      output.should_not contain("\e[")
    end
  end

  it "reports an info outcome when no links exist" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.md"), "---\ntitle: I\n---\nNo links here")

      output = with_captured_log do
        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.run(["-c", dir, "--internal-only"])
      end

      output.should contain("checked: no links found")
    end
  end

  it "allows one level of balanced parens in Wikipedia-style URLs" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.md"), "[Wiki](https://en.wikipedia.org/wiki/Array_(data_structure))")
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      links = cmd.find_links_for_test(dir)
      links.size.should eq(1)
      links[0].url.should eq("https://en.wikipedia.org/wiki/Array_(data_structure)")
    end
  end

  it "skips tel: and protocol-relative links" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.md"), "[Tel](tel:123456) [Relative](//example.com/foo) [Valid](/internal)")
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      links = cmd.find_internal_links_for_test(dir)
      links.size.should eq(1)
      links[0].url.should eq("/internal")
    end
  end

  it "decodes percent-encoded internal paths" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "user guide.pdf"), "content")
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: File.join(dir, "test.md"), url: "/user%20guide.pdf", kind: :internal
      )
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      results = cmd.check_internal_links_for_test([link], dir)
      results.should be_empty
    end
  end

  it "strips base path prefix from root-relative URLs" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "posts"))
      File.write(File.join(dir, "posts", "hello.md"), "hello")
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: File.join(dir, "test.md"), url: "/repo/posts/hello/", kind: :internal
      )
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      results = cmd.check_internal_links_for_test([link], dir, base_path: "/repo")
      results.should be_empty
    end
  end

  it "follows redirects, retries on 405 with GET, and sends User-Agent header" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true

    begin
      user_agent = ""
      requests = [] of String

      server = HTTP::Server.new do |context|
        user_agent = context.request.headers["User-Agent"]? || ""
        requests << context.request.method

        case context.request.path
        when "/redirect"
          context.response.status_code = 301
          context.response.headers["Location"] = "/target"
        when "/target"
          context.response.status_code = 200
        when "/method-retry"
          if context.request.method == "HEAD"
            context.response.status_code = 405
          else
            context.response.status_code = 200
          end
        else
          context.response.status_code = 404
        end
      end

      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      port = address.port

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new

      link1 = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{port}/redirect", kind: :external
      )
      results = cmd.check_links_concurrently_for_test([link1], 5, 1)
      results.size.should eq(1)
      results[0].status.should eq(200)
      user_agent.should eq("hwaro-link-checker/1.0")

      requests.clear
      link2 = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{port}/method-retry", kind: :external
      )
      results2 = cmd.check_links_concurrently_for_test([link2], 5, 1)
      results2.size.should eq(1)
      results2[0].status.should eq(200)
      requests.should eq(["HEAD", "GET"])
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end

  it "skips private hosts, reporting status -1 and info logs" do
    cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.md"), "[Private](http://127.0.0.1/foo)")

      output = with_captured_log do
        cmd.run(["-c", dir, "--external-only"])
      end

      output.should contain("Skipped: private/internal address")
      output.should_not contain("✗")
    end
  end
end

describe "check-links redirect and dedup behavior" do
  # Finding 8: 303 was missing from the followed-redirect set, so a live link
  # behind a See Other was reported dead with status 303.
  it "follows a 303 redirect with GET" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true
    begin
      target_methods = [] of String
      server = HTTP::Server.new do |context|
        case context.request.path
        when "/see-other"
          context.response.status_code = 303
          context.response.headers["Location"] = "/result"
        when "/result"
          target_methods << context.request.method
          context.response.status_code = 200
        else
          context.response.status_code = 404
        end
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{address.port}/see-other", kind: :external
      )
      results = cmd.check_links_concurrently_for_test([link], 5, 1)

      results.size.should eq(1)
      results[0].status.should eq(200)
      # RFC 9110: 303 is followed with GET regardless of the original method.
      target_methods.should eq(["GET"])
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end

  # Finding 9: redirect loops / Location-less redirects recorded the redirect
  # code as the result status, so `--allow-status 301` classified broken
  # redirects as healthy. They must carry the -1 sentinel like other failures.
  it "reports a redirect loop with the -1 sentinel, not the redirect code" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true
    begin
      server = HTTP::Server.new do |context|
        context.response.status_code = 301
        context.response.headers["Location"] = "/loop"
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{address.port}/loop", kind: :external
      )
      results = cmd.check_links_concurrently_for_test([link], 5, 1)

      results.size.should eq(1)
      results[0].status.should eq(-1)
      results[0].error.not_nil!.should contain("Too many redirects")
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end

  it "reports a Location-less redirect with the -1 sentinel" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true
    begin
      server = HTTP::Server.new do |context|
        context.response.status_code = 302
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{address.port}/nowhere", kind: :external
      )
      results = cmd.check_links_concurrently_for_test([link], 5, 1)

      results.size.should eq(1)
      results[0].status.should eq(-1)
      results[0].error.not_nil!.should contain("Redirect without Location")
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end

  # Finding 10: identical external URLs were contacted once per occurrence,
  # so 50 pages linking the same site produced 50 simultaneous requests and
  # 429 false positives. Each unique URL must be contacted once, with the
  # result fanned back out to every occurrence.
  it "contacts an identical external URL only once but reports every occurrence" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true
    begin
      hits = Atomic(Int32).new(0)
      server = HTTP::Server.new do |context|
        hits.add(1) if context.request.path == "/dup"
        context.response.status_code = 200
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      url = "http://127.0.0.1:#{address.port}/dup"
      links = ["a.md", "b.md", "c.md"].map do |file|
        Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(file: file, url: url, kind: :external)
      end

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      results = cmd.check_links_concurrently_for_test(links, 5, 4)

      # One reported result per occurrence, each with its own file...
      results.size.should eq(3)
      results.map(&.link.file).sort!.should eq(["a.md", "b.md", "c.md"])
      results.all? { |r| r.status == 200 }.should be_true
      # ...but the server was contacted exactly once.
      hits.get.should eq(1)
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end

  # Finding 13: each redirect hop could take up to the full --timeout, so a
  # slow chain multiplied the budget. Elapsed time is now tracked across hops
  # and following stops once 3× the configured timeout is exceeded (the
  # headroom keeps slow-but-healthy few-hop chains passing).
  it "stops following redirects when the total time budget is exhausted" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true
    begin
      server = HTTP::Server.new do |context|
        case context.request.path
        when "/r1", "/r2", "/r3", "/r4"
          sleep 0.9.seconds
          nxt = {"/r1" => "/r2", "/r2" => "/r3", "/r3" => "/r4", "/r4" => "/final"}[context.request.path]
          context.response.status_code = 302
          context.response.headers["Location"] = nxt
        else
          context.response.status_code = 200
        end
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{address.port}/r1", kind: :external
      )
      # Each hop stays under the 1s per-request timeout, but the chain as a
      # whole (~3.6s of server sleeps) exceeds the 3s (1s × 3) total budget.
      results = cmd.check_links_concurrently_for_test([link], 1, 1)

      results.size.should eq(1)
      results[0].status.should eq(-1)
      results[0].error.not_nil!.downcase.should contain("timed out")
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end

  # The 3× headroom exists so a slow-but-healthy short chain (every hop within
  # the per-request timeout) is NOT converted into a false dead link.
  it "still passes a slow-but-healthy two-hop redirect chain" do
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = true
    begin
      server = HTTP::Server.new do |context|
        case context.request.path
        when "/s1", "/s2"
          sleep 0.6.seconds
          nxt = {"/s1" => "/s2", "/s2" => "/final"}[context.request.path]
          context.response.status_code = 302
          context.response.headers["Location"] = nxt
        else
          context.response.status_code = 200
        end
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
        file: "test.md", url: "http://127.0.0.1:#{address.port}/s1", kind: :external
      )
      results = cmd.check_links_concurrently_for_test([link], 1, 1)

      results.size.should eq(1)
      results[0].status.should eq(200)
    ensure
      server.try(&.close)
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.disable_private_host_check = false
    end
  end
end
