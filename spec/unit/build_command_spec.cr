require "../spec_helper"
require "../../src/cli/commands/build_command"

describe Hwaro::CLI::Commands::BuildCommand do
  describe "#parse_options" do
    it "returns default options" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, input_dir = cmd.parse_options([] of String)
      options, output_dir_explicit = result

      input_dir.should be_nil
      output_dir_explicit.should be_false
      options.output_dir.should eq("public")
      options.base_url.should be_nil
      options.drafts.should be_false
      options.minify.should be_false
      options.parallel.should be_true
      options.cache.should be_false
      options.highlight.should be_true
      options.verbose.should be_false
      options.profile.should be_false
      options.debug.should be_false
    end

    it "parses output directory" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, _ = cmd.parse_options(["--output-dir", "dist"])
      options, output_dir_explicit = result
      options.output_dir.should eq("dist")
      output_dir_explicit.should be_true

      result, _ = cmd.parse_options(["-o", "out"])
      options, output_dir_explicit = result
      options.output_dir.should eq("out")
      output_dir_explicit.should be_true
    end

    it "parses base url" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, _ = cmd.parse_options(["--base-url", "https://example.com"])
      options, _ = result
      options.base_url.should eq("https://example.com")
    end

    it "parses boolean flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, _ = cmd.parse_options([
        "--drafts",
        "--minify",
        "--cache",
        "--verbose",
        "--profile",
        "--debug",
      ])
      options, _ = result

      options.drafts.should be_true
      options.minify.should be_true
      options.cache.should be_true
      options.verbose.should be_true
      options.profile.should be_true
      options.debug.should be_true
    end

    it "parses short boolean flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, _ = cmd.parse_options(["-d", "-v"])
      options, _ = result

      options.drafts.should be_true
      options.verbose.should be_true
    end

    it "parses negative flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, _ = cmd.parse_options(["--no-parallel", "--skip-highlighting"])
      options, _ = result

      options.parallel.should be_false
      options.highlight.should be_false
    end

    it "parses mixed flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, _ = cmd.parse_options(["-o", "build", "--drafts", "--base-url", "http://localhost:3000"])
      options, output_dir_explicit = result

      options.output_dir.should eq("build")
      options.drafts.should be_true
      options.base_url.should eq("http://localhost:3000")
      output_dir_explicit.should be_true
    end

    it "parses input directory" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, input_dir = cmd.parse_options(["-i", "/tmp/my-site"])
      options, _ = result

      input_dir.should eq("/tmp/my-site")
      options.output_dir.should eq("public")
    end

    it "parses input directory with long flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, input_dir = cmd.parse_options(["--input", "/tmp/my-site"])
      _, _ = result

      input_dir.should eq("/tmp/my-site")
    end

    it "parses input and output together" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      result, input_dir = cmd.parse_options(["-i", "/tmp/my-site", "-o", "dist"])
      options, output_dir_explicit = result

      input_dir.should eq("/tmp/my-site")
      options.output_dir.should eq("dist")
      output_dir_explicit.should be_true
    end
  end
end
