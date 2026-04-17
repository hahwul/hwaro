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

private def with_initialized_project(&)
  temp_dir = File.tempname("hwaro_test")
  Dir.mkdir(temp_dir)
  project_dir = File.join(temp_dir, "test_site")
  Dir.mkdir(project_dir)
  begin
    Process.run(HWARO_BIN, ["init", project_dir],
      output: IO::Memory.new, error: IO::Memory.new)
    yield project_dir
  ensure
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end
end

private def run_hwaro(args : Array(String), chdir : String? = nil)
  output = IO::Memory.new
  error = IO::Memory.new
  status = if chdir
             Process.run(HWARO_BIN, args, chdir: chdir, output: output, error: error)
           else
             Process.run(HWARO_BIN, args, output: output, error: error)
           end
  {status, output.to_s, error.to_s}
end

describe "hwaro tool (router)" do
  it "exits 1 and prints help when no subcommand is given" do
    status, output, _ = run_hwaro(["tool"])
    status.success?.should be_false
    output.should contain("Usage")
    output.should contain("subcommand")
  end

  it "exits 1 and prints 'Unknown subcommand' for unrecognized names" do
    status, output, _ = run_hwaro(["tool", "nonexistent-subcommand"])
    status.success?.should be_false
    output.should contain("Unknown subcommand")
  end

  it "prints help and exits 0 when invoked with help" do
    status, output, _ = run_hwaro(["tool", "help"])
    status.success?.should be_true
    output.should contain("Available subcommands")
  end

  it "categorizes visible subcommands under Content / Site headings" do
    status, output, _ = run_hwaro(["tool", "--help"])
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
  it "runs against an initialized project without crashing" do
    with_initialized_project do |project_dir|
      status, _, _ = run_hwaro(["tool", "check-links"], chdir: project_dir)
      # check-links may exit non-zero if the scaffold has broken links;
      # we only verify it terminates with a defined exit code.
      status.exit_code.should_not be_nil
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
    end
  end
end

describe "hwaro tool agents-md" do
  it "prints local-mode AGENTS.md content to stdout by default" do
    with_initialized_project do |project_dir|
      # `init` writes AGENTS.md by default — remove it to verify the no-write
      # path of `tool agents-md` doesn't touch the file.
      File.delete(File.join(project_dir, "AGENTS.md"))

      status, output, _ = run_hwaro(["tool", "agents-md"], chdir: project_dir)
      status.success?.should be_true
      output.should contain("AGENTS.md")
      File.exists?(File.join(project_dir, "AGENTS.md")).should be_false
    end
  end

  it "writes AGENTS.md when --write is passed" do
    with_initialized_project do |project_dir|
      File.delete(File.join(project_dir, "AGENTS.md"))

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
