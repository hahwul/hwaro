require "../../../../../spec_helper"
require "../../../../../support/build_helper"

# `--stream` releases each batch's rendered `page.content` to keep peak memory
# flat. The search index and the feeds read that field back, and their fallback
# is a markdown-only re-render of `raw_content` — no shortcode expansion, no
# `@/` link resolution, no anchor links. Releasing under those consumers put
# raw `{% alert() %}` markup and `…/posts/one/@/posts/two.md` links into
# search.json and rss.xml (the corruption #775 fixed for warm `--cache` builds,
# on the one mode still doing it), so streaming output was NOT identical to a
# normal build the way the docs promise.
STREAM_CONFIG = <<-TOML
  title = "Stream Site"
  base_url = "https://example.com"

  [feeds]
  enabled = true
  full_content = true

  [search]
  enabled = true

  [markdown]
  insert_anchor_links = "right"
  TOML

STREAM_CONTENT = {
  "posts/one.md" => <<-MD,
    +++
    title = "One"
    date = 2026-01-02
    +++

    ## Heading

    {% alert(type="tip") %}Body text.{% endalert %}

    See [two](@/posts/two.md).
    MD
  "posts/two.md" => <<-MD,
    +++
    title = "Two"
    date = 2026-01-01
    +++

    Second post.
    MD
}

describe "streaming build generated outputs" do
  it "expands shortcodes and resolves @/ links in the feed" do
    build_site(STREAM_CONFIG, STREAM_CONTENT, stream: true) do |_dir|
      rss = File.read(File.join("public", "rss.xml"))
      rss.should contain(%(<div class="sc-alert sc-alert--tip"))
      rss.should_not contain("{% alert")
      rss.should contain("https://example.com/posts/two/")
      rss.should_not contain("@/posts/two.md")
    end
  end

  it "expands shortcodes in the search index" do
    build_site(STREAM_CONFIG, STREAM_CONTENT, stream: true) do |_dir|
      index = File.read(File.join("public", "search.json"))
      index.should_not contain("{% alert")
      index.should contain("Body text.")
    end
  end

  it "produces the same feed and index bytes as a non-streaming build" do
    streamed = {} of String => String
    build_site(STREAM_CONFIG, STREAM_CONTENT, stream: true) do |_dir|
      streamed["rss.xml"] = File.read(File.join("public", "rss.xml"))
      streamed["search.json"] = File.read(File.join("public", "search.json"))
    end

    build_site(STREAM_CONFIG, STREAM_CONTENT) do |_dir|
      File.read(File.join("public", "rss.xml")).should eq(streamed["rss.xml"])
      File.read(File.join("public", "search.json")).should eq(streamed["search.json"])
    end
  end

  # The release is still made where it is sound: with no search index and no
  # feed of any kind, nothing reads `page.content` after the Render phase.
  it "still releases page content when no generator reads it" do
    config = <<-TOML
      title = "Stream Site"
      base_url = "https://example.com"

      [feeds]
      enabled = false

      [search]
      enabled = false
      TOML

    build_site(config, STREAM_CONTENT, stream: true) do |_dir|
      File.exists?(File.join("public", "posts", "one", "index.html")).should be_true
      File.exists?(File.join("public", "rss.xml")).should be_false
    end
  end
end
