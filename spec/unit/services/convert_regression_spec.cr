require "../../spec_helper"

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

        # Root (and Windows) ignore the read-only bit, so the precondition
        # this example needs cannot be built there. Report that explicitly as
        # pending — wrapping the assertions in a silent `unless writable?`
        # left the example reporting green while asserting nothing.
        pending! "cannot create an unwritable file here (running as root?)" if File::Info.writable?(path)

        result = Hwaro::Services::FrontmatterConverter.new(content_dir).convert_to_yaml

        result.success.should be_false
        result.error_count.should eq(1)
        result.message.should contain("could not be converted")

        File.chmod(path, 0o644)
      end
    end
  end

  # Stability audit 2026-08-23. `write_in_place` renamed the temp file over
  # the given path, so converting a symlinked content file destroyed the
  # symlink and left the real target unconverted.
  describe "symlinked content files" do
    it "converts the symlink's target and keeps the symlink" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        target = File.join(dir, "real.md")
        File.write(target, "+++\ntitle = \"Linked\"\n+++\n\nBody.\n")
        link = File.join(content_dir, "linked.md")
        File.symlink(target, link)

        result = Hwaro::Services::FrontmatterConverter.new(content_dir).convert_to_yaml
        result.converted_count.should eq(1)

        File.symlink?(link).should be_true
        File.read(target).should start_with("---\ntitle: Linked\n---\n")
      end
    end
  end

  # Stability audit 2026-08-23. An empty source mapping serialized through
  # `to_yaml` as `--- {}`, which ended up embedded inside the new fences.
  describe "empty frontmatter blocks" do
    it "converts empty JSON frontmatter to an empty YAML block" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        path = File.join(dir, "post.md")
        File.write(path, "{}\n\nBody.\n")

        converter.convert_file(path, Hwaro::Services::FrontmatterFormat::YAML).should be_true

        content = File.read(path)
        content.should start_with("---\n---\n")
        content.should_not contain("--- {}")
      end
    end

    it "converts empty TOML frontmatter to an empty YAML block" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        path = File.join(dir, "post.md")
        File.write(path, "+++\n+++\n\nBody.\n")

        converter.convert_file(path, Hwaro::Services::FrontmatterFormat::YAML).should be_true

        content = File.read(path)
        content.should eq("---\n---\n\nBody.\n")
      end
    end

    # `YAML.parse("")` is nil, so `---\n---\n` was misclassified as "not
    # front matter" and skipped instead of converting to `+++\n+++`.
    it "converts an empty YAML frontmatter block to TOML" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        path = File.join(dir, "post.md")
        File.write(path, "---\n---\n\nBody.\n")

        converter.convert_file(path, Hwaro::Services::FrontmatterFormat::TOML).should be_true

        File.read(path).should eq("+++\n+++\n\nBody.\n")
      end
    end
  end

  # Stability audit 2026-08-23. `detect_format` required the opener to be
  # exactly `---\n`, while the build parser accepts trailing whitespace —
  # `--- \n` files were skipped as "no frontmatter".
  describe "delimiter trailing whitespace" do
    it "detects frontmatter whose opening delimiter has trailing whitespace" do
      converter = Hwaro::Services::FrontmatterConverter.new(".")
      converter.detect_format("--- \ntitle: x\n---\n").should eq(Hwaro::Services::FrontmatterFormat::YAML)
      converter.detect_format("+++\t\ntitle = \"x\"\n+++\n").should eq(Hwaro::Services::FrontmatterFormat::TOML)
      converter.detect_format("--- \r\ntitle: x\n---\n").should eq(Hwaro::Services::FrontmatterFormat::YAML)
    end

    it "converts a file whose opening delimiter has a trailing space" do
      Dir.mktmpdir do |dir|
        converter = Hwaro::Services::FrontmatterConverter.new(dir)
        path = File.join(dir, "post.md")
        File.write(path, "--- \ntitle: X\n---\n\nBody.\n")

        converter.convert_file(path, Hwaro::Services::FrontmatterFormat::TOML).should be_true

        content = File.read(path)
        content.should start_with("+++\n")
        content.should contain(%(title = "X"))
      end
    end
  end
end
