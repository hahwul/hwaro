require "../spec_helper"

# =============================================================================
# Automatic summary fallback — model, config and feed wiring.
#
# Precedence is `<!-- more -->` marker > `description` > automatic excerpt.
# Every example that exercises the excerpt fails on the pre-feature code:
# `auto_summary` did not exist, `has_summary?` was false without a marker
# or description, and `[content] summary_length` was an unknown key.
# =============================================================================

private def load_config(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-auto-summary", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

private def auto_page(text : String? = "Automatic excerpt text.") : Hwaro::Models::Page
  page = Hwaro::Models::Page.new("posts/auto.md")
  page.title = "Auto"
  page.url = "/posts/auto/"
  page.raw_content = "Body"
  page.auto_summary = text
  page
end

describe "Automatic summary" do
  describe Hwaro::Models::Page do
    it "has_summary? is true for an automatic excerpt alone" do
      page = auto_page
      page.summary.should be_nil
      page.description.should be_nil
      page.has_summary?.should be_true
      auto_page(nil).has_summary?.should be_false
    end

    it "effective_summary wraps the excerpt in one escaped paragraph" do
      page = auto_page("Tom & Jerry <3 \"quotes\"")
      page.effective_summary.should eq("<p>Tom &amp; Jerry &lt;3 &quot;quotes&quot;</p>")
    end

    it "keeps marker > description > excerpt precedence" do
      page = auto_page
      page.description = "Front matter description"
      page.effective_summary.should eq("Front matter description")

      page.summary = "Marker chunk"
      page.effective_summary.should eq("Marker chunk")
    end

    it "plain_summary returns the excerpt text and soft-truncates it" do
      page = auto_page("word " * 60 + "end")
      page.plain_summary(400).should eq("word " * 60 + "end")
      short = page.plain_summary(20).not_nil!
      short.should end_with("…")
      short.size.should be <= 21
      auto_page(nil).plain_summary.should be_nil
    end

    it "plain_summary still prefers the rendered marker summary" do
      page = auto_page
      page.summary_html = "<p>From <em>marker</em></p>"
      page.plain_summary.should eq("From marker")
    end
  end

  describe Hwaro::Models::SummaryConfig do
    it "defaults to 70 words and a Unicode ellipsis" do
      config = Hwaro::Models::Config.new
      config.summary.length.should eq(70)
      config.summary.ellipsis.should eq("…")
      config.summary.enabled?.should be_true
    end

    it "reads [content] summary_length and summary_ellipsis" do
      config = load_config(<<-TOML)
        title = "T"
        base_url = "http://localhost"

        [content]
        summary_length = 12
        summary_ellipsis = " (more)"
        TOML
      config.summary.length.should eq(12)
      config.summary.ellipsis.should eq(" (more)")
    end

    it "disables the fallback at 0 and clamps a negative length to 0" do
      load_config("title = \"T\"\n[content]\nsummary_length = 0\n").summary.enabled?.should be_false
      neg = load_config("title = \"T\"\n[content]\nsummary_length = -5\n").summary
      neg.length.should eq(0)
      neg.enabled?.should be_false
    end

    it "keeps the default ellipsis when the key is not a string" do
      load_config("title = \"T\"\n[content]\nsummary_ellipsis = 3\n").summary.ellipsis.should eq("…")
    end

    it "folds both keys into the build-cache config hash" do
      base = load_config("title = \"T\"\nbase_url = \"http://localhost\"\n")
      len = load_config("title = \"T\"\nbase_url = \"http://localhost\"\n[content]\nsummary_length = 30\n")
      ell = load_config("title = \"T\"\nbase_url = \"http://localhost\"\n[content]\nsummary_ellipsis = \"...\"\n")
      hashes = [base, len, ell].map { |c| Hwaro::Core::Build::Cache.compute_config_hash(c) }
      hashes.uniq.size.should eq(3)
    end
  end

  describe "feeds" do
    it "uses the automatic excerpt for <description> after the marker summary and before the body" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page = auto_page("Excerpt for the feed.")
      page.date = Time.utc(2026, 1, 1)
      page.content = "<p>Full body that should not be the description.</p>"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)
        feed = File.read(File.join(output_dir, "rss.xml"))
        feed.should contain("<description>Excerpt for the feed.</description>")
        feed.should_not contain("<description>Full body")
      end
    end
  end
end
