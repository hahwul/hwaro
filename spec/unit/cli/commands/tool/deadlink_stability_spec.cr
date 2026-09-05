require "../../../../spec_helper"

# Helpers exposing private methods under names that do not collide with the
# other deadlink spec files (they all compile into one binary).
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def stability_external_links_for_test(dir : String) : Array(Link)
    find_external_links(dir)
  end

  def stability_private_host_for_test?(host : String) : Bool
    private_host?(host)
  end

  def stability_ascii_host_for_test(host : String) : String
    ascii_host(host)
  end

  def stability_private_ip_for_test?(ip : Socket::IPAddress) : Bool
    private_ip_address?(ip)
  end

  def stability_private_host_cache_for_test : Hash(String, Bool)
    @private_host_cache
  end
end

private def external_urls(body : String) : Array(String)
  urls = [] of String
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, "a.md"), "---\ntitle: A\n---\n#{body}\n")
    urls = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.stability_external_links_for_test(dir).map(&.url)
  end
  urls
end

describe "check-links stability regressions" do
  # Finding 5: external URLs written in raw HTML were never checked — the
  # external scan only saw markdown-style links, and the HTML pass dropped
  # scheme-carrying URLs via skip_internal?.
  describe "external URLs in raw HTML" do
    it "finds http(s) hrefs in raw anchors" do
      external_urls(%(<a href="https://example.com/html-x">x</a>))
        .should eq(["https://example.com/html-x"])
    end

    it "finds external img src and srcset candidates" do
      external_urls(%(<img srcset="https://cdn.example.com/a.webp 1x, /local.webp 2x" src="https://cdn.example.com/p.png">))
        .should eq(["https://cdn.example.com/a.webp", "https://cdn.example.com/p.png"])
    end

    it "does not resurrect HTML externals from fenced code" do
      external_urls("```html\n<a href=\"https://example.com/fenced\">x</a>\n```")
        .should be_empty
    end

    it "skips unrendered template syntax, matching the internal HTML pass" do
      external_urls(%(<a href="https://example.com/{{ page.slug }}">x</a><a href="https://example.com/{% if a %}b{% endif %}">y</a>))
        .should be_empty
    end
  end

  # Finding 6: the external regex required `)` right after the URL, so a
  # CommonMark title or angle-bracket destination hid the link entirely.
  describe "titled and angle-bracket external destinations" do
    it "checks a titled external link" do
      external_urls(%([x](https://example.com/titled "T")))
        .should eq(["https://example.com/titled"])
    end

    it "checks an angle-bracket external link" do
      external_urls("[x](<https://example.com/angled>)")
        .should eq(["https://example.com/angled"])
    end

    it "checks a titled external image" do
      external_urls(%(![a](https://example.com/img.png 'title')))
        .should eq(["https://example.com/img.png"])
    end

    it "keeps query strings and fragments on external destinations" do
      external_urls("[x](https://example.com/s?q=a&b=c#frag)")
        .should eq(["https://example.com/s?q=a&b=c#frag"])
    end

    it "still ignores relative and scheme-only destinations" do
      external_urls("[r](/relative/) [m](mailto:a@b.c) [t](tel:123)")
        .should be_empty
    end
  end

  # Finding 11: the SSRF guard used string prefixes, missing IPv4-mapped IPv6
  # loopback and fe81–febf link-local addresses.
  describe "SSRF guard address classification" do
    it "blocks an IPv4-mapped IPv6 loopback literal" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.stability_private_host_for_test?("::ffff:127.0.0.1").should be_true
    end

    it "blocks fe81 link-local (fe80::/10 is wider than the 'fe80' prefix string)" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.stability_private_host_for_test?("fe81::1").should be_true
    end
  end

  # Finding 11 continued: pure address classification (no DNS involved).
  describe "private_ip_address? classification" do
    it "classifies mapped, link-local, ULA and unspecified addresses as private" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      {"::ffff:127.0.0.1", "::ffff:192.168.1.5", "::ffff:10.0.0.1",
       "fe81::1", "febf::1", "fd00::1", "127.0.0.1", "10.1.1.1",
       "192.168.0.9", "172.20.1.1", "169.254.1.1", "::", "0.0.0.0", "::1"}.each do |addr|
        cmd.stability_private_ip_for_test?(Socket::IPAddress.new(addr, 0)).should be_true
      end
    end

    it "leaves public addresses alone" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      {"8.8.8.8", "93.184.216.34", "2607:f8b0::1", "172.15.0.1", "172.32.0.1"}.each do |addr|
        cmd.stability_private_ip_for_test?(Socket::IPAddress.new(addr, 0)).should be_false
      end
    end
  end

  # Finding 4: private_host? resolved DNS synchronously on every occurrence
  # and redirect hop. Results are now memoized per host for the run.
  describe "private_host? memoization" do
    it "caches the verdict per host" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.stability_private_host_for_test?("localhost").should be_true
      cmd.stability_private_host_for_test?("localhost").should be_true
      cmd.stability_private_host_for_test?("127.0.0.1").should be_true

      cache = cmd.stability_private_host_cache_for_test
      cache.size.should eq(2)
      cache["localhost"].should be_true
      cache["127.0.0.1"].should be_true
    end
  end

  # Finding 7: non-ASCII (IDN) hosts failed DNS as-is and were reported
  # dead. Labels are punycoded for resolution/connection; the original URL
  # is kept for reporting.
  describe "IDN host conversion" do
    it "punycodes a non-ASCII host" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.stability_ascii_host_for_test("例え.jp").should eq("xn--r8jz45g.jp")
    end

    it "leaves an ASCII host untouched" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.stability_ascii_host_for_test("example.com").should eq("example.com")
    end

    it "punycodes only the non-ASCII labels of a mixed host" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.stability_ascii_host_for_test("docs.例え.jp").should eq("docs.xn--r8jz45g.jp")
    end
  end

  # Finding 12: `--allow-status "403,"` rejected the empty trailing segment
  # with a confusing "Invalid --allow-status value:" (empty) message.
  describe "--allow-status parsing" do
    it "skips empty segments from a trailing comma" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.md"), "---\ntitle: I\n---\nNo links here")

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
          cmd.run(["-c", dir, "--internal-only", "--allow-status", "403,"])
        end

        output.should contain("checked")
      end
    end

    it "still rejects a non-numeric segment" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      ex = expect_raises(Hwaro::HwaroError) do
        cmd.run(["--allow-status", "403,abc"])
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.not_nil!.should contain("Invalid --allow-status")
    end

    it "rejects an all-empty value instead of silently allowing nothing" do
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      ex = expect_raises(Hwaro::HwaroError) do
        cmd.run(["--allow-status", ","])
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      ex.message.not_nil!.should contain("Invalid --allow-status")
    end
  end
end
