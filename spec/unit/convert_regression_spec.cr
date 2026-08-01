require "../spec_helper"

# Regression specs for defects found by dogfooding `hwaro tool convert`.
# Numbering matches the audit report.
describe "convert regressions" do
  # (6) `hwaro tool convert` in a directory with no `content/` exited 1 with
  # no diagnostic at all in human mode — the reason was produced and then
  # thrown away, reachable only via `--json`. Every sibling `tool` command
  # raises a coded, hinted error for the same class of failure.
  describe "missing content directory" do
    it "reports the missing directory in the result message" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(File.join(dir, "missingdir"))
        result = converter.convert_to_toml

        result.success.should be_false
        result.message.should contain("missingdir")
        result.message.should contain("not found")
      end
    end

    it "raises an actionable HwaroError from the command instead of exiting silently" do
      Dir.mktmpdir do |dir|
        error = expect_raises(Hwaro::HwaroError) do
          Hwaro::CLI::Commands::Tool::ConvertCommand.new.run(
            ["to-toml", "--content-dir", File.join(dir, "missingdir")]
          )
        end

        error.code.should eq(Hwaro::Errors::HWARO_E_IO)
        (error.message || "").should contain("not found")
        error.hint.should_not be_nil
      end
    end

    it "describes the failure rather than a partial success when files error" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        # Read-only file: `write_in_place` refuses to replace it, so the
        # conversion fails and the summary must say so.
        path = File.join(content_dir, "ro.md")
        File.write(path, "+++\ntitle = \"RO\"\n+++\n\nBody.\n")
        File.chmod(path, 0o444)

        # Running as root defeats the permission bit, so only assert when the
        # file is genuinely unwritable.
        unless File::Info.writable?(path)
          result = Hwaro::Services::FrontmatterConverter.new(content_dir).convert_to_yaml

          result.success.should be_false
          result.error_count.should eq(1)
          result.message.should contain("could not be converted")
        end

        File.chmod(path, 0o644)
      end
    end
  end
end
