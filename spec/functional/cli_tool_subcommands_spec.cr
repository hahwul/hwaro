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
# Note on streams: Hwaro::Logger.error / .info / .success all write to
# Logger.io which defaults to STDOUT — not STDERR. Tests therefore assert
# on the captured `output` stream, not `error`.
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

  it "exits 2 and prints a concise unknown-command error to stderr" do
    status, output, error = run_hwaro_no_chdir(["tool", "nonexistent-subcommand"])
    status.success?.should be_false
    status.exit_code.should eq(2)
    # Concise error goes to stderr, not stdout — the full help/banner
    # must NOT be dumped on a typo.
    error.should contain("unknown command 'tool nonexistent-subcommand'")
    error.should contain("hwaro tool --help")
    output.should_not contain("Available subcommands")
  end

  it "suggests the closest subcommand for near-miss typos" do
    status, _, error = run_hwaro_no_chdir(["tool", "stts"])
    status.exit_code.should eq(2)
    error.should contain("Did you mean 'stats'?")
  end

  it "omits the suggestion when no candidate is close" do
    status, _, error = run_hwaro_no_chdir(["tool", "xyzabc"])
    status.exit_code.should eq(2)
    error.should_not contain("Did you mean")
    error.should contain("hwaro tool --help")
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
end

describe "hwaro tool validate" do
  it "validates content of an initialized project" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "validate"], chdir: project_dir)
      # Default scaffold has no validation errors → exit 0
      status.success?.should be_true
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

  it "exits 1 and prints 'Unsupported platform' on an unknown platform" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(
        ["tool", "platform", "definitely-not-real"], chdir: project_dir
      )
      status.success?.should be_false
      output.should contain("Unsupported platform")
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
      _, output, _ = run_hwaro(
        ["tool", "ci", "github-actions", "--stdout"], chdir: project_dir
      )
      output.should contain("DEPRECATED")
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
  it "exits 1 and reports missing source-type" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "import"], chdir: project_dir)
      status.success?.should be_false
      output.should contain("Missing source")
    end
  end

  it "exits 1 and reports missing path when only source-type is given" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "import", "hugo"], chdir: project_dir)
      status.success?.should be_false
      output.should contain("Missing path")
    end
  end

  it "exits 1 and reports an unknown source-type" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(
        ["tool", "import", "definitely-not-real", "/tmp"], chdir: project_dir
      )
      status.success?.should be_false
      output.should contain("Unknown source type")
    end
  end
end

describe "hwaro tool export" do
  it "exits 1 and prints an error when no target-type is given" do
    with_initialized_project do |project_dir|
      status, output, _ = run_hwaro(["tool", "export"], chdir: project_dir)
      status.success?.should be_false
      output.size.should be > 0
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
