require "../spec_helper"

# Renderer mirroring Builder#feed_template_renderer: a fresh Crinja env per
# call (TemplateEngine registers the same filters — xml_escape, date, …).
private def feed_renderer : Hwaro::Content::Seo::Feeds::Renderer
  ->(source : String, context : Hash(String, Crinja::Value)) do
    env = Hwaro::Content::Processors::TemplateEngine.new.env
    env.from_string(source).render(context)
  end
end

private def feed_config(type : String = "rss") : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.feeds.enabled = true
  config.feeds.type = type
  config.base_url = "https://example.com"
  config.title = "Test Site"
  config.description = "A test site"
  config
end

private def feed_page(
  path : String = "posts/hello.md",
  url : String = "/posts/hello/",
  title : String = "Hello World",
  date : Time? = Time.utc(2026, 3, 5),
) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.title = title
  page.url = url
  page.date = date
  page.section = Path[path].dirname.to_s.presence || ""
  page.draft = false
  page.render = true
  page.is_index = false
  page.raw_content = "Some content"
  page.content = "<p>Some content</p>"
  page
end

describe Hwaro::Content::Seo::Feeds do
  describe "user feed templates" do
    it "uses the rss.xml template override when present" do
      config = feed_config("rss")
      templates = {"rss.xml" => "CUSTOM-FEED type={{ feed.type }} kind={{ feed.kind }} items={{ pages | length }}"}

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([feed_page], config, output_dir,
          templates: templates, renderer: feed_renderer)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should eq("CUSTOM-FEED type=rss kind=main items=1")
      end
    end

    it "produces byte-identical output to the programmatic path when the template is absent" do
      config = feed_config("rss")
      page = feed_page

      programmatic = uninitialized String
      via_plumbing = uninitialized String

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)
        programmatic = File.read(File.join(output_dir, "rss.xml"))
      end

      Dir.mktmpdir do |output_dir|
        # templates hash carries unrelated keys only — no rss.xml/atom.xml.
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir,
          templates: {"page" => "{{ content }}"}, renderer: feed_renderer)
        via_plumbing = File.read(File.join(output_dir, "rss.xml"))
      end

      via_plumbing.should eq(programmatic)
    end

    it "selects the template by feed type (atom ignores an rss override)" do
      config = feed_config("atom")
      templates = {
        "rss.xml"  => "RSS-OVERRIDE",
        "atom.xml" => "ATOM-OVERRIDE type={{ feed.type }}",
      }

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([feed_page], config, output_dir,
          templates: templates, renderer: feed_renderer)

        File.exists?(File.join(output_dir, "rss.xml")).should be_false
        File.read(File.join(output_dir, "atom.xml")).should eq("ATOM-OVERRIDE type=atom")
      end
    end

    it "honors a custom feeds.filename for the output path while using the override" do
      config = feed_config("rss")
      config.feeds.filename = "feed.xml"
      templates = {"rss.xml" => "CUSTOM url={{ feed.url }}"}

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([feed_page], config, output_dir,
          templates: templates, renderer: feed_renderer)

        # Output file follows the configured filename; the self URL inside
        # the context follows it too.
        content = File.read(File.join(output_dir, "feed.xml"))
        content.should eq("CUSTOM url=https://example.com/feed.xml")
      end
    end

    it "exposes a correct context (urls, dates, summary, content, categories, title fallback)" do
      config = feed_config("rss")
      page = feed_page(path: "posts/한글.md", url: "/posts/한글/", date: Time.utc(2026, 3, 5))
      page.tags = ["crystal", "hwaro"]
      page.taxonomies = {"categories" => ["dev"]}
      page.content = %(<p>Body with a <a href="/inside/">link</a></p>)

      untitled = feed_page(path: "posts/untitled.md", url: "/posts/untitled/", title: "", date: nil)
      untitled.content = "<p>Untitled body</p>"

      template = <<-JINJA
        {%- for p in pages -%}
        title={{ p.title }}
        url={{ p.url }}
        date_rfc822={% if p.date_rfc822 %}{{ p.date_rfc822 }}{% endif %}
        updated_rfc3339={{ p.updated_rfc3339 }}
        summary={{ p.summary }}
        content_html={{ p.content_html }}
        content_is_html={{ p.content_is_html }}
        categories={{ p.categories | join(",") }}
        section={{ p.section }}
        ---
        {% endfor -%}
        feed_updated_rfc822={{ feed.updated_rfc822 }}
        feed_updated_rfc3339={{ feed.updated_rfc3339 }}
        feed_author={{ feed.author }}
        JINJA
      templates = {"rss.xml" => template}

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page, untitled], config, output_dir,
          templates: templates, renderer: feed_renderer)

        content = File.read(File.join(output_dir, "rss.xml"))

        # Absolute + percent-encoded URL
        content.should contain("url=https://example.com/posts/%ED%95%9C%EA%B8%80/")
        # Zero-padded RFC 822 date
        content.should contain("date_rfc822=Thu, 05 Mar 2026 00:00:00 +0000")
        # Deterministic RFC 3339 timestamp
        content.should contain("updated_rfc3339=2026-03-05T00:00:00Z")
        # Summary is plain text (no tags)
        content.should contain("summary=Body with a link")
        # content_html is absolutized against the page URL
        content.should contain(%(content_html=<p>Body with a <a href="https://example.com/inside/">link</a></p>))
        content.should contain("content_is_html=true")
        # Categories: tags first, then other taxonomy terms, order preserved
        content.should contain("categories=crystal,hwaro,dev")
        content.should contain("section=posts")

        # Empty title falls back to the site title; dateless page has an
        # empty date_rfc822 and the epoch fallback for updated_rfc3339.
        content.should contain("title=Test Site")
        content.should contain("date_rfc822=\n")
        content.should contain("updated_rfc3339=1970-01-01T00:00:00Z")

        # Feed-level values mirror the Atom generator's deterministic rules.
        content.should contain("feed_updated_rfc822=Thu, 05 Mar 2026 00:00:00 +0000")
        content.should contain("feed_updated_rfc3339=2026-03-05T00:00:00Z")
        content.should contain("feed_author=Test Site")
      end
    end

    it "exposes section kind variables for section feeds" do
      config = feed_config("rss")
      templates = {"rss.xml" => "kind={{ feed.kind }} section_url={{ feed.section_url }} url={{ feed.url }}"}

      section = Hwaro::Models::Section.new("posts/_index.md")
      section.title = "Posts"
      section.url = "/posts/"
      section.render = true
      section.generate_feeds = true

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([feed_page, section], config, output_dir,
          templates: templates, renderer: feed_renderer)

        content = File.read(File.join(output_dir, "posts", "rss.xml"))
        content.should eq("kind=section section_url=/posts/ url=https://example.com/posts/rss.xml")
      end
    end

    it "exposes language kind variables for per-language feeds" do
      config = feed_config("rss")
      config.feeds.filename = "rss.xml"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      templates = {"rss.xml" => "kind={{ feed.kind }} language={{ feed.language }} home={{ feed.home_url }}"}

      ko_page = feed_page(path: "posts/hello.ko.md", url: "/ko/posts/hello/")
      ko_page.language = "ko"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir,
          templates: templates, renderer: feed_renderer)

        content = File.read(File.join(output_dir, "ko", "rss.xml"))
        content.should eq("kind=language language=ko home=https://example.com/ko/")
      end
    end

    it "supports the xml_escape filter in feed templates" do
      config = feed_config("rss")
      templates = {"rss.xml" => "{{ pages[0].title | xml_escape }}"}
      page = feed_page(title: "Ampersands & <Angles>")

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir,
          templates: templates, renderer: feed_renderer)

        File.read(File.join(output_dir, "rss.xml")).should eq("Ampersands &amp; &lt;Angles&gt;")
      end
    end

    it "raises a classified template error for a broken feed template" do
      config = feed_config("rss")
      templates = {"rss.xml" => "{{ feed.title | no_such_filter }}"}

      Dir.mktmpdir do |output_dir|
        ex = expect_raises(Hwaro::HwaroError, /Feed template 'rss.xml' failed to render/) do
          Hwaro::Content::Seo::Feeds.generate([feed_page], config, output_dir,
            templates: templates, renderer: feed_renderer)
        end
        ex.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
        ex.hint.not_nil!.should contain("templates/rss.xml.jinja")
      end
    end
  end
end
