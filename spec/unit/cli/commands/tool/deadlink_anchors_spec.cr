require "../../../../spec_helper"

# Test helper: scan a content dir, then check the collected fragment links
# against `public/` under it.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def dead_anchors_for_test(dir : String) : Array(String)
    content = File.join(dir, "content")
    find_internal_links(content)
    oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [content], tool: "check-links")
    check_anchor_links(@anchor_links, content, "", [] of String, oracle, nil).map { |r| "#{File.basename(r.link.file)} #{r.link.url}" }
  end
end

private def anchor_site(dir : String, pages : Hash(String, {String, String}))
  pages.each do |name, (source, html)|
    File.write(File.join(dir, "content", "#{name}.md"), "---\ntitle: #{name}\n---\n#{source}")
    FileUtils.mkdir_p(File.join(dir, "public", name))
    File.write(File.join(dir, "public", name, "index.html"), html)
  end
end

describe "check-links anchors" do
  it "reports fragments with no matching id/name in the target's built HTML" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      anchor_site(dir, {
        "a" => {"[ok](#intro) [bad](#gone) [b](/b/#there) [b2](../b/#nope) [at](@/b.md#nope2) <a href=\"/b/#old\">o</a> [ext](https://x.com/#y) [miss](/missing/#q)",
                %(<h1 id="intro">A</h1>)},
        "b" => {"body", %(<h2 id=there>B</h2><a name="old"></a>)},
      })

      dead = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.dead_anchors_for_test(dir)
      dead.sort.should eq(["a.md #gone", "a.md ../b/#nope", "a.md @/b.md#nope2"])
    end
  end

  it "checks fragments in used reference definitions, not unused ones" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      anchor_site(dir, {"a" => {"[x][ref] [y][ok]\n\n[ref]: #refdef\n[ok]: #intro\n[Note]: #unused\n", %(<h1 id="intro">A</h1>)}})
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.dead_anchors_for_test(dir).should eq(["a.md #refdef"])
    end
  end

  it "checks nothing without a usable build tree" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      File.write(File.join(dir, "content", "a.md"), "---\ntitle: a\n---\n[bad](#gone)")
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.dead_anchors_for_test(dir).should be_empty
    end
  end

  it "runs healthy, and --skip-anchors drops the anchor scan" do
    Dir.mktmpdir do |dir|
      content = File.join(dir, "content")
      FileUtils.mkdir_p(content)
      File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n))
      anchor_site(dir, {"a" => {"[ok](#intro)", %(<h1 id="intro">A</h1>)}})

      output = with_captured_log do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.run(["-c", content, "--internal-only"])
      end
      output.should contain("1 anchor")
      output.should contain("all healthy")

      output = with_captured_log do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.run(["-c", content, "--internal-only", "--skip-anchors"])
      end
      output.should_not contain("anchors")
    end
  end

  it "ignores data-href attributes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      anchor_site(dir, {"a" => {"<a data-href=\"#gone\">x</a> <a href=\"#gone2\">y</a>", %(<h1 id="intro">A</h1>)}})
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.dead_anchors_for_test(dir).should eq(["a.md #gone2"])
    end
  end

  it "counts --ignore-url anchor links in the ignored total" do
    Dir.mktmpdir do |dir|
      content = File.join(dir, "content")
      FileUtils.mkdir_p(content)
      File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n))
      anchor_site(dir, {"a" => {"[bad](#gone)", %(<h1 id="intro">A</h1>)}})

      output = with_captured_log do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.run(["-c", content, "--internal-only", "--ignore-url", "gone"])
      end
      output.should contain("1 ignored")
    end
  end
end
