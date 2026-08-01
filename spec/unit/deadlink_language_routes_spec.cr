require "../spec_helper"

# Review findings 1 and 2. The first cut of the multilingual fix stripped a
# `/<code>/` prefix UNCONDITIONALLY and then resolved, which broke both ways:
#
#   1. False negative — `/ko/x/` passed as soon as the DEFAULT-language
#      `content/x.md` existed, so a link to an untranslated page reported
#      healthy while the build published nothing at `/ko/x/`.
#   2. False positive — a real section at `content/ko/` became unresolvable
#      whenever `ko` was also a declared language, so a link the build DOES
#      publish was reported dead (a regression against the previous release).
#
# The resolver now tries the URL literally first and only then reads it as a
# translation route, accepting language-qualified evidence only.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def resolve_langs_for_test(links : Array(Link), content_dir : String,
                             taxonomy_names : Array(String), language_codes : Array(String)) : Array(Result)
    check_internal_links(links, content_dir, taxonomy_names, "", language_codes)
  end
end

private def lang_link(dir : String, url : String, kind : Symbol = :internal)
  Hwaro::CLI::Commands::Tool::DeadlinkCommand::Link.new(
    file: File.join(dir, "_index.md"), url: url, kind: kind)
end

private def dead_urls(dir : String, url : String, codes : Array(String),
                      taxonomies : Array(String) = [] of String, kind : Symbol = :internal) : Array(String)
  cmd = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
  cmd.resolve_langs_for_test([lang_link(dir, url, kind)], dir, taxonomies, codes).map(&.link.url)
end

describe "check-links language routes" do
  describe "untranslated pages are still dead (finding 1)" do
    it "does not accept the default-language source for a /<lang>/ URL" do
      Dir.mktmpdir do |dir|
        # Only the English source exists; the build emits no /ko/onlyenglish/.
        File.write(File.join(dir, "onlyenglish.md"), "---\ntitle: OE\n---\nBody")

        dead_urls(dir, "/ko/onlyenglish/", ["ko"]).should eq(["/ko/onlyenglish/"])
      end
    end

    it "accepts it once the translation exists" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "onlyenglish.md"), "---\ntitle: OE\n---\nBody")
        File.write(File.join(dir, "onlyenglish.ko.md"), "---\ntitle: OE ko\n---\nBody")

        dead_urls(dir, "/ko/onlyenglish/", ["ko"]).should be_empty
      end
    end

    it "does not language-prefix static assets" do
      # `/ko/images/x.png` is not a route the build serves even though
      # `static/images/x.png` exists.
      Dir.mktmpdir do |dir|
        content = File.join(dir, "content")
        FileUtils.mkdir_p(File.join(dir, "static", "images"))
        FileUtils.mkdir_p(content)
        File.write(File.join(dir, "static", "images", "x.png"), "png")

        dead_urls(content, "/ko/images/x.png", ["ko"], kind: :image)
          .should eq(["/ko/images/x.png"])
      end
    end

    it "rejects a hyphenated locale prefix the build cannot route" do
      # `ReadContent::LANGUAGE_FILENAME_PATTERN` only matches 2-3 lowercase
      # letters, so `about.pt-BR.md` is read as an ordinary page published at
      # `/about.pt-BR/` — `/pt-BR/about/` 404s.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "about.md"), "---\ntitle: A\n---\nen")
        File.write(File.join(dir, "about.pt-BR.md"), "---\ntitle: A pt\n---\npt")

        dead_urls(dir, "/pt-BR/about/", ["pt-BR"]).should eq(["/pt-BR/about/"])
      end
    end
  end

  describe "real sections named like a language still resolve (finding 2)" do
    it "resolves content/<code>/<section>/ when <code> is also a language" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "ko", "posts"))
        File.write(File.join(dir, "ko", "posts", "_index.md"), "---\ntitle: KP\n---\nBody")

        dead_urls(dir, "/ko/posts/", ["ko"]).should be_empty
      end
    end

    it "resolves a leaf page under a section named like a language" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "de"))
        File.write(File.join(dir, "de", "guide.md"), "---\ntitle: G\n---\nBody")

        dead_urls(dir, "/de/guide/", ["de"]).should be_empty
      end
    end

    it "prefers the literal section over a same-named translation" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "ko"))
        File.write(File.join(dir, "ko", "posts.md"), "---\ntitle: literal\n---\nBody")

        dead_urls(dir, "/ko/posts/", ["ko"]).should be_empty
      end
    end
  end

  describe "translation routes that do resolve" do
    it "accepts a translated section index" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "posts"))
        File.write(File.join(dir, "posts", "_index.ko.md"), "---\ntitle: KO\n---\nBody")

        dead_urls(dir, "/ko/posts/", ["ko"]).should be_empty
      end
    end

    it "accepts a language-prefixed taxonomy listing" do
      Dir.mktmpdir do |dir|
        dead_urls(dir, "/ko/tags/", ["ko"], taxonomies: ["tags"]).should be_empty
      end
    end

    it "leaves non-language prefixes alone" do
      Dir.mktmpdir do |dir|
        dead_urls(dir, "/ko/missing/", [] of String).should eq(["/ko/missing/"])
      end
    end
  end
end
