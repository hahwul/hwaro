require "../../../../spec_helper"

# Test helper exposing the private scan/resolve methods under names that do
# not collide with the ones `deadlink_command_spec.cr` already defines.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def resolve_internal_for_test(links : Array(Link), content_dir : String, taxonomy_names : Array(String), base_path : String, language_codes : Array(String)) : Array(Result)
    check_internal_links(links, content_dir, taxonomy_names, base_path, language_codes)
  end

  def scan_internal_for_test(dir : String) : Array(Link)
    find_internal_links(dir)
  end

  def scan_external_for_test(dir : String) : Array(Link)
    find_external_links(dir)
  end

  def translation_language_codes_for_test(config : Hwaro::Models::Config?) : Array(String)
    translation_language_codes(config)
  end

  def routes_for_test(config : Hwaro::Models::Config?) : GeneratedRoutes
    generated_routes(config)
  end

  def resolve_with_routes_for_test(links : Array(Link), content_dir : String, routes : GeneratedRoutes) : Array(Result)
    check_internal_links(links, content_dir, [] of String, "", [] of String, routes)
  end
end

describe "check-links regressions" do
  # Finding 1: a multilingual site serves `content/about.ko.md` at `/ko/about/`.
  # The resolver had no language awareness, so it looked for `content/ko/about`
  # and reported every translated link dead — 288 of 576 links on hwaro's own
  # docs site, and every `hwaro init --include-multilingual` scaffold.
  describe "language-prefixed internal links" do
    it "resolves /<lang>/<page>/ against the translated source file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "about.md"), "---\ntitle: About\n---\nEN")
        File.write(File.join(dir, "about.ko.md"), "---\ntitle: 소개\n---\nKO")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.ko.md"), url: "/ko/about/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, [] of String, "", ["ko"]).should be_empty
      end
    end

    it "resolves a language-prefixed section index (_index.<lang>.md)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "posts"))
        File.write(File.join(dir, "posts", "_index.ko.md"), "---\ntitle: 글\n---\nKO")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.ko.md"), url: "/ko/posts/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, [] of String, "", ["ko"]).should be_empty
      end
    end

    it "accepts a language-prefixed taxonomy listing" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.ko.md"), "---\ntitle: 홈\n---\nKO")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.ko.md"), url: "/ko/tags/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, ["tags"], "", ["ko"]).should be_empty
      end
    end

    # NOTE: the real holes — default-language page present but translation
    # absent, and a `content/<lang>/` section colliding with a language code —
    # are covered in `deadlink_language_routes_spec.cr`. This example only
    # pins the trivial case where nothing exists in any language.
    it "still reports a language-prefixed target absent in every language" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.ko.md"), "---\ntitle: 홈\n---\nKO")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.ko.md"), url: "/ko/nope/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, [] of String, "", ["ko"]).size.should eq(1)
      end
    end

    it "does not strip a segment that merely looks like a language code" do
      # `/ko/…` must only be treated as a language prefix when `ko` is a
      # declared language; otherwise a real `content/ko/` section would be
      # silently resolved against the wrong path.
      Dir.mktmpdir do |dir|
        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.md"), url: "/ko/about/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, [] of String, "", [] of String).size.should eq(1)
      end
    end

    it "excludes the default language from the prefix list" do
      config = Hwaro::Models::Config.new
      config.default_language = "en"
      config.languages["en"] = Hwaro::Models::LanguageConfig.new("en")
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      cmd.translation_language_codes_for_test(config).should eq(["ko"])
      cmd.translation_language_codes_for_test(nil).should be_empty
    end
  end

  # `.markdown` is a first-class page extension (read_content
  # PAGE_EXTENSIONS), so the resolver must probe the same section-index and
  # translated-source candidates it probes for `.md`.
  describe ".markdown source resolution" do
    it "resolves a section index backed by _index.markdown" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "guides"))
        File.write(File.join(dir, "guides", "_index.markdown"), "---\ntitle: Guides\n---\n")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.md"), url: "/guides/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, [] of String, "", [] of String).should be_empty
      end
    end

    it "resolves a language-prefixed section index backed by _index.<code>.markdown" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "guides"))
        File.write(File.join(dir, "guides", "_index.ko.markdown"), "---\ntitle: 안내\n---\n")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        link = Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
          file: File.join(dir, "index.ko.md"), url: "/ko/guides/", kind: :internal)

        cmd.resolve_internal_for_test([link], dir, [] of String, "", ["ko"]).should be_empty
      end
    end
  end

  # Finding 6: PCRE2 raises ArgumentError on invalid UTF-8, which used to abort
  # the whole run with a bare "Error: Regex match error" and exit 1 — the same
  # code as "dead links found".
  describe "unreadable content files" do
    it "skips a file containing invalid UTF-8 instead of aborting the scan" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "bad.md"), Bytes[0x2B, 0x2B, 0x2B, 0x0A, 0xFF, 0x0A])
        File.write(File.join(dir, "good.md"), "---\ntitle: G\n---\n[l](/target/)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        urls = cmd.scan_internal_for_test(dir).map(&.url)

        urls.should eq(["/target/"])
      end
    end

    it "keeps scanning external links after an unreadable file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "bad.md"), Bytes[0xFF, 0xFE, 0x0A])
        File.write(File.join(dir, "good.md"), "[e](https://example.com/x)")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.scan_external_for_test(dir).map(&.url).should eq(["https://example.com/x"])
      end
    end
  end

  # Finding 10: reference-style links and raw HTML anchors/images render as
  # real links but were invisible to the scanner.
  describe "reference-style and raw HTML links" do
    it "finds internal reference-link definitions" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"), "---\ntitle: A\n---\nSee [docs][d].\n\n[d]: /guide/\n")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.scan_internal_for_test(dir).map(&.url).should eq(["/guide/"])
      end
    end

    it "finds external reference-link definitions" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"), "---\ntitle: A\n---\n[x][e]\n\n[e]: https://example.com/ref\n")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.scan_external_for_test(dir).map(&.url).should eq(["https://example.com/ref"])
      end
    end

    it "finds raw HTML anchors and images" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"),
          "---\ntitle: A\n---\n<a href=\"/html-link/\">x</a>\n<img src=\"/img/pic.png\">\n")

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        links = cmd.scan_internal_for_test(dir)

        links.map(&.url).should eq(["/html-link/", "/img/pic.png"])
        links.map(&.kind).should eq([:internal, :image])
      end
    end

    it "ignores footnote definitions, prose definitions and template expressions" do
      # `[^1]: See the docs.` and `[note]: plain prose` are not links; a
      # `src="{{ page.image }}"` resolves at build time. Treating any of them
      # as a path produced false "dead link" reports.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"), <<-MD)
          ---
          title: A
          ---
          Body[^1]

          [^1]: See the documentation for details.
          [note]: plain prose, not a target
          <img src="{{ page.image }}">
          MD

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.scan_internal_for_test(dir).should be_empty
      end
    end

    it "does not resurrect reference definitions or HTML from fenced code" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"), <<-MD)
          ---
          title: A
          ---
          ```markdown
          [d]: /example-only/
          <img src="/example-only.png">
          ```
          MD

        cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
        cmd.scan_internal_for_test(dir).should be_empty
      end
    end
  end
end

# Section feeds are gated by the section's own `generate_feeds` and always
# written as rss.xml/atom.xml (see Seo::Feeds); the checker used to key them
# on the ROOT feed's `enabled` flag and `filename`.
private def feed_link(dir : String, url : String)
  Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(file: File.join(dir, "index.md"), url: url, kind: :internal)
end

describe "check-links section feed routes" do
  it "accepts /<section>/rss.xml when the section opts in even though the root feed is disabled" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "posts"))
      File.write(File.join(dir, "posts", "_index.md"), "---\ntitle: Posts\ngenerate_feeds: true\n---\n")
      config = Hwaro::Models::Config.new
      config.feeds.enabled = false

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      routes = cmd.routes_for_test(config)
      cmd.resolve_with_routes_for_test([feed_link(dir, "/posts/rss.xml")], dir, routes).should be_empty
      # The root feed really is off.
      cmd.resolve_with_routes_for_test([feed_link(dir, "/rss.xml")], dir, routes).should_not be_empty
    end
  end

  it "keeps section feeds at rss.xml when the root feed uses a custom filename" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "posts"))
      File.write(File.join(dir, "posts", "_index.md"), "---\ntitle: Posts\ngenerate_feeds: true\n---\n")
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.filename = "feed.xml"

      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      routes = cmd.routes_for_test(config)
      cmd.resolve_with_routes_for_test([feed_link(dir, "/feed.xml")], dir, routes).should be_empty
      cmd.resolve_with_routes_for_test([feed_link(dir, "/posts/rss.xml")], dir, routes).should be_empty
      cmd.resolve_with_routes_for_test([feed_link(dir, "/posts/feed.xml")], dir, routes).should_not be_empty
    end
  end

  it "still rejects a section feed for a section that did not opt in" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "posts"))
      File.write(File.join(dir, "posts", "_index.md"), "---\ntitle: Posts\n---\n")
      config = Hwaro::Models::Config.new
      cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      routes = cmd.routes_for_test(config)
      cmd.resolve_with_routes_for_test([feed_link(dir, "/posts/rss.xml")], dir, routes).should_not be_empty
    end
  end
end
