require "../spec_helper"
require "../../src/cli/commands/new_wizard"

private def with_prompt_input(data : String, &)
  previous = Hwaro::CLI::Prompt.input
  Hwaro::CLI::Prompt.input = IO::Memory.new(data)
  begin
    yield
  ensure
    Hwaro::CLI::Prompt.input = previous
  end
end

# Run the wizard inside a throwaway project dir with a scripted answer stream.
private def run_wizard(answers : String, options : Hwaro::Config::Options::NewOptions, archetypes = [] of Hwaro::CLI::Commands::NewWizard::Archetype) : Bool
  result = false
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      FileUtils.mkdir_p("content")
      with_prompt_input(answers) do
        result = Hwaro::CLI::Commands::NewWizard.new.run(options, archetypes)
      end
    end
  end
  result
end

describe Hwaro::CLI::Commands::NewWizard do
  it "collects fields and accepts the recommended path" do
    options = Hwaro::Config::Options::NewOptions.new
    # title, description, section, path(accept), tags, date(accept), draft, confirm(accept)
    run_wizard("My First Post\nA short intro\nposts\n\ncrystal, howto\n\nn\n\n", options).should be_true

    options.title.should eq("My First Post")
    options.description.should eq("A short intro")
    options.path.should eq("posts/my-first-post.md")
    options.tags.should eq(["crystal", "howto"])
    options.draft.should be_false
    options.date.should be_nil    # today's default accepted → left unset
    options.section.should be_nil # baked into the path, not duplicated
  end

  it "honours a custom path, explicit date, and draft" do
    options = Hwaro::Config::Options::NewOptions.new
    # title, description(skip), section(skip), path(custom), tags(skip), date, draft(y), confirm(accept)
    run_wizard("Custom\n\n\nguides/custom-guide.md\n\n2024-01-02\ny\n\n", options).should be_true

    options.path.should eq("guides/custom-guide.md")
    options.description.should be_nil
    options.section.should be_nil
    options.tags.empty?.should be_true
    options.date.should eq("2024-01-02")
    options.draft.should be_true
  end

  it "uses an existing --title flag as the title default" do
    options = Hwaro::Config::Options::NewOptions.new(title: "Seeded Title")
    # title(accept seed), description, section(skip), path(accept), tags(skip), date(accept), draft(n), confirm(accept)
    run_wizard("\nDesc\n\n\n\n\nn\n\n", options).should be_true

    options.title.should eq("Seeded Title")
    options.path.should eq("seeded-title.md")
  end

  it "lets the author pick an archetype from the detected list" do
    options = Hwaro::Config::Options::NewOptions.new
    archetypes = [
      {name: "post", path: "archetypes/post.md"},
      {name: "page", path: "archetypes/page.md"},
    ]
    # title, desc(skip), section(skip), path(accept), tags(skip), date(accept), draft(n), archetype(2), confirm(accept)
    run_wizard("Arch\n\n\n\n\n\nn\n2\n\n", options, archetypes).should be_true

    options.archetype.should eq("page")
    options.path.should eq("arch.md")
  end

  it "returns false and leaves options unmutated when the confirmation is declined" do
    options = Hwaro::Config::Options::NewOptions.new
    # everything answered, but final confirm is "n"
    run_wizard("X\n\n\n\n\n\nn\nn\n", options).should be_false
    options.path.should be_nil
  end

  it "returns false when cancelled with EOF on the required title" do
    options = Hwaro::Config::Options::NewOptions.new
    run_wizard("", options).should be_false
    options.path.should be_nil
  end
end
