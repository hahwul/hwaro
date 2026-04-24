require "../spec_helper"

# =============================================================================
# CLI tool command registration and execution functional tests
#
# Verifies that tool subcommands (check-links, doctor, convert, list),
# new, and completion commands are properly registered and functional.
# =============================================================================

describe "CLI Tool Commands" do
  describe Hwaro::CLI::CommandRegistry do
    Hwaro::CLI::Runner.new

    it "has tool command registered" do
      Hwaro::CLI::CommandRegistry.has?("tool").should be_true
    end

    it "has new command registered" do
      Hwaro::CLI::CommandRegistry.has?("new").should be_true
    end

    it "has completion command registered" do
      Hwaro::CLI::CommandRegistry.has?("completion").should be_true
    end
  end

  describe "hwaro new" do
    it "creates a new content file" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        # Initialize project first
        init_output = IO::Memory.new
        init_error = IO::Memory.new
        Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: init_output, error: init_error)

        # Create new content
        new_output = IO::Memory.new
        new_error = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["new", "blog/my-first-post.md"], chdir: project_dir, output: new_output, error: new_error)

        status.success?.should be_true

        content_file = File.join(project_dir, "content", "blog", "my-first-post.md")
        File.exists?(content_file).should be_true

        content = File.read(content_file)
        content.should contain("title")
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end

  describe "hwaro completion" do
    it "generates bash completion" do
      output_io = IO::Memory.new
      error_io = IO::Memory.new
      status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["completion", "bash"], output: output_io, error: error_io)

      status.success?.should be_true
      output = output_io.to_s
      output.should contain("hwaro")
    end

    it "generates zsh completion" do
      output_io = IO::Memory.new
      error_io = IO::Memory.new
      status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["completion", "zsh"], output: output_io, error: error_io)

      status.success?.should be_true
      output = output_io.to_s
      output.should contain("hwaro")
    end

    it "generates fish completion" do
      output_io = IO::Memory.new
      error_io = IO::Memory.new
      status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["completion", "fish"], output: output_io, error: error_io)

      status.success?.should be_true
      output = output_io.to_s
      output.should contain("hwaro")
    end
  end

  describe "hwaro help" do
    it "delegates `help <command>` to the command's --help output" do
      output_io = IO::Memory.new
      error_io = IO::Memory.new
      status = Process.run(
        File.expand_path("../../bin/hwaro", __DIR__),
        ["help", "build"],
        output: output_io, error: error_io)

      status.success?.should be_true
      output = output_io.to_s + error_io.to_s
      # `build --help` prints its OptionParser banner which starts with "Usage: hwaro build".
      output.should contain("Usage: hwaro build")
      # And should not be the generic top-level help (which lists other commands).
      output.should_not contain("Available commands")
    end

    it "falls back to generic help when no command is given" do
      output_io = IO::Memory.new
      error_io = IO::Memory.new
      status = Process.run(
        File.expand_path("../../bin/hwaro", __DIR__),
        ["help"],
        output: output_io, error: error_io)

      status.success?.should be_true
      (output_io.to_s + error_io.to_s).should contain("Commands:")
    end

    it "reports an unknown command with a non-zero exit" do
      output_io = IO::Memory.new
      error_io = IO::Memory.new
      status = Process.run(
        File.expand_path("../../bin/hwaro", __DIR__),
        ["help", "nosuchcommand"],
        output: output_io, error: error_io)

      status.success?.should be_false
      error_io.to_s.should contain("unknown command")
    end
  end

  describe "hwaro doctor (top-level)" do
    it "runs diagnostics on a valid project" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: IO::Memory.new, error: IO::Memory.new)

        output_io = IO::Memory.new
        error_io = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["doctor"], chdir: project_dir, output: output_io, error: error_io)

        status.success?.should be_true
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end

  describe "hwaro tool doctor (alias)" do
    it "still works via tool subcommand" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: IO::Memory.new, error: IO::Memory.new)

        output_io = IO::Memory.new
        error_io = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["tool", "doctor"], chdir: project_dir, output: output_io, error: error_io)

        status.success?.should be_true
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end

  describe "hwaro tool list" do
    it "lists content files in a project" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        # Initialize project
        Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: IO::Memory.new, error: IO::Memory.new)

        output_io = IO::Memory.new
        error_io = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["tool", "list", "all"], chdir: project_dir, output: output_io, error: error_io)

        status.success?.should be_true
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end

  describe "hwaro tool convert" do
    it "converts YAML frontmatter to TOML" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        # Initialize project
        Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: IO::Memory.new, error: IO::Memory.new)

        # Create a YAML frontmatter file
        content_dir = File.join(project_dir, "content")
        File.write(File.join(content_dir, "test.md"), "---\ntitle: Test Page\ndraft: false\n---\nContent here")

        output_io = IO::Memory.new
        error_io = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["tool", "convert", "to-toml"], chdir: project_dir, output: output_io, error: error_io)

        status.success?.should be_true

        converted = File.read(File.join(content_dir, "test.md"))
        converted.should contain("+++")
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end
end
