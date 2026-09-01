require "../spec_helper"

# Test helper: resolve internal links against an explicit build-output oracle
# (the private path `run` takes), under a name no other deadlink spec defines.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def resolve_with_oracle_for_test(links : Array(Link), content_dir : String,
                                   oracle : Hwaro::Utils::BuildOutput::Oracle) : Array(Result)
    check_internal_links(links, content_dir, [] of String, "", [] of String, GeneratedRoutes.new, oracle)
  end
end

# Issue #761: `check-links` accepts pipeline-emitted assets (compiled Sass,
# resized image variants, `[content.files]` output) by finding them in the
# configured output_dir. A serve-only workflow leaves that tree absent, so
# every such link was reported dead with no explanation.
private def asset_link(dir : String, url : String)
  Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
    file: File.join(dir, "content", "index.md"), url: url, kind: :internal)
end

describe "check-links build-output oracle" do
  it "accepts a pipeline asset from a real build tree" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")], tool: "check-links")
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      dead = cmd.resolve_with_oracle_for_test([asset_link(dir, "/css/app.css")], File.join(dir, "content"), oracle)

      dead.should be_empty
      oracle.consulted?.should be_true
    end
  end

  it "does not accept a pipeline asset from serve output" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      Hwaro::Utils::DevMarker.write(File.join(dir, "public"))

      oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [File.join(dir, "content")], tool: "check-links")
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      dead = cmd.resolve_with_oracle_for_test([asset_link(dir, "/css/app.css")], File.join(dir, "content"), oracle)

      dead.size.should eq(1)
      oracle.hint.to_s.should contain("hwaro build")
    end
  end

  # The human report carries the caveat only when it changes how the result
  # reads. Here every link resolves — through a tree older than the content —
  # so the run is "healthy" but the verdict rests on stale evidence.
  it "prints the stale-output caveat under an otherwise healthy report" do
    Dir.mktmpdir do |dir|
      content = File.join(dir, "content")
      FileUtils.mkdir_p(content)
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n))
      File.write(File.join(content, "index.md"), "---\ntitle: I\n---\n[css](/css/app.css)")
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      File.touch(File.join(dir, "public", "css", "app.css"), Time.utc(2026, 1, 1))
      File.touch(File.join(content, "index.md"), Time.utc(2026, 2, 1))

      output = with_captured_log do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.run(["-c", content, "--internal-only"])
      end

      output.should contain("all healthy")
      output.should contain("older than the newest source")
      output.should contain("public/")
    end
  end

  it "leaves the report alone when the build tree is current" do
    Dir.mktmpdir do |dir|
      content = File.join(dir, "content")
      FileUtils.mkdir_p(content)
      FileUtils.mkdir_p(File.join(dir, "public", "css"))
      File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n))
      File.write(File.join(content, "index.md"), "---\ntitle: I\n---\n[css](/css/app.css)")
      File.write(File.join(dir, "public", "css", "app.css"), "body{}")
      File.touch(File.join(content, "index.md"), Time.utc(2026, 1, 1))
      File.touch(content, Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "config.toml"), Time.utc(2026, 1, 1))
      File.touch(File.join(dir, "public", "css", "app.css"), Time.utc(2026, 2, 1))

      output = with_captured_log do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.run(["-c", content, "--internal-only"])
      end

      output.should contain("all healthy")
      output.should_not contain("hwaro build")
    end
  end
end
