require "../spec_helper"
require "../../src/cli/commands/init_wizard"

private def with_wizard_input(data : String, &)
  previous = Hwaro::CLI::Prompt.input
  Hwaro::CLI::Prompt.input = IO::Memory.new(data)
  begin
    yield
  ensure
    Hwaro::CLI::Prompt.input = previous
  end
end

# Run the wizard with a scripted answer stream. The wizard only collects
# input — it never touches the filesystem — so no temp project is needed.
private def run_init_wizard(answers : String, seed_path : String? = nil) : Hwaro::Config::Options::InitOptions?
  result = nil
  with_captured_log do
    with_wizard_input(answers) do
      result = Hwaro::CLI::Commands::InitWizard.new.run(seed_path)
    end
  end
  result
end

describe Hwaro::CLI::Commands::InitWizard do
  it "collects directory, scaffold, and title, and confirms" do
    # directory, scaffold(2 = blog), title, dark(n), confirm(accept default y)
    options = run_init_wizard("my-site\n2\nMy Blog\nn\n\n")
    options.should_not be_nil
    options = options.not_nil!

    options.path.should eq("my-site")
    options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    options.site_title.should eq("My Blog")
    options.from_wizard.should be_true
  end

  it "defaults to the simple scaffold in the current directory on bare Enters" do
    # directory(accept .), scaffold(skip = simple), title(accept default), confirm
    options = run_init_wizard("\n\n\n\n")
    options.should_not be_nil
    options = options.not_nil!

    options.path.should eq(".")
    options.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    options.site_title.should eq("My Hwaro Site")
  end

  it "maps the dark toggle onto the matching *-dark scaffold" do
    # directory, scaffold(3 = docs), title(accept), dark(y), confirm
    options = run_init_wizard("site\n3\n\ny\n\n")
    options.should_not be_nil
    options.not_nil!.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::DocsDark)
  end

  it "does not ask about dark for scaffolds without a dark variant" do
    # directory, scaffold(1 = simple), title, confirm — no dark answer needed
    options = run_init_wizard("site\n1\nTitle\n\n")
    options.should_not be_nil
    options.not_nil!.scaffold.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
  end

  it "skips the directory prompt when a path positional is given" do
    log = with_captured_log do
      with_wizard_input("\n\n\n") do
        Hwaro::CLI::Commands::InitWizard.new.run("seeded-site")
      end
    end

    log.should_not contain "Directory"
    log.should contain "seeded-site"

    options = run_init_wizard("\n\n\n", seed_path: "seeded-site")
    options.should_not be_nil
    options.not_nil!.path.should eq("seeded-site")
  end

  it "returns nil when the confirmation is declined" do
    run_init_wizard("site\n1\nTitle\nn\n").should be_nil
  end

  it "returns nil on EOF (Ctrl-D) mid-flow" do
    run_init_wizard("site\n").should be_nil
  end
end
