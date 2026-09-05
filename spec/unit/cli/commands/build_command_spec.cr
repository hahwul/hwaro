require "../../../spec_helper"
require "../../../../src/cli/commands/build_command"

describe Hwaro::CLI::Commands::BuildCommand do
  describe "#parse_options" do
    it "returns default options" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, input_dir = cmd.parse_options([] of String)

      input_dir.should be_nil
      options.output_dir_explicit.should be_false
      options.output_dir.should eq("public")
      options.base_url.should be_nil
      options.drafts.should be_false
      options.minify.should be_false
      options.parallel.should be_true
      options.workers.should eq(0)
      options.cache.should be_false
      options.highlight.should be_true
      options.verbose.should be_false
      options.profile.should be_false
      options.debug.should be_false
      options.stream.should be_false
      options.memory_limit.should be_nil
    end

    it "parses output directory" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--output", "dist"])
      options.output_dir.should eq("dist")
      options.output_dir_explicit.should be_true

      options, _ = cmd.parse_options(["-o", "out"])
      options.output_dir.should eq("out")
      options.output_dir_explicit.should be_true
    end

    it "parses base url" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--base-url", "https://example.com"])
      options.base_url.should eq("https://example.com")
    end

    it "rejects an invalid --base-url with HWARO_E_USAGE" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      err = expect_raises(Hwaro::HwaroError) do
        cmd.parse_options(["--base-url", "not a valid url"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
    end

    it "rejects a --base-url without a scheme" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      err = expect_raises(Hwaro::HwaroError) do
        cmd.parse_options(["--base-url", "example.com"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    end

    it "parses boolean flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options([
        "--drafts",
        "--minify",
        "--cache",
        "--verbose",
        "--profile",
        "--debug",
      ])

      options.drafts.should be_true
      options.minify.should be_true
      options.cache.should be_true
      options.verbose.should be_true
      options.profile.should be_true
      options.debug.should be_true
    end

    it "parses short boolean flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["-d", "-v"])

      options.drafts.should be_true
      options.verbose.should be_true
    end

    it "parses negative flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--no-parallel", "--skip-highlighting"])

      options.parallel.should be_false
      options.highlight.should be_false
    end

    it "parses --jobs into the worker count" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--jobs", "2"])
      options.workers.should eq(2)
    end

    it "warns that --jobs is ignored when combined with --no-parallel" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      log = with_captured_log do
        options, _ = cmd.parse_options(["--no-parallel", "--jobs", "4"])
        options.parallel.should be_false
        options.workers.should eq(4)
      end
      log.should contain("--jobs")
      log.should contain("--no-parallel")
    end

    it "does not warn about --jobs when parallel rendering is enabled" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      log = with_captured_log do
        cmd.parse_options(["--jobs", "4"])
      end
      log.should_not contain("--no-parallel")
    end

    it "raises HwaroError(HWARO_E_USAGE) when --jobs is not a positive integer" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new

      ["0", "-1", "abc", ""].each do |bad|
        err = expect_raises(Hwaro::HwaroError) do
          cmd.parse_options(["--jobs", bad])
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      end
    end

    it "defaults skip_og_image to false" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options([] of String)
      options.skip_og_image.should be_false
    end

    it "parses --skip-og-image flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--skip-og-image"])
      options.skip_og_image.should be_true
    end

    it "defaults skip_image_processing to false" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options([] of String)
      options.skip_image_processing.should be_false
    end

    it "parses --skip-image-processing flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--skip-image-processing"])
      options.skip_image_processing.should be_true
    end

    it "parses mixed flags" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["-o", "build", "--drafts", "--base-url", "http://localhost:3000"])

      options.output_dir.should eq("build")
      options.drafts.should be_true
      options.base_url.should eq("http://localhost:3000")
      options.output_dir_explicit.should be_true
    end

    it "parses input directory" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, input_dir = cmd.parse_options(["-i", "/tmp/my-site"])

      input_dir.should eq("/tmp/my-site")
      options.output_dir.should eq("public")
    end

    it "parses input directory with long flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      _, input_dir = cmd.parse_options(["--input", "/tmp/my-site"])

      input_dir.should eq("/tmp/my-site")
    end

    it "parses input and output together" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, input_dir = cmd.parse_options(["-i", "/tmp/my-site", "-o", "dist"])

      input_dir.should eq("/tmp/my-site")
      options.output_dir.should eq("dist")
      options.output_dir_explicit.should be_true
    end

    it "parses --stream flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--stream"])

      options.stream.should be_true
      options.streaming?.should be_true
    end

    it "parses --memory-limit flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--memory-limit", "512M"])

      options.memory_limit.should eq("512M")
      options.streaming?.should be_true
    end

    it "parses --stream with --memory-limit" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      options, _ = cmd.parse_options(["--stream", "--memory-limit", "2G"])

      options.stream.should be_true
      options.memory_limit.should eq("2G")
      options.streaming?.should be_true
    end

    it "uses HWARO_MEMORYLIMIT env var as fallback" do
      ENV["HWARO_MEMORYLIMIT"] = "1G"
      begin
        cmd = Hwaro::CLI::Commands::BuildCommand.new
        options, _ = cmd.parse_options([] of String)

        options.memory_limit.should eq("1G")
        options.streaming?.should be_true
      ensure
        ENV.delete("HWARO_MEMORYLIMIT")
      end
    end

    it "defaults json flag to false" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      _, _, json_output = cmd.parse_options([] of String)
      json_output.should be_false
    end

    it "parses --json flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      _, _, json_output = cmd.parse_options(["--json"])
      json_output.should be_true
    end

    it "parses -j short json flag" do
      cmd = Hwaro::CLI::Commands::BuildCommand.new
      _, _, json_output = cmd.parse_options(["-j"])
      json_output.should be_true
    end

    it "CLI --memory-limit overrides HWARO_MEMORYLIMIT env var" do
      ENV["HWARO_MEMORYLIMIT"] = "1G"
      begin
        cmd = Hwaro::CLI::Commands::BuildCommand.new
        options, _ = cmd.parse_options(["--memory-limit", "2G"])

        options.memory_limit.should eq("2G")
      ensure
        ENV.delete("HWARO_MEMORYLIMIT")
      end
    end
  end
end
