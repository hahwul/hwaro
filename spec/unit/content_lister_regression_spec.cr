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

    it "preserves zero-width format characters inside titles" do
      # Hangul alone could not catch this: `strip_control` used to delete Cf,
      # so a ZWNJ/ZWJ/RLM title was silently rewritten into a different word.
      {
        "می\u{200C}رود",
        "👨\u{200D}👩\u{200D}👧",
        "שלום\u{200F}!",
        "soft\u{00AD}hyphen",
      }.each_with_index do |title, i|
        Dir.mktmpdir do |dir|
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(content_dir)
          File.write(File.join(content_dir, "t#{i}.md"), "+++\ntitle = \"#{title}\"\n+++\nBody")

          output = with_captured_log do
            Hwaro::Services::ContentLister.new(content_dir).display(Hwaro::Services::ContentFilter::All)
          end

          output.should contain(title)
        end
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

  # `hwaro build` learned to walk a symlink cycle in content/ (see
  # core/build/phases/read_content.cr), but the tool services kept feeding the
  # raw glob output to `File.read`: every unfollowable link came back as a
  # per-file "Failed to read content file" failure on a tree the build
  # publishes without complaint.
  describe "unfollowable symlinks in content/" do
    it "skips cycles and dangling links instead of reporting read failures" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "real.md"), "+++\ntitle = \"Real\"\n+++\nBody")
        # Self-referential link, mutually-referential pair, dangling link.
        File.symlink("loop.md", File.join(content_dir, "loop.md"))
        File.symlink("b.md", File.join(content_dir, "a.md"))
        File.symlink("a.md", File.join(content_dir, "b.md"))
        File.symlink("gone.md", File.join(content_dir, "dangling.md"))

        result = [] of Hwaro::Services::ContentInfo
        output = with_captured_log do
          result = Hwaro::Services::ContentLister.new(content_dir).list_content(Hwaro::Services::ContentFilter::All)
        end

        result.map(&.title).should eq(["Real"])
        output.should_not contain("Failed to read content file")
        # Skipped, but never silently: each link is named once.
        output.should contain("loop.md")
        output.should contain("dangling.md")
      end
    end
  end
end
