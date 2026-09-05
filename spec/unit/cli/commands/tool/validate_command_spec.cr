require "../../../../spec_helper"

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

        output.should contain("hwaro: validate")
        output.should contain("no issues found")
      end
    end

    it "raises a classified usage error for a non-numeric --max-warnings" do
      err = expect_raises(Hwaro::HwaroError) do
        Hwaro::CLI::Commands::Tool::ValidateCommand.new.run(["--max-warnings", "abc"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
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
        output.should match(/checked: \d+ errors?, \d+ warnings?, \d+ info/)
      end
    end
  end
end

# Service-level regressions for ContentValidator error classification and
# the tag plumbing (previously smuggled through the frontmatter hash under
# a fake "_tags" key).
describe Hwaro::Services::ContentValidator do
  it "distinguishes an unprocessable (invalid encoding) file from a read failure" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.md")
      File.open(path, "w") do |f|
        f << "---\ntitle: ok\n---\n\nbody "
        f.write(Bytes[0xff, 0xfe, 0xfa])
      end

      issues = Hwaro::Services::ContentValidator.new(content_dir: dir).run
      issue = issues.find { |i| i.id == "content-read-error" }
      issue.should_not be_nil
      # A perfectly readable file must not be blamed on I/O: that message
      # pointed authors at permissions/disk when the problem is encoding.
      issue.not_nil!.message.should_not contain("Failed to read file")
    end
  end

  it "does not misreport a real front matter key named _tags as tags" do
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "post.md"),
        "+++\ntitle = \"T\"\ndescription = \"D\"\n_tags = \"FooBar\"\n+++\n\nBody text.\n"
      )

      issues = Hwaro::Services::ContentValidator.new(content_dir: dir).run
      issues.any? { |i| i.id == "content-tag-mixed-case" }.should be_false
    end
  end

  it "keeps a tag containing a comma intact for the mixed-case check" do
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "post.md"),
        "+++\ntitle = \"T\"\ndescription = \"D\"\ntags = [\"Foo,Bar\"]\n+++\n\nBody text.\n"
      )

      issues = Hwaro::Services::ContentValidator.new(content_dir: dir).run
      mixed = issues.select { |i| i.id == "content-tag-mixed-case" }
      mixed.size.should eq(1)
      mixed.first.message.should contain(%("Foo,Bar"))
    end
  end

  it "still warns on ordinary mixed-case tags" do
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "post.md"),
        "+++\ntitle = \"T\"\ndescription = \"D\"\ntags = [\"FooBar\", \"fine\"]\n+++\n\nBody text.\n"
      )

      issues = Hwaro::Services::ContentValidator.new(content_dir: dir).run
      mixed = issues.select { |i| i.id == "content-tag-mixed-case" }
      mixed.size.should eq(1)
      mixed.first.message.should contain(%("FooBar"))
    end
  end
end
