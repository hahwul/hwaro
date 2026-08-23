require "../spec_helper"
require "../../src/services/platform_config"

describe "PlatformConfig alias-scan stability" do
  # Finding 1: scan_content_for_aliases recursed through symlinked
  # directories, so a symlink cycle (`ln -s . content/loop`) recursed until
  # ELOOP aborted the whole command. Symlinked directories are skipped.
  it "survives a symlinked directory cycle in content/" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        File.write("content/posts/p.md", "---\ntitle: P\naliases:\n  - /old/\n---\nBody\n")
        File.symlink(File.join(dir, "content"), File.join(dir, "content", "loop"))

        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("netlify")

        result.should contain("from = \"/old/\"")
        result.should contain("to = \"/posts/p/\"")
      end
    end
  end

  # Finding 2: one unparseable content file (invalid UTF-8 → ArgumentError
  # from PCRE2; malformed frontmatter → HwaroError) aborted all platform
  # config generation. It must degrade per file and keep going.
  it "continues past an unparseable content file and keeps the healthy aliases" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        # Invalid UTF-8 bytes make PCRE2 raise ArgumentError mid-parse.
        File.write("content/posts/bad-utf8.md", Bytes[0x2B, 0x2B, 0x2B, 0x0A, 0xFF, 0x0A])
        # Malformed TOML frontmatter raises a HwaroError from the parser.
        File.write("content/posts/bad-toml.md", "+++\ntitle = = broken\n+++\nBody\n")
        File.write("content/posts/good.md", "---\ntitle: Good\naliases:\n  - /kept/\n---\nBody\n")

        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)

        result = ""
        with_captured_log { result = generator.generate("netlify") }
        result.should contain("from = \"/kept/\"")
      end
    end
  end

  # Finding 3: toml_escape only handled \ and ", so an alias containing a
  # newline produced an unparseable netlify.toml. Control characters are now
  # escaped (chosen over skipping, matching the existing escape-not-drop
  # behavior for quotes/backslashes; cloudflare's _redirects keeps skipping
  # because that format has no escape syntax).
  it "escapes control characters in netlify redirect aliases so the TOML stays parseable" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        # YAML double-quoted scalars inject a real newline and tab into the
        # alias values.
        File.write("content/posts/p.md",
          "---\ntitle: P\naliases:\n  - \"/line\\nbreak/\"\n  - \"/tab\\there/\"\n---\nBody\n")

        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("netlify")

        # The raw control bytes must not appear inside the basic strings.
        result.should contain("from = \"/line\\nbreak/\"")
        result.should contain("from = \"/tab\\there/\"")

        # The emitted netlify.toml parses, and the values round-trip.
        parsed = TOML.parse(result)
        froms = parsed["redirects"].as_a.map(&.["from"].as_s)
        froms.should contain("/line\nbreak/")
        froms.should contain("/tab\there/")
      end
    end
  end

  # Review follow-up: TOML's \u escape takes exactly four hex digits, so a
  # control/format character above U+FFFF (Char#control? is true for Cf tag
  # characters) emitted a five-digit \u that TOML parsers reject.
  it "escapes supplementary-plane control characters with the 8-digit \\U form" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        File.write("content/posts/p.md",
          "---\ntitle: P\naliases:\n  - \"/tag\\U000E0001here/\"\n---\nBody\n")

        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("netlify")

        result.should contain("\\U000E0001")
        result.should_not contain("\\ue0001")
        result.should_not contain("\\uE0001")
      end
    end
  end

  # Review follow-up: the alias walk itself had no rescue, so one unreadable
  # subdirectory under content/ aborted the whole platform-config run (the
  # same class walk_files_into was fixed for on the importer side).
  it "skips an unreadable content subdirectory instead of aborting" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("content/locked")
        File.write("content/posts/p.md", "---\ntitle: P\naliases:\n  - /kept/\n---\nBody\n")
        File.write("content/locked/hidden.md", "---\ntitle: H\n---\nBody\n")
        File.chmod("content/locked", 0o000)

        readable_anyway = begin
          Dir.children("content/locked")
          true
        rescue File::Error
          false
        end

        begin
          unless readable_anyway
            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = ""
            with_captured_log { result = generator.generate("netlify") }
            result.should contain("from = \"/kept/\"")
          end
        ensure
          File.chmod("content/locked", 0o755)
        end
      end
    end
  end
end
