require "../spec_helper"

# `--quiet` silences status chatter, never the answer: commands whose job is
# to print data (listings, reports, help) keep that output, like
# `hwaro version -q` (#899). Usage failures keep stdout empty.

private HWARO_BIN = hwaro_binary

Spec.before_suite do
  unless File.exists?(HWARO_BIN) && File::Info.executable?(HWARO_BIN)
    raise "Binary #{HWARO_BIN} is missing or not executable. Run `shards build` first."
  end
end

private def with_site(&)
  temp_dir = File.tempname("hwaro_quiet")
  Dir.mkdir(temp_dir)
  dir = File.join(temp_dir, "site")
  begin
    Process.run(HWARO_BIN, ["init", dir, "--scaffold", "blog"], output: IO::Memory.new, error: IO::Memory.new).success?.should be_true
    File.write(File.join(dir, "static", "orphan-asset.png"), "x")
    yield dir
  ensure
    FileUtils.rm_rf(temp_dir)
  end
end

private def run(args : Array(String), chdir : String? = nil)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run(HWARO_BIN, args, chdir: chdir, output: output, error: error)
  {status.exit_code, output.to_s, error.to_s}
end

describe "hwaro --quiet keeps a command's result" do
  it "tool list prints the table without the heading" do
    with_site do |dir|
      code, out, _ = run(["tool", "list", "all", "-q"], dir)
      code.should eq(0)
      out.should contain("Path")
      out.should_not contain("hwaro: list")
    end
  end

  it "tool stats prints the report" do
    with_site do |dir|
      code, out, _ = run(["tool", "stats", "-q"], dir)
      code.should eq(0)
      out.should contain("total")
    end
  end

  it "tool unused-assets prints the unused files" do
    with_site do |dir|
      code, out, _ = run(["tool", "unused-assets", "-q"], dir)
      code.should eq(0)
      out.should contain("orphan-asset.png")
    end
  end

  it "init --list-scaffolds, new --list-archetypes and deploy --list-targets keep their listing" do
    with_site do |dir|
      run(["init", "--list-scaffolds", "-q"], dir)[1].should contain("blog")
      run(["new", "--list-archetypes", "-q"], dir)[1].should_not be_empty
      run(["deploy", "--list-targets", "-q"], dir)[1].should_not be_empty
    end
  end

  it "--help still prints the help text" do
    with_site do |dir|
      [["--help"], ["build", "--help"], ["tool", "list", "--help"], ["tool", "platform", "--help"],
       ["tool", "--help"], ["completion", "--help"], ["help", "build"], ["init", "--help"]].each do |argv|
        code, out, _ = run(argv + ["-q"], dir)
        code.should eq(0)
        out.should contain("Usage")
      end
    end
  end

  it "tool subcommand help lists -q" do
    with_site do |dir|
      ["list", "convert", "check-links", "stats", "validate", "unused-assets", "platform", "import", "export", "agents-md"].each do |sub|
        run(["tool", sub, "--help"], dir)[1].should contain("--quiet")
      end
    end
  end
end

describe "usage failures keep stdout empty" do
  it "prints the usage text on stderr for `tool`, `completion` and an unknown scaffold" do
    with_site do |dir|
      [["tool"], ["completion"], ["init", "x", "--scaffold", "nope"]].each do |argv|
        code, out, err = run(argv, dir)
        code.should eq(Hwaro::Errors::EXIT_USAGE)
        out.should be_empty
        err.should contain("HWARO_E_USAGE")
      end
    end
  end

  it "gives an unknown flag a hint naming the right --help" do
    code, stdout, _ = run(["tool", "platform", "netlify", "--json"])
    code.should eq(Hwaro::Errors::EXIT_USAGE)
    JSON.parse(stdout)["error"]["hint"].as_s.should contain("hwaro tool platform --help")
    _, _, err = run(["tool", "platform", "netlify", "--bogus"])
    err.should contain("hwaro tool platform --help")
  end

  it "rejects extra positionals for completion" do
    code, out, err = run(["completion", "bash", "zsh"])
    code.should eq(Hwaro::Errors::EXIT_USAGE)
    out.should be_empty
    err.should contain("unexpected extra argument")
  end
end
