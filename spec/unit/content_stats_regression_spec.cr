require "../spec_helper"

describe "content analysis regressions" do
  # Finding 4: `extract_body` chained `.sub(TOML_RE, "").sub(YAML_RE, "")`.
  # Once the TOML front matter was gone, the `\A`-anchored YAML pattern
  # matched a *body* that opens with a thematic break and deleted it, so the
  # first block of the document vanished from every check.
  describe "body that opens with a thematic break" do
    it "counts words in the block following TOML front matter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "x.md"),
          "+++\ntitle = \"X\"\n+++\n---\nalpha beta gamma delta\n---\nomega\n")

        result = Hwaro::Services::ContentStats.new(content_dir).run

        # 4 words + the two `---` rules + "omega". Previously only "omega"
        # survived, so words_total was 1.
        result.words_total.should be > 1
        result.words_total.should eq(7)
      end
    end

    it "still reports findings inside that first block" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "y.md"),
          "+++\ntitle = \"Y\"\ndescription = \"d\"\n+++\n---\n![](/a.png)\n---\ntail\n")

        ids = Hwaro::Services::ContentValidator.new(content_dir).run.map(&.id)
        ids.should contain("content-alt-text-missing")
      end
    end

    it "still strips real YAML front matter" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "z.md"), "---\ntitle: Z\n---\none two three\n")

        Hwaro::Services::ContentStats.new(content_dir).run.words_total.should eq(3)
      end
    end
  end

  # Finding 7: stats split the body on whitespace, counting `##`, `|` and
  # `|-----|` as words, so the report disagreed with the `page.word_count` /
  # `page.reading_time` the site itself renders.
  describe "word counting matches the build" do
    body = <<-MD
      ## A heading here

      | col | col2 |
      |-----|------|
      | a   | b    |

      - item one
      - item two

      Some **bold** and `inline` text.
      MD

    it "agrees with Models::Page#calculate_word_count" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "post.md"), "+++\ntitle = \"P\"\n+++\n#{body}\n")

        page = Hwaro::Models::Page.new(File.join(content_dir, "post.md"))
        page.raw_content = "#{body}\n"

        Hwaro::Services::ContentStats.new(content_dir).run.words_total
          .should eq(page.calculate_word_count)
      end
    end

    it "does not count Markdown punctuation as words" do
      Hwaro::Utils::TextUtils.count_words("## Heading").should eq(1)
      Hwaro::Utils::TextUtils.count_words("| a | b |").should eq(2)
      Hwaro::Utils::TextUtils.count_words("<p>one two</p>").should eq(2)
    end

    it "keeps excluding fenced code blocks from the stats report" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "code.md"),
          "---\ntitle: Code\n---\n\nReal words here\n\n```crystal\nputs \"not counted\"\n```\n")

        Hwaro::Services::ContentStats.new(content_dir).run.words_total.should eq(3)
      end
    end
  end

  # Finding 8: titles, tags and link targets are semi-trusted content and were
  # printed to the terminal with their control bytes intact.
  describe "control-character sanitising" do
    it "strips control characters but leaves ordinary text alone" do
      Hwaro::Utils::TextUtils.strip_control("\e[31mred\e[0m").should eq("[31mred[0m")
      Hwaro::Utils::TextUtils.strip_control("plain title").should eq("plain title")
      Hwaro::Utils::TextUtils.strip_control("한글 제목").should eq("한글 제목")
    end

    it "does not leak escapes through validator messages" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "a.md"),
          "+++\ntitle = \"A\"\ndescription = \"d\"\ntags = [\"\e[31mEvil\e[0m\"]\n+++\n![](\e[31m/x.png\e[0m)\n")

        messages = Hwaro::Services::ContentValidator.new(content_dir).run.map(&.message)
        messages.each(&.should_not(contain("\e")))
      end
    end

    it "does not leak escapes through the stats tag chart" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "a.md"),
          "+++\ntitle = \"A\"\ntags = [\"\e[31mEvil\e[0m\"]\n+++\nbody words\n")

        output = with_captured_log do
          Hwaro::CLI::Commands::Tool::StatsCommand.new.run(["-c", content_dir])
        end

        output.should contain("tags")
        output.should_not contain("\e[31m")
      end
    end
  end
end
