require "../spec_helper"

# =============================================================================
# Functional CLI integration tests for `hwaro tool` subcommands that were
# previously uncovered by `cli_commands_spec.cr` (which already covers
# tool list, tool convert, tool doctor, and the top-level doctor).
#
# Each test spawns the built binary at bin/hwaro and asserts on exit status
# plus filesystem side effects. CI builds the binary via `shards build`
# before running specs.
#
# Note on streams: Hwaro::Logger.info / .success write to Logger.io (STDOUT
# by default). Hwaro::Logger.warn / .error write to Logger.err_io (STDERR
# by default). Tests assert on the captured stream that matches the
# originating log method.
# =============================================================================

private HWARO_BIN = File.expand_path("../../bin/hwaro", __DIR__)

# Pre-flight check: surface a clear error if the binary is missing rather
# than letting every test fail with an inscrutable Process.run error.
Spec.before_suite do
  unless File.exists?(HWARO_BIN) && File::Info.executable?(HWARO_BIN)
    raise "Binary #{HWARO_BIN} is missing or not executable. Run `shards build` first."
  end
end

private def with_initialized_project(&)
  temp_dir = File.tempname("hwaro_test")
  Dir.mkdir(temp_dir)
  project_dir = File.join(temp_dir, "test_site")
  Dir.mkdir(project_dir)
  begin
    init_status = Process.run(HWARO_BIN, ["init", project_dir],
      output: IO::Memory.new, error: IO::Memory.new)
    init_status.success?.should be_true
    yield project_dir
  ensure
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end
end

# Every test in this file runs the binary inside a temp project directory,
# so chdir is required (not optional). Process.run is invoked uniformly.
private def run_hwaro(args : Array(String), chdir : String)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run(HWARO_BIN, args, chdir: chdir, output: output, error: error)
  {status, output.to_s, error.to_s}
end

# Variant for router-level tests that don't require an initialized project.
private def run_hwaro_no_chdir(args : Array(String))
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run(HWARO_BIN, args, output: output, error: error)
  {status, output.to_s, error.to_s}
end

describe "hwaro tool (router)" do
  it "exits 1 and prints help when no subcommand is given" do
    status, output, _ = run_hwaro_no_chdir(["tool"])
    status.success?.should be_false
    output.should contain("Usage")
    output.should contain("subcommand")
  end

  it "exits with HWARO_E_USAGE on an unknown subcommand" do
    status, output, error = run_hwaro_no_chdir(["tool", "nonexistent-subcommand"])
    status.success?.should be_false
    status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    # Structured classified error on stderr; help banner must not be
    # dumped to stdout on a typo.
    error.should contain("HWARO_E_USAGE")
    error.should contain("unknown command 'tool nonexistent-subcommand'")
    error.should contain("hwaro tool --help")
    output.should_not contain("Available subcommands")
  end

  it "suggests the closest subcommand for near-miss typos" do
    status, _, error = run_hwaro_no_chdir(["tool", "stts"])
    status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    error.should contain("Did you mean 'stats'?")
  end

  it "omits the suggestion when no candidate is close" do
    status, _, error = run_hwaro_no_chdir(["tool", "xyzabc"])
    status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    error.should_not contain("Did you mean")
    error.should contain("hwaro tool --help")
  end

  it "emits a JSON error payload under --json for an unknown subcommand" do
    status, output, _ = run_hwaro_no_chdir(["tool", "nonexistent-subcommand", "--json"])
    status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    parsed = JSON.parse(output.strip)
    parsed["status"].as_s.should eq("error")
    parsed["error"]["code"].as_s.should eq("HWARO_E_USAGE")
    parsed["error"]["message"].as_s.should contain("unknown command")
  end

  it "prints help and exits 0 when invoked with help" do
    status, output, _ = run_hwaro_no_chdir(["tool", "help"])
    status.success?.should be_true
    output.should contain("Available subcommands")
  end

  it "categorizes visible subcommands under Content / Site headings" do
    status, output, _ = run_hwaro_no_chdir(["tool", "--help"])
    status.success?.should be_true
    output.should contain("Content:")
    output.should contain("Site:")
  end
end

describe "hwaro tool stats" do
  it "prints statistics for an initialized project" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "stats"], chdir: project_dir)
      status.success?.should be_true
    end
  end

  it "emits JSON matching the documented schema under --json" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "stats", "--json"], chdir: project_dir)
      status.success?.should be_true
      # Must be a single JSON object parseable by external tools.
      parsed = JSON.parse(output.strip)
      parsed["total"].as_i?.should_not be_nil
      parsed["published"].as_i?.should_not be_nil
      parsed["drafts"].as_i?.should_not be_nil
      parsed["word_count"]["total"].as_i?.should_not be_nil
      parsed["tags"].as_h?.should_not be_nil
    end
  end
end

describe "hwaro tool validate" do
  it "validates content of an initialized project" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "validate"], chdir: project_dir)
      # Default scaffold has no validation errors → exit 0
      status.success?.should be_true
    end
  end

  it "emits {findings:[…]} under --json" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "validate", "--json"], chdir: project_dir)
      status.success?.should be_true
      parsed = JSON.parse(output.strip)
      parsed["findings"].as_a?.should_not be_nil
    end
  end
end

describe "hwaro tool unused-assets" do
  it "scans an initialized project without errors" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "unused-assets"], chdir: project_dir)
      status.success?.should be_true
    end
  end

  it "deletes unused files under --delete --force --json and keeps stdout valid JSON" do
    with_initialized_project do |project_dir|
      orphan = File.join(project_dir, "static", "orphan.png")
      File.write(orphan, "x")

      status, output, _ = run_hwaro(["tool", "unused-assets", "--delete", "--force", "--json"], chdir: project_dir)

      status.success?.should be_true
      File.exists?(orphan).should be_false
      # stdout must remain a single parseable JSON document — the
      # `Deleted: …` log lines must not leak onto stdout in JSON mode.
      parsed = JSON.parse(output.strip)
      parsed["unused_files"].as_a.map(&.as_s).should contain("static/orphan.png")
    end
  end

  it "does not delete under --delete --json without --force, and warns on stderr" do
    with_initialized_project do |project_dir|
      orphan = File.join(project_dir, "static", "orphan.png")
      File.write(orphan, "x")

      status, output, error = run_hwaro(["tool", "unused-assets", "--delete", "--json"], chdir: project_dir)

      status.success?.should be_true
      # Destructive action is skipped without --force, but not silently:
      # the file survives, stdout stays parseable, and stderr explains why.
      File.exists?(orphan).should be_true
      JSON.parse(output.strip)
      error.should contain("--force")
    end
  end
end

describe "hwaro tool check-links" do
  it "exits 0 or 1 (no crash) on an initialized project" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "check-links"], chdir: project_dir)
      # check-links exits 0 when no broken links and 1 when some are found.
      # Anything else (e.g. signal-based exit from a crash) is a bug.
      [0, 1].includes?(status.exit_code).should be_true
    end
  end

  it "emits {dead_internal, dead_external} under --json" do
    with_initialized_project do |project_dir|
      _, output, _ = run_hwaro(["tool", "check-links", "--json", "--internal-only"], chdir: project_dir)
      parsed = JSON.parse(output.strip)
      parsed["dead_internal"].as_a?.should_not be_nil
      parsed["dead_external"].as_a?.should_not be_nil
    end
  end
end

describe "hwaro tool platform" do
  it "generates vercel.json for the vercel platform" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "platform", "vercel", "--force"], chdir: project_dir)
      status.success?.should be_true
      File.exists?(File.join(project_dir, "vercel.json")).should be_true
    end
  end

  it "generates netlify.toml for the netlify platform" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "platform", "netlify", "--force"], chdir: project_dir)
      status.success?.should be_true
      File.exists?(File.join(project_dir, "netlify.toml")).should be_true
    end
  end

  it "exits with the shared usage code on an unknown platform" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "platform", "definitely-not-real"], chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("unsupported platform: definitely-not-real")
    end
  end

  it "exits with the shared usage code when no platform is given" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "platform"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("missing <platform> argument")
    end
  end

  it "prints to stdout and writes no file when --stdout is passed" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(
        ["tool", "platform", "vercel", "--stdout"], chdir: project_dir
      )
      status.success?.should be_true
      output.size.should be > 0
      File.exists?(File.join(project_dir, "vercel.json")).should be_false
    end
  end
end

describe "hwaro tool ci" do
  it "generates .github/workflows/deploy.yml for github-actions" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(
        ["tool", "ci", "github-actions", "--force"], chdir: project_dir
      )
      status.success?.should be_true
      File.exists?(File.join(project_dir, ".github/workflows/deploy.yml")).should be_true
    end
  end

  it "exits 1 when no provider is given" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "ci"], chdir: project_dir)
      status.success?.should be_false
    end
  end

  it "warns about deprecation in favor of `tool platform github-pages`" do
    with_initialized_project do |project_dir|
      _, output, err = run_hwaro(
        ["tool", "ci", "github-actions", "--stdout"], chdir: project_dir
      )
      # Deprecation notice uses Logger.warn → stderr.
      err.should contain("DEPRECATED")
      # Co-signal: the actual workflow content was also generated to stdout,
      # confirming the deprecation log didn't short-circuit the command.
      output.should contain("workflow")
    end
  end
end

describe "hwaro tool agents-md" do
  it "prints local-mode AGENTS.md content to stdout by default" do
    with_initialized_project do |project_dir|
      # `init` writes AGENTS.md by default — remove it to verify the no-write
      # path of `tool agents-md` doesn't touch the file.
      agents_md = File.join(project_dir, "AGENTS.md")
      File.delete(agents_md) if File.exists?(agents_md)

      status, output, _ = run_hwaro(["tool", "agents-md"], chdir: project_dir)
      status.success?.should be_true
      output.should contain("AGENTS.md")
      File.exists?(File.join(project_dir, "AGENTS.md")).should be_false
    end
  end

  it "writes AGENTS.md when --write is passed" do
    with_initialized_project do |project_dir|
      agents_md = File.join(project_dir, "AGENTS.md")
      File.delete(agents_md) if File.exists?(agents_md)

      status, _, _ = run_hwaro(
        ["tool", "agents-md", "--write", "--force"], chdir: project_dir
      )
      status.success?.should be_true
      File.exists?(File.join(project_dir, "AGENTS.md")).should be_true
    end
  end

  it "supports --remote mode" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "agents-md", "--remote"], chdir: project_dir)
      status.success?.should be_true
      output.size.should be > 0
    end
  end
end

describe "hwaro tool import" do
  it "exits with HWARO_E_USAGE when source-type is missing" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "import"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("<source-type>")
    end
  end

  it "exits with HWARO_E_USAGE when path is missing" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "import", "hugo"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("<path>")
    end
  end

  it "exits with HWARO_E_USAGE on unknown source-type" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "import", "definitely-not-real", "/tmp"], chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("unknown source type")
    end
  end

  it "exits with HWARO_E_USAGE when source directory yields no importable content" do
    with_initialized_project do |project_dir|
      Dir.mktmpdir do |empty|
        FileUtils.mkdir_p(File.join(empty, "content"))
        status, _, err = run_hwaro(
          ["tool", "import", "hugo", empty, "-o", File.join(project_dir, "out")],
          chdir: project_dir
        )
        status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
        err.should contain("HWARO_E_USAGE")
        err.should contain("no importable content")
      end
    end
  end
end

describe "hwaro tool export" do
  it "exits with HWARO_E_USAGE when target-type is missing" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "export"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("<target-type>")
    end
  end

  it "exits with HWARO_E_USAGE on unknown target-type" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "export", "definitely-not-real"], chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("unknown target type")
    end
  end

  # Regression: `-o .` made every destination collapse back onto the source
  # file the exporter had just read, so the command rewrote the project's own
  # content/ in place (front matter re-serialized, comments dropped, `@/`
  # links flattened) and reported success. `hwaro build -o .` already
  # refused; export must too.
  it "exits with HWARO_E_CONFIG on -o . and leaves content byte-identical" do
    with_initialized_project do |project_dir|
      before = Dir.glob(File.join(project_dir, "content", "**", "*.md")).sort.map { |f| {f, File.read(f)} }
      before.should_not be_empty

      status, _, err = run_hwaro(["tool", "export", "hugo", "-o", "."], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
      err.should contain("HWARO_E_CONFIG")

      before.each do |(path, content)|
        File.read(path).should eq(content)
      end
    end
  end
end

describe "hwaro tool convert" do
  it "exits with HWARO_E_USAGE when format is missing" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "convert"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("<format>")
    end
  end

  it "exits with HWARO_E_USAGE on unknown format" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "convert", "to-xml"], chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("unknown format")
    end
  end

  it "exits HWARO_E_IO and emits a failing ConversionResult JSON for a missing content dir" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(
        ["tool", "convert", "to-yaml", "-c", "does-not-exist", "--json"],
        chdir: project_dir
      )
      # Same code as the human path below: an exit status that depends on the
      # output format hands machine consumers a different answer for the
      # identical failure. The payload shape is unchanged.
      status.exit_code.should eq(Hwaro::Errors::EXIT_IO)
      parsed = JSON.parse(output.strip)
      parsed["success"].as_bool.should be_false
      parsed["message"].as_s.should contain("not found")
    end
  end

  it "exits HWARO_E_IO for a missing content dir without --json" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "convert", "to-yaml", "-c", "does-not-exist"],
        chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_IO)
      err.should contain("HWARO_E_IO")
      err.should contain("not found")
    end
  end
end

describe "hwaro tool list" do
  it "exits with HWARO_E_USAGE when filter is missing" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "list"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
      err.should contain("<filter>")
    end
  end

  it "emits a JSON error payload under --json when filter is missing" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(
        ["tool", "list", "--json"], chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      parsed = JSON.parse(output.strip)
      parsed["error"]["code"].as_s.should eq("HWARO_E_USAGE")
    end
  end
end

describe "hwaro doctor (top-level alias)" do
  # Note: top-level command registration with CommandRegistry is exercised
  # via `cli_commands_spec.cr` (which instantiates Runner). This block
  # focuses on the alias's metadata equivalence with Tool::DoctorCommand.

  it "exposes the same description as Tool::DoctorCommand" do
    Hwaro::CLI::Commands::DoctorCommand::DESCRIPTION.should eq(
      Hwaro::CLI::Commands::Tool::DoctorCommand::DESCRIPTION
    )
  end

  it "exposes the same flags as Tool::DoctorCommand" do
    Hwaro::CLI::Commands::DoctorCommand.metadata.flags.should eq(
      Hwaro::CLI::Commands::Tool::DoctorCommand::FLAGS
    )
  end

  it "exposes the same positional args/choices" do
    Hwaro::CLI::Commands::DoctorCommand.metadata.positional_args.should eq(
      Hwaro::CLI::Commands::Tool::DoctorCommand::POSITIONAL_ARGS
    )
    Hwaro::CLI::Commands::DoctorCommand.metadata.positional_choices.should eq(
      Hwaro::CLI::Commands::Tool::DoctorCommand::POSITIONAL_CHOICES
    )
  end
end

# `check-links` had no idea which routes the BUILD generates, so it could only
# accept `/sitemap.xml` and `/rss.xml` once `public/` existed — reporting a
# site's own links dead in the lint-before-build order CI actually uses.
describe "hwaro tool check-links (generated routes)" do
  it "accepts config-generated routes and paginated section routes before a build" do
    with_initialized_project do |project_dir|
      content_dir = File.join(project_dir, "content")
      posts_dir = File.join(content_dir, "posts")
      # Replace the scaffold's content and config so the assertion depends
      # only on the routes under test.
      FileUtils.rm_rf(content_dir)
      Dir.mkdir_p(posts_dir)
      File.write(File.join(project_dir, "config.toml"), <<-TOML)
        title = "Site"
        base_url = "https://example.com"

        [sitemap]
        enabled = true

        [feeds]
        enabled = true
        TOML
      File.write(File.join(posts_dir, "_index.md"), "+++\ntitle = \"Posts\"\npaginate_by = 2\n+++\n")
      # Three pages at two per page, so `/posts/page/2/` really is reachable.
      File.write(File.join(posts_dir, "a.md"), "+++\ntitle = \"A\"\n+++\n")
      File.write(File.join(posts_dir, "b.md"), "+++\ntitle = \"B\"\n+++\n")
      File.write(File.join(posts_dir, "routes.md"), <<-MD)
        +++
        title = "Routes"
        +++

        [feed](/rss.xml)
        [map](/sitemap.xml)
        [robots](/robots.txt)
        [next](/posts/page/2/)
        [gone](/nope/)
        MD

      status, output, _ = run_hwaro(["tool", "check-links", "--internal-only", "--json"], chdir: project_dir)
      status.success?.should be_false
      dead = JSON.parse(output)["dead_internal"].as_a.map(&.["link"].["url"].as_s)
      dead.should eq(["/nope/"])
    end
  end

  it "refuses a feed path whose prefix is not a section, and an out-of-range page" do
    with_initialized_project do |project_dir|
      content_dir = File.join(project_dir, "content")
      blog_dir = File.join(content_dir, "blog")
      FileUtils.rm_rf(content_dir)
      Dir.mkdir_p(blog_dir)
      File.write(File.join(project_dir, "config.toml"), <<-TOML)
        title = "Site"
        base_url = "https://example.com"

        [feeds]
        enabled = true
        TOML
      # `generate_feeds` is what makes `/blog/rss.xml` a route at all — the
      # case under test is the PREFIX check, so the section opts in.
      File.write(File.join(blog_dir, "_index.md"), "+++\ntitle = \"Blog\"\npaginate_by = 2\ngenerate_feeds = true\n+++\n")
      File.write(File.join(blog_dir, "p1.md"), "+++\ntitle = \"P1\"\n+++\n")
      File.write(File.join(blog_dir, "p2.md"), "+++\ntitle = \"P2\"\n+++\n")
      File.write(File.join(blog_dir, "links.md"), <<-MD)
        +++
        title = "Links"
        +++

        [section feed](/blog/rss.xml)
        [page one](/blog/page/1/)
        [nowhere feed](/nowhere/rss.xml)
        [too far](/blog/page/99/)
        MD

      status, output, _ = run_hwaro(["tool", "check-links", "--internal-only", "--json"], chdir: project_dir)
      status.success?.should be_false
      dead = JSON.parse(output)["dead_internal"].as_a.map(&.["link"].["url"].as_s)
      dead.sort!.should eq(["/blog/page/99/", "/nowhere/rss.xml"])
    end
  end

  # A per-section feed exists only when the section sets
  # `generate_feeds = true`. `feed_route?` accepted `/<section>/rss.xml` for
  # ANY section with an `_index.md`, so the checker waved through a link that
  # 404s on the deployed site — including on `hwaro init --scaffold blog`,
  # whose `[feeds] sections = ["posts"]` only filters the SITE feed's items.
  it "reports a section feed for a section that never opted into feeds" do
    with_initialized_project do |project_dir|
      content_dir = File.join(project_dir, "content")
      posts_dir = File.join(content_dir, "posts")
      FileUtils.rm_rf(content_dir)
      Dir.mkdir_p(posts_dir)
      File.write(File.join(project_dir, "config.toml"), <<-TOML)
        title = "Site"
        base_url = "https://example.com"

        [feeds]
        enabled = true
        sections = ["posts"]
        TOML
      File.write(File.join(posts_dir, "_index.md"), "+++\ntitle = \"Posts\"\n+++\n")
      File.write(File.join(posts_dir, "links.md"), <<-MD)
        +++
        title = "Links"
        +++

        [site feed](/rss.xml)
        [section feed](/posts/rss.xml)
        MD

      status, output, _ = run_hwaro(["tool", "check-links", "--internal-only", "--json"], chdir: project_dir)
      status.success?.should be_false
      dead = JSON.parse(output)["dead_internal"].as_a.map(&.["link"].["url"].as_s)
      dead.should eq(["/posts/rss.xml"])
    end
  end

  it "accepts a section feed once the section declares generate_feeds" do
    with_initialized_project do |project_dir|
      content_dir = File.join(project_dir, "content")
      posts_dir = File.join(content_dir, "posts")
      FileUtils.rm_rf(content_dir)
      Dir.mkdir_p(posts_dir)
      File.write(File.join(project_dir, "config.toml"), <<-TOML)
        title = "Site"
        base_url = "https://example.com"

        [feeds]
        enabled = true
        TOML
      File.write(File.join(posts_dir, "_index.md"), "+++\ntitle = \"Posts\"\ngenerate_feeds = true\n+++\n")
      File.write(File.join(posts_dir, "links.md"), "+++\ntitle = \"Links\"\n+++\n\n[section feed](/posts/rss.xml)\n")

      status, output, _ = run_hwaro(["tool", "check-links", "--internal-only", "--json"], chdir: project_dir)
      status.success?.should be_true
      JSON.parse(output)["dead_internal"].as_a.should be_empty
    end
  end

  it "still reports /page/N/ under a section that does not paginate" do
    with_initialized_project do |project_dir|
      content_dir = File.join(project_dir, "content")
      posts_dir = File.join(content_dir, "posts")
      FileUtils.rm_rf(content_dir)
      Dir.mkdir_p(posts_dir)
      File.write(File.join(posts_dir, "_index.md"), "+++\ntitle = \"Posts\"\n+++\n")
      File.write(File.join(posts_dir, "routes.md"), "+++\ntitle = \"Routes\"\n+++\n\n[next](/posts/page/2/)\n")

      status, output, _ = run_hwaro(["tool", "check-links", "--internal-only", "--json"], chdir: project_dir)
      status.success?.should be_false
      dead = JSON.parse(output)["dead_internal"].as_a.map(&.["link"].["url"].as_s)
      dead.should contain("/posts/page/2/")
    end
  end
end

# =============================================================================
# Feature-flag coverage: the 2026-08 tool improvement batch.
# =============================================================================

describe "hwaro tool check-links (--ignore-url / --allow-status)" do
  it "silences a broken link matched by --ignore-url" do
    with_initialized_project do |project_dir|
      File.write(File.join(project_dir, "content", "broken.md"),
        "+++\ntitle = \"B\"\n+++\n\n[dead](/definitely-missing/)\n")

      status, _, _ = run_hwaro(["tool", "check-links", "--internal-only"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_GENERIC)

      ignored, _, _ = run_hwaro(
        ["tool", "check-links", "--internal-only", "--ignore-url", "definitely-missing"],
        chdir: project_dir
      )
      ignored.success?.should be_true
    end
  end

  it "supports * wildcards in --ignore-url patterns" do
    with_initialized_project do |project_dir|
      File.write(File.join(project_dir, "content", "broken.md"),
        "+++\ntitle = \"B\"\n+++\n\n[dead](/definitely-missing/)\n")

      status, _, _ = run_hwaro(
        ["tool", "check-links", "--internal-only", "--ignore-url", "/definitely*missing/"],
        chdir: project_dir
      )
      status.success?.should be_true
    end
  end

  it "emits skipped_external in the --json payload" do
    with_initialized_project do |project_dir|
      _, output, _ = run_hwaro(["tool", "check-links", "--json", "--internal-only"], chdir: project_dir)
      parsed = JSON.parse(output.strip)
      parsed["skipped_external"].as_a?.should_not be_nil
    end
  end

  it "rejects an invalid --allow-status value with the shared usage code" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "check-links", "--allow-status", "abc"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
    end
  end

  it "rejects an empty --ignore-url pattern with the shared usage code" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "check-links", "--ignore-url", " "], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
    end
  end
end

describe "hwaro tool validate (--strict / --max-warnings)" do
  it "gates warnings behind --strict and --max-warnings" do
    with_initialized_project do |project_dir|
      # Guarantees at least one warning-level finding (missing description).
      File.write(File.join(project_dir, "content", "warny.md"),
        "+++\ntitle = \"W\"\n+++\n\nBody\n")

      status, _, _ = run_hwaro(["tool", "validate"], chdir: project_dir)
      status.success?.should be_true

      strict, _, _ = run_hwaro(["tool", "validate", "--strict"], chdir: project_dir)
      strict.exit_code.should eq(Hwaro::Errors::EXIT_GENERIC)

      capped, _, _ = run_hwaro(["tool", "validate", "--max-warnings", "0"], chdir: project_dir)
      capped.exit_code.should eq(Hwaro::Errors::EXIT_GENERIC)

      loose, _, _ = run_hwaro(["tool", "validate", "--max-warnings", "999"], chdir: project_dir)
      loose.success?.should be_true
    end
  end

  it "applies --strict to the --json exit code too" do
    with_initialized_project do |project_dir|
      File.write(File.join(project_dir, "content", "warny.md"),
        "+++\ntitle = \"W\"\n+++\n\nBody\n")

      status, output, _ = run_hwaro(["tool", "validate", "--strict", "--json"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_GENERIC)
      JSON.parse(output.strip)["findings"].as_a?.should_not be_nil
    end
  end

  it "rejects a negative --max-warnings with the shared usage code" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "validate", "--max-warnings", "-1"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
    end
  end
end

describe "hwaro tool list (--sort / --reverse / --limit)" do
  it "sorts by path, reverses, and limits the --json output" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "list", "all", "--json", "--sort", "path"], chdir: project_dir)
      status.success?.should be_true
      paths = JSON.parse(output.strip).as_a.map(&.["path"].as_s)
      paths.should eq(paths.sort)
      paths.size.should be > 1

      _, reversed_out, _ = run_hwaro(
        ["tool", "list", "all", "--json", "--sort", "path", "--reverse"], chdir: project_dir
      )
      JSON.parse(reversed_out.strip).as_a.map(&.["path"].as_s).should eq(paths.reverse)

      _, limited_out, _ = run_hwaro(
        ["tool", "list", "all", "--json", "--limit", "1"], chdir: project_dir
      )
      JSON.parse(limited_out.strip).as_a.size.should eq(1)
    end
  end

  it "rejects an unknown --sort key with the shared usage code" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "list", "all", "--sort", "size"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
    end
  end

  it "rejects a non-positive --limit with the shared usage code" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(["tool", "list", "all", "--limit", "0"], chdir: project_dir)
      status.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
    end
  end
end

describe "hwaro tool stats (--top)" do
  it "accepts --top and rejects a non-positive value" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "stats", "--top", "3"], chdir: project_dir)
      status.success?.should be_true

      bad, _, err = run_hwaro(["tool", "stats", "--top", "0"], chdir: project_dir)
      bad.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
      err.should contain("HWARO_E_USAGE")
    end
  end
end

describe "hwaro tool unused-assets (--templates-dir)" do
  it "scans a custom templates directory for references" do
    with_initialized_project do |project_dir|
      File.write(File.join(project_dir, "static", "special.png"), "x")
      custom = File.join(project_dir, "mytemplates")
      FileUtils.mkdir_p(custom)
      File.write(File.join(custom, "extra.html"), %(<img src="/special.png">))

      _, default_out, _ = run_hwaro(["tool", "unused-assets", "--json"], chdir: project_dir)
      JSON.parse(default_out.strip)["unused_files"].as_a.map(&.as_s)
        .should contain("static/special.png")

      _, custom_out, _ = run_hwaro(
        ["tool", "unused-assets", "--json", "--templates-dir", "mytemplates"], chdir: project_dir
      )
      JSON.parse(custom_out.strip)["unused_files"].as_a.map(&.as_s)
        .should_not contain("static/special.png")
    end
  end
end

describe "hwaro tool import (--json / --dry-run)" do
  it "emits a per-file manifest under --json and writes nothing with --dry-run" do
    with_initialized_project do |project_dir|
      Dir.mktmpdir do |src|
        posts = File.join(src, "_posts")
        FileUtils.mkdir_p(posts)
        File.write(File.join(posts, "2024-01-01-hi.md"), "---\ntitle: Hi\n---\n\nBody\n")
        out_dir = File.join(project_dir, "imported")

        status, output, _ = run_hwaro(
          ["tool", "import", "jekyll", src, "-o", "imported", "--dry-run", "--json"],
          chdir: project_dir
        )
        status.success?.should be_true
        parsed = JSON.parse(output.strip)
        parsed["dry_run"].as_bool.should be_true
        parsed["imported_count"].as_i.should eq(1)
        parsed["files"].as_a.first["action"].as_s.should eq("imported")
        Dir.exists?(out_dir).should be_false
      end
    end
  end

  it "actually imports without --dry-run and reports the destination in the manifest" do
    with_initialized_project do |project_dir|
      Dir.mktmpdir do |src|
        posts = File.join(src, "_posts")
        FileUtils.mkdir_p(posts)
        File.write(File.join(posts, "2024-01-01-hi.md"), "---\ntitle: Hi\n---\n\nBody\n")

        status, output, _ = run_hwaro(
          ["tool", "import", "jekyll", src, "-o", "imported", "--json"],
          chdir: project_dir
        )
        status.success?.should be_true
        parsed = JSON.parse(output.strip)
        file = parsed["files"].as_a.first
        file["action"].as_s.should eq("imported")
        File.exists?(File.join(project_dir, file["path"].as_s)).should be_true
      end
    end
  end
end

describe "hwaro tool export (--json / --dry-run / classified errors)" do
  it "emits a per-file manifest under --json and writes nothing with --dry-run" do
    with_initialized_project do |project_dir|
      out_dir = File.join(project_dir, "exported")

      status, output, _ = run_hwaro(
        ["tool", "export", "jekyll", "-o", "exported", "--dry-run", "--json"],
        chdir: project_dir
      )
      status.success?.should be_true
      parsed = JSON.parse(output.strip)
      parsed["dry_run"].as_bool.should be_true
      parsed["exported_count"].as_i.should be > 0
      parsed["files"].as_a.should_not be_empty
      Dir.exists?(out_dir).should be_false
    end
  end

  it "exits with HWARO_E_IO instead of a bare 1 when the export fails" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "export", "jekyll", "-c", "no-such-dir", "-o", "exported"],
        chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_IO)
      err.should contain("HWARO_E_IO")
    end
  end
end

describe "hwaro tool convert (--dry-run)" do
  it "previews the conversion without touching any file" do
    with_initialized_project do |project_dir|
      before = Dir.glob(File.join(project_dir, "content", "**", "*.md")).sort.map { |f| {f, File.read(f)} }
      before.should_not be_empty

      status, output, _ = run_hwaro(["tool", "convert", "to-yaml", "--dry-run"], chdir: project_dir)
      status.success?.should be_true
      output.should contain("would convert")

      before.each do |(path, content)|
        File.read(path).should eq(content)
      end
    end
  end
end

describe "hwaro tool agents-md (site-specific preservation)" do
  it "preserves the Site-Specific Instructions section on regeneration" do
    with_initialized_project do |project_dir|
      agents_md = File.join(project_dir, "AGENTS.md")
      run_hwaro(["tool", "agents-md", "--write", "--force"], chdir: project_dir)

      File.write(agents_md, File.read(agents_md) + "\n- NEVER touch data/secret.yml\n")

      status, _, _ = run_hwaro(["tool", "agents-md", "--write", "--force"], chdir: project_dir)
      status.success?.should be_true
      File.read(agents_md).should contain("NEVER touch data/secret.yml")

      # Preservation survives a mode switch too.
      run_hwaro(["tool", "agents-md", "--remote", "--write", "--force"], chdir: project_dir)
      File.read(agents_md).should contain("NEVER touch data/secret.yml")
    end
  end
end

describe "hwaro tool review-fix regressions (2026-08 batch)" do
  it "refuses a missing explicit --templates-dir instead of scanning nothing" do
    with_initialized_project do |project_dir|
      status, _, err = run_hwaro(
        ["tool", "unused-assets", "--templates-dir", "no-such-templates"], chdir: project_dir
      )
      status.exit_code.should eq(Hwaro::Errors::EXIT_IO)
      err.should contain("HWARO_E_IO")
    end
  end

  it "matches --ignore-url patterns case-insensitively" do
    with_initialized_project do |project_dir|
      File.write(File.join(project_dir, "content", "broken.md"),
        "+++\ntitle = \"B\"\n+++\n\n[dead](/definitely-missing/)\n")

      status, _, _ = run_hwaro(
        ["tool", "check-links", "--internal-only", "--ignore-url", "DEFINITELY-MISSING"],
        chdir: project_dir
      )
      status.success?.should be_true
    end
  end

  it "reports ignored_count in the --json payload" do
    with_initialized_project do |project_dir|
      File.write(File.join(project_dir, "content", "broken.md"),
        "+++\ntitle = \"B\"\n+++\n\n[dead](/definitely-missing/)\n")

      _, output, _ = run_hwaro(
        ["tool", "check-links", "--internal-only", "--json", "--ignore-url", "definitely-missing"],
        chdir: project_dir
      )
      parsed = JSON.parse(output.strip)
      parsed["ignored_count"].as_i.should eq(1)
      parsed["dead_internal"].as_a.should be_empty
    end
  end

  it "warns and fully replaces an AGENTS.md without the Site-Specific heading" do
    with_initialized_project do |project_dir|
      agents_md = File.join(project_dir, "AGENTS.md")
      File.write(agents_md, "# Hand-written file\n\n- my custom rule\n")

      status, _, err = run_hwaro(["tool", "agents-md", "--write", "--force"], chdir: project_dir)
      status.success?.should be_true
      err.should contain("replacing the whole file")
      content = File.read(agents_md)
      content.should_not contain("my custom rule")
      content.should contain("## Site-Specific Instructions")
    end
  end
end
