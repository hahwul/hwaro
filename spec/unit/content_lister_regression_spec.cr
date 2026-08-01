require "../spec_helper"

describe "tool list regressions" do
  # Finding 8: front-matter titles are semi-trusted content — a raw ANSI
  # escape in one repainted the maintainer's terminal and threw the table
  # column widths off. `check-links` already sanitised; `list` did not.
  describe "control characters in the table" do
    it "strips escapes from titles before rendering" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "a.md"), "+++\ntitle = \"\e[2J\e[31mPWNED\e[0m\"\n+++\nBody")

        output = with_captured_log do
          Hwaro::Services::ContentLister.new(content_dir).display(Hwaro::Services::ContentFilter::All)
        end

        output.should contain("PWNED")
        output.should_not contain("\e[2J")
        output.should_not contain("\e[31m")
      end
    end

    it "leaves ordinary and non-ASCII titles untouched" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "a.md"), "---\ntitle: 한국어 제목\n---\nBody")

        output = with_captured_log do
          Hwaro::Services::ContentLister.new(content_dir).display(Hwaro::Services::ContentFilter::All)
        end

        output.should contain("한국어 제목")
      end
    end
  end

  # Finding 9: a missing content directory logged "not found" on stderr,
  # printed `[]` on stdout and still exited 0, so a script could not tell
  # "no content" from "wrong directory". `tool validate` and
  # `tool check-links` both classify this as a failure.
  describe "missing content directory" do
    it "raises a classified content error" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "nope")

        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::CLI::Commands::Tool::ListCommand.new.run(["all", "-c", missing])
        end

        err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
        err.exit_code.should eq(Hwaro::Errors::EXIT_CONTENT)
        err.message.to_s.should contain(missing)
      end
    end

    it "raises the same error in JSON mode" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "nope")
        # `--json` flips the process-wide `Runner.enable_json_mode!` switch
        # (which also silences the Logger); restore both so the flag cannot
        # leak into later examples.
        previous_json = Hwaro::CLI::Runner.json_mode?
        previous_quiet = Hwaro::Logger.quiet?
        begin
          expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::Tool::ListCommand.new.run(["all", "-c", missing, "--json"])
          end
        ensure
          Hwaro::CLI::Runner.json_mode = previous_json
          Hwaro::Logger.quiet = previous_quiet
        end
      end
    end

    it "still lists an existing but empty content directory without raising" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)

        with_captured_log do
          Hwaro::CLI::Commands::Tool::ListCommand.new.run(["all", "-c", content_dir])
        end
      end
    end
  end
end
