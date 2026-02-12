require "../spec_helper"

describe Hwaro::Models::OpenGraphConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.default_image.should be_nil
      config.twitter_card.should eq("summary_large_image")
      config.twitter_site.should be_nil
      config.twitter_creator.should be_nil
      config.fb_app_id.should be_nil
      config.og_type.should eq("article")
    end
  end

  describe "#og_tags" do
    it "generates basic OG tags with title, type, and url" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:title" content="My Page">))
      tags.should contain(%(<meta property="og:type" content="article">))
      tags.should contain(%(<meta property="og:url" content="https://example.com/about/">))
    end

    it "includes description when provided" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: "A great page about stuff",
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:description" content="A great page about stuff">))
    end

    it "does not include description tag when nil" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("og:description")
    end

    it "includes page image when provided" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: "/images/cover.png",
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:image" content="https://example.com/images/cover.png">))
    end

    it "uses absolute image URL as-is" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: "https://cdn.example.com/images/cover.png",
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:image" content="https://cdn.example.com/images/cover.png">))
    end

    it "falls back to default_image when page image is nil" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.default_image = "/images/default-og.png"

      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:image" content="https://example.com/images/default-og.png">))
    end

    it "prefers page image over default_image" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.default_image = "/images/default-og.png"

      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: "/images/page-specific.png",
        base_url: "https://example.com"
      )

      tags.should contain("page-specific.png")
      tags.should_not contain("default-og.png")
    end

    it "does not include image tag when neither page image nor default is set" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("og:image")
    end

    it "includes fb:app_id when configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.fb_app_id = "123456789"

      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="fb:app_id" content="123456789">))
    end

    it "does not include fb:app_id when not configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("fb:app_id")
    end

    it "uses custom og_type" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.og_type = "website"

      tags = config.og_tags(
        title: "Home",
        description: nil,
        url: "/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:type" content="website">))
    end

    it "escapes HTML special characters in title" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "Tom & Jerry <script>",
        description: nil,
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain("Tom &amp; Jerry &lt;script&gt;")
      tags.should_not contain("<script>")
    end

    it "escapes HTML special characters in description" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: "Use <b>bold</b> & \"quotes\"",
        url: "/about/",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain("&lt;b&gt;bold&lt;/b&gt;")
      tags.should contain("&amp;")
      tags.should contain("&quot;quotes&quot;")
    end

    it "handles image path without leading slash" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.og_tags(
        title: "My Page",
        description: nil,
        url: "/about/",
        image: "images/cover.png",
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta property="og:image" content="https://example.com/images/cover.png">))
    end
  end

  describe "#twitter_tags" do
    it "generates basic Twitter card tags" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:card" content="summary_large_image">))
      tags.should contain(%(<meta name="twitter:title" content="My Page">))
    end

    it "includes description when provided" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: "A short description",
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:description" content="A short description">))
    end

    it "does not include description when nil" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("twitter:description")
    end

    it "includes page image" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: "/images/twitter-card.png",
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:image" content="https://example.com/images/twitter-card.png">))
    end

    it "falls back to default_image" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.default_image = "/images/default-twitter.png"

      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:image" content="https://example.com/images/default-twitter.png">))
    end

    it "does not include image tag when no image available" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("twitter:image")
    end

    it "includes twitter:site when configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_site = "@mysite"

      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:site" content="@mysite">))
    end

    it "does not include twitter:site when not configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("twitter:site")
    end

    it "includes twitter:creator when configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_creator = "@author"

      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:creator" content="@author">))
    end

    it "does not include twitter:creator when not configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should_not contain("twitter:creator")
    end

    it "uses custom twitter_card type" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_card = "summary"

      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:card" content="summary">))
    end

    it "escapes HTML in title" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "Tom & Jerry's \"Adventure\"",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain("Tom &amp; Jerry")
      tags.should contain("&quot;Adventure&quot;")
    end

    it "uses absolute image URL as-is" do
      config = Hwaro::Models::OpenGraphConfig.new
      tags = config.twitter_tags(
        title: "My Page",
        description: nil,
        image: "https://cdn.example.com/img.png",
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:image" content="https://cdn.example.com/img.png">))
    end

    it "includes both site and creator when configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_site = "@site_handle"
      config.twitter_creator = "@author_handle"

      tags = config.twitter_tags(
        title: "Post",
        description: nil,
        image: nil,
        base_url: "https://example.com"
      )

      tags.should contain(%(<meta name="twitter:site" content="@site_handle">))
      tags.should contain(%(<meta name="twitter:creator" content="@author_handle">))
    end
  end

  describe "#all_tags" do
    it "combines both OG and Twitter tags" do
      config = Hwaro::Models::OpenGraphConfig.new
      combined = config.all_tags(
        title: "My Page",
        description: "A description",
        url: "/about/",
        image: "/images/cover.png",
        base_url: "https://example.com"
      )

      # Should contain OG tags
      combined.should contain("og:title")
      combined.should contain("og:type")
      combined.should contain("og:url")
      combined.should contain("og:description")
      combined.should contain("og:image")

      # Should contain Twitter tags
      combined.should contain("twitter:card")
      combined.should contain("twitter:title")
      combined.should contain("twitter:description")
      combined.should contain("twitter:image")
    end

    it "returns only OG tags when Twitter tags are minimal" do
      config = Hwaro::Models::OpenGraphConfig.new
      combined = config.all_tags(
        title: "My Page",
        description: nil,
        url: "/",
        image: nil,
        base_url: "https://example.com"
      )

      combined.should contain("og:title")
      combined.should contain("twitter:card")
      combined.should contain("twitter:title")
    end

    it "includes fb_app_id and twitter_site when configured" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.fb_app_id = "999888777"
      config.twitter_site = "@mysite"

      combined = config.all_tags(
        title: "Page",
        description: nil,
        url: "/",
        image: nil,
        base_url: "https://example.com"
      )

      combined.should contain("fb:app_id")
      combined.should contain("999888777")
      combined.should contain("twitter:site")
      combined.should contain("@mysite")
    end

    it "produces consistent output with og_tags + twitter_tags" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_site = "@test"
      config.default_image = "/img/default.png"

      og = config.og_tags(
        title: "Test",
        description: "Desc",
        url: "/test/",
        image: nil,
        base_url: "https://example.com"
      )

      twitter = config.twitter_tags(
        title: "Test",
        description: "Desc",
        image: nil,
        base_url: "https://example.com"
      )

      combined = config.all_tags(
        title: "Test",
        description: "Desc",
        url: "/test/",
        image: nil,
        base_url: "https://example.com"
      )

      expected = [og, twitter].reject(&.empty?).join("\n")
      combined.should eq(expected)
    end

    it "handles all-nil optional fields gracefully" do
      config = Hwaro::Models::OpenGraphConfig.new
      combined = config.all_tags(
        title: "Minimal",
        description: nil,
        url: "/",
        image: nil,
        base_url: ""
      )

      combined.should contain("og:title")
      combined.should contain("twitter:title")
      combined.should_not contain("og:description")
      combined.should_not contain("og:image")
      combined.should_not contain("twitter:description")
      combined.should_not contain("twitter:image")
    end
  end

  describe "property setters" do
    it "can set default_image" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.default_image = "/images/og.png"
      config.default_image.should eq("/images/og.png")
    end

    it "can set twitter_card" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_card = "summary"
      config.twitter_card.should eq("summary")
    end

    it "can set twitter_site" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_site = "@example"
      config.twitter_site.should eq("@example")
    end

    it "can set twitter_creator" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.twitter_creator = "@creator"
      config.twitter_creator.should eq("@creator")
    end

    it "can set fb_app_id" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.fb_app_id = "12345"
      config.fb_app_id.should eq("12345")
    end

    it "can set og_type" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.og_type = "website"
      config.og_type.should eq("website")
    end
  end

  describe "full scenario" do
    it "generates complete meta tags for a blog post" do
      config = Hwaro::Models::OpenGraphConfig.new
      config.default_image = "/images/default-og.png"
      config.twitter_card = "summary_large_image"
      config.twitter_site = "@myblog"
      config.twitter_creator = "@author"
      config.fb_app_id = "1234567890"
      config.og_type = "article"

      combined = config.all_tags(
        title: "How to Build a Static Site",
        description: "Learn how to create a fast static site with Hwaro.",
        url: "/blog/how-to-build/",
        image: "/images/blog/how-to-build-cover.png",
        base_url: "https://myblog.com"
      )

      # OG tags
      combined.should contain(%(<meta property="og:title" content="How to Build a Static Site">))
      combined.should contain(%(<meta property="og:type" content="article">))
      combined.should contain(%(<meta property="og:url" content="https://myblog.com/blog/how-to-build/">))
      combined.should contain(%(<meta property="og:description" content="Learn how to create a fast static site with Hwaro.">))
      combined.should contain(%(<meta property="og:image" content="https://myblog.com/images/blog/how-to-build-cover.png">))
      combined.should contain(%(<meta property="fb:app_id" content="1234567890">))

      # Twitter tags
      combined.should contain(%(<meta name="twitter:card" content="summary_large_image">))
      combined.should contain(%(<meta name="twitter:title" content="How to Build a Static Site">))
      combined.should contain(%(<meta name="twitter:description" content="Learn how to create a fast static site with Hwaro.">))
      combined.should contain(%(<meta name="twitter:image" content="https://myblog.com/images/blog/how-to-build-cover.png">))
      combined.should contain(%(<meta name="twitter:site" content="@myblog">))
      combined.should contain(%(<meta name="twitter:creator" content="@author">))
    end
  end
end

describe Hwaro::Models::BuildHooksConfig do
  describe "#initialize" do
    it "has empty pre and post arrays by default" do
      config = Hwaro::Models::BuildHooksConfig.new
      config.pre.should eq([] of String)
      config.post.should eq([] of String)
    end
  end

  describe "property setters" do
    it "can set pre hooks" do
      config = Hwaro::Models::BuildHooksConfig.new
      config.pre = ["npm install", "npx tsc"]
      config.pre.should eq(["npm install", "npx tsc"])
    end

    it "can set post hooks" do
      config = Hwaro::Models::BuildHooksConfig.new
      config.post = ["npm run minify", "./deploy.sh"]
      config.post.should eq(["npm run minify", "./deploy.sh"])
    end

    it "can append to pre hooks" do
      config = Hwaro::Models::BuildHooksConfig.new
      config.pre << "echo pre1"
      config.pre << "echo pre2"
      config.pre.size.should eq(2)
    end

    it "can append to post hooks" do
      config = Hwaro::Models::BuildHooksConfig.new
      config.post << "echo post1"
      config.post << "echo post2"
      config.post.size.should eq(2)
    end
  end
end

describe Hwaro::Models::BuildConfig do
  describe "#initialize" do
    it "has default hooks config" do
      config = Hwaro::Models::BuildConfig.new
      config.hooks.should_not be_nil
      config.hooks.pre.should eq([] of String)
      config.hooks.post.should eq([] of String)
    end
  end

  describe "property setters" do
    it "can set hooks" do
      config = Hwaro::Models::BuildConfig.new
      hooks = Hwaro::Models::BuildHooksConfig.new
      hooks.pre = ["npm ci"]
      hooks.post = ["./scripts/deploy.sh"]
      config.hooks = hooks

      config.hooks.pre.should eq(["npm ci"])
      config.hooks.post.should eq(["./scripts/deploy.sh"])
    end
  end
end

describe Hwaro::Models::MarkdownConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::MarkdownConfig.new
      config.safe.should be_false
      config.lazy_loading.should be_false
    end
  end

  describe "property setters" do
    it "can set safe mode" do
      config = Hwaro::Models::MarkdownConfig.new
      config.safe = true
      config.safe.should be_true
    end

    it "can set lazy_loading" do
      config = Hwaro::Models::MarkdownConfig.new
      config.lazy_loading = true
      config.lazy_loading.should be_true
    end
  end
end

describe Hwaro::Models::LanguageConfig do
  describe "#initialize" do
    it "initializes with code" do
      config = Hwaro::Models::LanguageConfig.new("ko")
      config.code.should eq("ko")
      config.language_name.should eq("ko")
      config.weight.should eq(1)
      config.generate_feed.should be_true
      config.build_search_index.should be_true
      config.taxonomies.should eq(["tags", "categories"])
    end
  end

  describe "property setters" do
    it "can set language_name" do
      config = Hwaro::Models::LanguageConfig.new("ko")
      config.language_name = "한국어"
      config.language_name.should eq("한국어")
    end

    it "can set weight" do
      config = Hwaro::Models::LanguageConfig.new("ko")
      config.weight = 2
      config.weight.should eq(2)
    end

    it "can set generate_feed" do
      config = Hwaro::Models::LanguageConfig.new("en")
      config.generate_feed = true
      config.generate_feed.should be_true
    end

    it "can set build_search_index" do
      config = Hwaro::Models::LanguageConfig.new("en")
      config.build_search_index = true
      config.build_search_index.should be_true
    end

    it "can set taxonomies" do
      config = Hwaro::Models::LanguageConfig.new("en")
      config.taxonomies = ["tags", "categories"]
      config.taxonomies.should eq(["tags", "categories"])
    end
  end
end

describe Hwaro::Models::TaxonomyConfig do
  describe "#initialize" do
    it "initializes with name" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.name.should eq("tags")
      config.feed.should be_false
      config.sitemap.should be_true
      config.paginate_by.should be_nil
    end
  end

  describe "property setters" do
    it "can set feed" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.feed = true
      config.feed.should be_true
    end

    it "can set sitemap" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.sitemap = false
      config.sitemap.should be_false
    end

    it "can set paginate_by" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.paginate_by = 20
      config.paginate_by.should eq(20)
    end

    it "can set paginate_by to nil" do
      config = Hwaro::Models::TaxonomyConfig.new("tags")
      config.paginate_by = 20
      config.paginate_by = nil
      config.paginate_by.should be_nil
    end
  end
end

describe Hwaro::Models::PaginationConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::PaginationConfig.new
      config.enabled.should be_false
      config.per_page.should eq(10)
    end
  end

  describe "property setters" do
    it "can set enabled" do
      config = Hwaro::Models::PaginationConfig.new
      config.enabled = true
      config.enabled.should be_true
    end

    it "can set per_page" do
      config = Hwaro::Models::PaginationConfig.new
      config.per_page = 25
      config.per_page.should eq(25)
    end
  end
end

describe Hwaro::Models::FeedConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::FeedConfig.new
      config.enabled.should be_false
      config.filename.should eq("")
      config.type.should eq("rss")
      config.truncate.should eq(0)
      config.limit.should eq(10)
      config.sections.should eq([] of String)
    end
  end

  describe "property setters" do
    it "can set enabled" do
      config = Hwaro::Models::FeedConfig.new
      config.enabled = true
      config.enabled.should be_true
    end

    it "can set filename" do
      config = Hwaro::Models::FeedConfig.new
      config.filename = "atom.xml"
      config.filename.should eq("atom.xml")
    end

    it "can set type" do
      config = Hwaro::Models::FeedConfig.new
      config.type = "atom"
      config.type.should eq("atom")
    end

    it "can set truncate" do
      config = Hwaro::Models::FeedConfig.new
      config.truncate = 200
      config.truncate.should eq(200)
    end

    it "can set limit" do
      config = Hwaro::Models::FeedConfig.new
      config.limit = 50
      config.limit.should eq(50)
    end

    it "can set sections" do
      config = Hwaro::Models::FeedConfig.new
      config.sections = ["blog", "news"]
      config.sections.should eq(["blog", "news"])
    end
  end
end

describe Hwaro::Models::LlmsConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::LlmsConfig.new
      config.enabled.should be_true
      config.filename.should eq("llms.txt")
      config.instructions.should eq("")
      config.full_enabled.should be_false
      config.full_filename.should eq("llms-full.txt")
    end
  end

  describe "property setters" do
    it "can set enabled" do
      config = Hwaro::Models::LlmsConfig.new
      config.enabled = true
      config.enabled.should be_true
    end

    it "can set filename" do
      config = Hwaro::Models::LlmsConfig.new
      config.filename = "ai.txt"
      config.filename.should eq("ai.txt")
    end

    it "can set instructions" do
      config = Hwaro::Models::LlmsConfig.new
      config.instructions = "This is an AI-friendly site."
      config.instructions.should eq("This is an AI-friendly site.")
    end

    it "can set full_enabled" do
      config = Hwaro::Models::LlmsConfig.new
      config.full_enabled = true
      config.full_enabled.should be_true
    end

    it "can set full_filename" do
      config = Hwaro::Models::LlmsConfig.new
      config.full_filename = "llms-complete.txt"
      config.full_filename.should eq("llms-complete.txt")
    end
  end
end

describe Hwaro::Models::SitemapConfig do
  describe "#initialize" do
    it "has correct default values" do
      config = Hwaro::Models::SitemapConfig.new
      config.enabled.should be_false
      config.filename.should eq("sitemap.xml")
      config.changefreq.should eq("weekly")
      config.priority.should eq(0.5)
    end
  end

  describe "property setters" do
    it "can set enabled" do
      config = Hwaro::Models::SitemapConfig.new
      config.enabled = true
      config.enabled.should be_true
    end

    it "can set filename" do
      config = Hwaro::Models::SitemapConfig.new
      config.filename = "custom-sitemap.xml"
      config.filename.should eq("custom-sitemap.xml")
    end

    it "can set changefreq" do
      config = Hwaro::Models::SitemapConfig.new
      config.changefreq = "daily"
      config.changefreq.should eq("daily")
    end

    it "can set priority" do
      config = Hwaro::Models::SitemapConfig.new
      config.priority = 0.8
      config.priority.should eq(0.8)
    end
  end
end
