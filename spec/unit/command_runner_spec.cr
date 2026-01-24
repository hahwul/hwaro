require "../spec_helper"

describe Hwaro::Utils::CommandRunner do
  describe Hwaro::Utils::CommandRunner::Result do
    it "can be created with success" do
      result = Hwaro::Utils::CommandRunner::Result.new(
        success: true,
        output: "output text",
        error: "",
        exit_code: 0
      )

      result.success.should be_true
      result.output.should eq("output text")
      result.error.should eq("")
      result.exit_code.should eq(0)
    end

    it "can be created with failure" do
      result = Hwaro::Utils::CommandRunner::Result.new(
        success: false,
        output: "",
        error: "error message",
        exit_code: 1
      )

      result.success.should be_false
      result.output.should eq("")
      result.error.should eq("error message")
      result.exit_code.should eq(1)
    end
  end

  describe ".run" do
    it "executes a successful command" do
      result = Hwaro::Utils::CommandRunner.run("echo 'hello'")
      result.success.should be_true
      result.output.strip.should eq("hello")
      result.exit_code.should eq(0)
    end

    it "captures stdout" do
      result = Hwaro::Utils::CommandRunner.run("echo 'test output'")
      result.output.should contain("test output")
    end

    it "captures stderr" do
      result = Hwaro::Utils::CommandRunner.run("echo 'error' >&2")
      result.error.should contain("error")
    end

    it "returns failure for invalid command" do
      result = Hwaro::Utils::CommandRunner.run("nonexistent_command_12345")
      result.success.should be_false
      result.exit_code.should_not eq(0)
    end

    it "returns correct exit code" do
      result = Hwaro::Utils::CommandRunner.run("exit 42")
      result.success.should be_false
      result.exit_code.should eq(42)
    end

    it "respects working directory" do
      Dir.mktmpdir do |dir|
        # Create a test file in the temp directory
        test_file = File.join(dir, "test.txt")
        File.write(test_file, "content")

        result = Hwaro::Utils::CommandRunner.run("ls test.txt", dir)
        result.success.should be_true
        result.output.should contain("test.txt")
      end
    end

    it "handles commands with special characters" do
      result = Hwaro::Utils::CommandRunner.run("echo 'hello world'")
      result.success.should be_true
      result.output.strip.should eq("hello world")
    end

    it "handles multiline output" do
      result = Hwaro::Utils::CommandRunner.run("echo 'line1'; echo 'line2'")
      result.success.should be_true
      result.output.should contain("line1")
      result.output.should contain("line2")
    end
  end

  describe ".run_all" do
    it "returns true for empty commands array" do
      result = Hwaro::Utils::CommandRunner.run_all([] of String)
      result.should be_true
    end

    it "executes all commands sequentially" do
      Dir.mktmpdir do |dir|
        commands = [
          "touch file1.txt",
          "touch file2.txt",
          "touch file3.txt",
        ]

        result = Hwaro::Utils::CommandRunner.run_all(commands, dir)
        result.should be_true

        File.exists?(File.join(dir, "file1.txt")).should be_true
        File.exists?(File.join(dir, "file2.txt")).should be_true
        File.exists?(File.join(dir, "file3.txt")).should be_true
      end
    end

    it "stops on first failure" do
      Dir.mktmpdir do |dir|
        commands = [
          "touch file1.txt",
          "exit 1",
          "touch file2.txt",
        ]

        result = Hwaro::Utils::CommandRunner.run_all(commands, dir)
        result.should be_false

        # First file should exist
        File.exists?(File.join(dir, "file1.txt")).should be_true
        # Third file should not exist (stopped after failure)
        File.exists?(File.join(dir, "file2.txt")).should be_false
      end
    end

    it "returns true when all commands succeed" do
      commands = [
        "echo 'first'",
        "echo 'second'",
        "echo 'third'",
      ]

      result = Hwaro::Utils::CommandRunner.run_all(commands)
      result.should be_true
    end
  end

  describe ".run_pre_hooks" do
    it "returns true for empty hooks" do
      result = Hwaro::Utils::CommandRunner.run_pre_hooks([] of String)
      result.should be_true
    end

    it "executes pre-build hooks" do
      Dir.mktmpdir do |dir|
        commands = ["touch pre_hook_file.txt"]
        result = Hwaro::Utils::CommandRunner.run_pre_hooks(commands, dir)
        result.should be_true
        File.exists?(File.join(dir, "pre_hook_file.txt")).should be_true
      end
    end

    it "returns false on hook failure" do
      commands = ["exit 1"]
      result = Hwaro::Utils::CommandRunner.run_pre_hooks(commands)
      result.should be_false
    end
  end

  describe ".run_post_hooks" do
    it "returns true for empty hooks" do
      result = Hwaro::Utils::CommandRunner.run_post_hooks([] of String)
      result.should be_true
    end

    it "executes post-build hooks" do
      Dir.mktmpdir do |dir|
        commands = ["touch post_hook_file.txt"]
        result = Hwaro::Utils::CommandRunner.run_post_hooks(commands, dir)
        result.should be_true
        File.exists?(File.join(dir, "post_hook_file.txt")).should be_true
      end
    end

    it "returns false on hook failure" do
      commands = ["exit 1"]
      result = Hwaro::Utils::CommandRunner.run_post_hooks(commands)
      result.should be_false
    end
  end
end
