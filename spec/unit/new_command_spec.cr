require "../spec_helper"
require "../../src/cli/commands/new_command"

describe Hwaro::CLI::Commands::NewCommand do
  describe "#parse_options" do
    it "parses path argument" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["posts/hello.md"])
      options.path.should eq("posts/hello.md")
    end

    it "parses title flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["--title", "Hello World"])
      options.title.should eq("Hello World")

      options, _json = cmd.parse_options(["-t", "My Title"])
      options.title.should eq("My Title")
    end

    it "parses archetype flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["--archetype", "blog"])
      options.archetype.should eq("blog")

      options, _json = cmd.parse_options(["-a", "news"])
      options.archetype.should eq("news")
    end

    it "parses combinations of flags and arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["posts/new.md", "--title", "New Post", "-a", "blog"])

      options.path.should eq("posts/new.md")
      options.title.should eq("New Post")
      options.archetype.should eq("blog")
    end

    it "parses --date flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--date", "2026-03-22"])
      options.date.should eq("2026-03-22")
    end

    it "parses --draft flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--draft"])
      options.draft.should be_true
    end

    it "defaults draft to nil (auto-detect)" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md"])
      options.draft.should be_nil
    end

    it "parses --tags flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--tags", "go,web,api"])
      options.tags.should eq(["go", "web", "api"])
    end

    it "parses --tags with spaces" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--tags", "go, web, api"])
      options.tags.should eq(["go", "web", "api"])
    end

    it "defaults tags to empty" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md"])
      options.tags.should be_empty
    end

    it "parses --section flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["post.md", "--section", "blog"])
      options.section.should eq("blog")

      options, _json = cmd.parse_options(["post.md", "-s", "docs"])
      options.section.should eq("docs")
    end

    it "handles empty arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options([] of String)

      options.path.should be_nil
      options.title.should be_nil
      options.archetype.should be_nil
      options.date.should be_nil
      options.draft.should be_nil
      options.tags.should be_empty
      options.section.should be_nil
    end

    it "raises on unknown flags" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      expect_raises(OptionParser::InvalidOption) do
        cmd.parse_options(["--unknown"])
      end
    end

    it "defaults bundle to nil (fall back to archetype/config)" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _ = cmd.parse_options(["post.md"])
      options.bundle.should be_nil
    end

    it "parses --bundle as true and --no-bundle as false" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _ = cmd.parse_options(["post.md", "--bundle"])
      options.bundle.should be_true

      options, _ = cmd.parse_options(["post.md", "--no-bundle"])
      options.bundle.should be_false
    end

    it "parses --json flag" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      _, json_output = cmd.parse_options(["post.md", "--json"])
      json_output.should be_true

      _, json_output = cmd.parse_options(["post.md"])
      json_output.should be_false
    end

    it "raises on extra positional arguments instead of silently dropping them" do
      # `hwaro new post.md --title My Post` (unquoted title) used to scaffold
      # `post.md` and silently discard `Post` — now it's a classified error.
      cmd = Hwaro::CLI::Commands::NewCommand.new
      err = expect_raises(Hwaro::HwaroError) do
        cmd.parse_options(["a.md", "b.md"])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      (err.message || "").should contain("b.md")
    end

    it "accepts a leading-dash path after `--`" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      options, _json = cmd.parse_options(["--", "-dash.md"])
      options.path.should eq("-dash.md")
    end

    it "still reports unknown flags as invalid options, not extra arguments" do
      cmd = Hwaro::CLI::Commands::NewCommand.new
      expect_raises(OptionParser::InvalidOption) do
        cmd.parse_options(["--bogus", "x.md"])
      end
    end
  end

  # A malformed `config.toml` must surface as the same classified
  # HWARO_E_CONFIG error that every other command raises. Silently falling
  # back to defaults would hide user typos from `hwaro new`.
  describe "#run with malformed config" do
    it "raises HwaroError(HWARO_E_CONFIG) when config.toml is broken" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", "this = = broken\n")
          FileUtils.mkdir_p("content/drafts")

          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["post.md", "-t", "Hello"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        end
      end
    end
  end

  # `hwaro new` must refuse to run outside a Hwaro project — otherwise a
  # mis-typed `cd` would silently scatter `content/…` files in arbitrary
  # directories. Same contract as `hwaro build`.
  describe "#run outside a Hwaro project" do
    it "raises HwaroError(HWARO_E_CONFIG) when config.toml is missing" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["post.md", "-t", "Hello"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          (err.message || "").should contain("config.toml not found")
          # Crucially, nothing was written.
          Dir.exists?(File.join(dir, "content")).should be_false
        end
      end
    end
  end

  # Path-shape validation happens at the CLI boundary so each bad path
  # surfaces as a classified usage error (exit 2, JSON payload if --json).
  # The Creator class itself is tested more thoroughly in creator_spec.cr.
  describe "#run path validation" do
    it "rejects `..`-escaping paths with HWARO_E_USAGE" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["../escaped.md", "-t", "X"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          err.exit_code.should eq(Hwaro::Errors::EXIT_USAGE)
          (err.message || "").should contain("escapes the content/ directory")

          # Nothing should have been written anywhere.
          File.exists?(File.join(dir, "escaped.md")).should be_false
          File.exists?("escaped.md").should be_false
        end
      end
    end

    it "rejects absolute paths with HWARO_E_USAGE" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["/tmp/hwaro-evil.md", "-t", "X"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          (err.message || "").should contain("Absolute path")

          File.exists?("/tmp/hwaro-evil.md").should be_false
          File.exists?("content/tmp/hwaro-evil.md").should be_false
        end
      end
    end

    it "rejects empty path with HWARO_E_USAGE" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["", "-t", "X"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          (err.message || "").should contain("missing <path>")
        end
      end
    end

    it "rejects `..`-escaping --section with HWARO_E_USAGE" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          # Benign path arg isolates the --section guard (the section
          # validate_and_normalize_path! block).
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["post.md", "--section", "../escape"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)

          # `--section ..` must not write a file outside content/.
          File.exists?(File.join(dir, "escape", "post.md")).should be_false
          File.exists?("escape/post.md").should be_false
        end
      end
    end

    it "sanitizes a URL-unsafe --section to a safe on-disk directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          Hwaro::CLI::Commands::NewCommand.new.run(["post.md", "--section", "my section!"])

          # The space/`!` are rewritten before the section becomes a directory,
          # so the file lands under a sanitized dir, not a literal "my section!".
          Dir.exists?("content/my section!").should be_false
          File.exists?("content/my-section/post.md").should be_true
        end
      end
    end

    it "normalizes double slashes in the input path" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          Hwaro::CLI::Commands::NewCommand.new.run(["posts//slashy.md", "-t", "Slashy"])

          # Canonical path on disk.
          File.exists?("content/posts/slashy.md").should be_true
          # No phantom dir from the stray slash.
          Dir.exists?("content/posts/").should be_true
          Dir.children("content/posts").includes?("").should be_false
        end
      end
    end

    it "rejects paths whose sanitized form would synthesize `..` (no file escapes content/)" do
      # `.>.` is not `..`, so it survived the first structural validation —
      # but sanitizing `>` → `-` and collapsing hyphens against dots turned it
      # into `..`, and the file landed OUTSIDE the project directory.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["posts/.>./.>./.>./evil.md", "-t", "X"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)

          File.exists?(File.join(dir, "evil.md")).should be_false
          File.exists?(File.join(dir, "..", "evil.md")).should be_false
        end
      end
    end

    it "rejects a path that sanitizes to a hidden filename" do
      # `!.md` sanitizes to `.md` — a dotfile the build's glob never sees.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::NewCommand.new.run(["!.md", "-t", "X"])
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
          (err.message || "").should contain("hidden segment")
          File.exists?("content/.md").should be_false
        end
      end
    end

    it "normalizes a case-variant .MD extension instead of double-suffixing" do
      # `Foo.MD` slipped past every `ends_with?(".md")` heuristic and
      # scaffolded `Foo.MD.md`.
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = ""\n))
          FileUtils.mkdir_p("content")
          Hwaro::CLI::Commands::NewCommand.new.run(["Foo.MD", "-t", "T"])

          File.exists?("content/Foo.md").should be_true
          File.exists?("content/Foo.MD.md").should be_false
        end
      end
    end
  end
end
