require "../spec_helper"

# Command-level tests for `hwaro tool validate`.
#
# The ContentValidator service is exercised in spec/unit/content_validator_spec.cr;
# these tests cover the command wrapper's metadata and its rendering of the
# "no issues" and "issues grouped by file with a summary" paths.
describe Hwaro::CLI::Commands::Tool::ValidateCommand do
  describe ".metadata" do
    it "reports the command name and description" do
      meta = Hwaro::CLI::Commands::Tool::ValidateCommand.metadata
      meta.name.should eq("validate")
      meta.description.should_not be_empty
    end

    it "exposes the content-dir and json flags" do
      meta = Hwaro::CLI::Commands::Tool::ValidateCommand.metadata
      meta.flags.any? { |f| f.long == "--content-dir" }.should be_true
      meta.flags.any? { |f| f.long == "--json" }.should be_true
    end
  end

  describe "#run" do
    it "reports a clean result for well-formed content" do
      Dir.mktmpdir do |dir|
        File.write(
          File.join(dir, "good.md"),
          "---\ntitle: A Good Post\ndescription: A perfectly fine description for SEO purposes.\ndate: 2024-01-10\n---\n\n# A Good Post\n\nThis post has a healthy amount of body text so the validator is satisfied that it is a real article and not an empty stub document.\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::ValidateCommand.new
          cmd.run(["-c", dir])
        end

        output.should contain("Validating content")
        output.should contain("No issues found")
      end
    end

    it "groups issues by file and prints a summary when problems exist" do
      Dir.mktmpdir do |dir|
        # Missing title triggers a validation issue.
        File.write(
          File.join(dir, "bad.md"),
          "---\ndescription: no title here\n---\n\nShort.\n"
        )

        output = with_captured_log do
          cmd = Hwaro::CLI::Commands::Tool::ValidateCommand.new
          cmd.run(["-c", dir])
        end

        # The offending file is listed and a count summary is printed. We assert
        # on the summary line shape rather than a specific severity so the test
        # does not break if the validator reclassifies this issue.
        output.should contain("bad.md")
        output.should match(/Found \d+ error\(s\), \d+ warning\(s\), \d+ info\(s\)/)
      end
    end
  end
end
