require "../../../../spec_helper"

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
      File.touch(File.join(dir, "public", "css"), Time.utc(2026, 1, 1))
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

# A file beside a page exists in content/ whether or not the build publishes
# it. With `[content.files] allow_extensions` naming only images, a linked
# `doc.pdf` never reaches the output: the link is dead, and was reported
# healthy because its source is there.
private def dead_bundle_files(config_extra : String) : Hash(String, String?)
  Dir.mktmpdir do |dir|
    content = File.join(dir, "content")
    FileUtils.mkdir_p(File.join(content, "b"))
    File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n#{config_extra}))
    page = File.join(content, "b", "index.md")
    File.write(page, "---\ntitle: B\n---\nbody")
    names = %w[doc.pdf pic.png data.json]
    names.each { |name| File.write(File.join(content, "b", name), "x") }
    links = names.map { |name| Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(file: page, url: name, kind: :internal) }
    oracle = Hwaro::Utils::BuildOutput.oracle("public", root: dir, sources: [content], tool: "check-links")
    Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.resolve_with_oracle_for_test(links, content, oracle).to_h { |r| {r.link.url, r.error} }
  end
end

describe "check-links and content files the build leaves out" do
  it "reports a link to a file the allow-list leaves out, and says why" do
    dead = dead_bundle_files(%([content.files]\nallow_extensions = ["png"]\n))
    dead.keys.should eq(["doc.pdf"])
    dead["doc.pdf"].to_s.should contain("the build does not publish it")
  end

  it "reports a link to a file a deny rule excludes" do
    dead_bundle_files(%([content.files]\ndisallow_extensions = ["pdf"]\n)).keys.should eq(["doc.pdf"])
  end

  it "keeps resolving by the source when no rule decides" do
    dead_bundle_files("").should be_empty
  end
end
