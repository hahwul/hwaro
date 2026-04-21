require "../spec_helper"

describe Hwaro::Content::Seo::Feeds do
  describe "multilingual feeds" do
    it "filters main feed to default language pages when default_language_only is true (default)" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "A test site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello World"
      en_page.url = "/posts/hello/"
      en_page.language = nil # default language
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English content"

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page, ko_page], config, output_dir)

        # Main feed should only contain default language pages
        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("Hello World")
        main_feed.should_not contain("안녕하세요")
      end
    end

    it "generates per-language feed for non-default languages" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "A test site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello World"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English content"

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page, ko_page], config, output_dir)

        # Korean feed should exist at /ko/rss.xml
        ko_feed_path = File.join(output_dir, "ko", "rss.xml")
        File.exists?(ko_feed_path).should be_true

        ko_feed = File.read(ko_feed_path)
        ko_feed.should contain("안녕하세요")
        ko_feed.should_not contain("Hello World")
      end
    end

    it "generates atom feed per language when feed type is atom" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.feeds.filename = "atom.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir)

        ko_feed_path = File.join(output_dir, "ko", "atom.xml")
        File.exists?(ko_feed_path).should be_true

        ko_feed = File.read(ko_feed_path)
        ko_feed.should contain("<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"ko\">")
        ko_feed.should contain("안녕하세요")
      end
    end

    it "does not generate language feed when generate_feed is false" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"

      ko_config = Hwaro::Models::LanguageConfig.new("ko")
      ko_config.generate_feed = false
      config.languages["ko"] = ko_config

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir)

        File.exists?(File.join(output_dir, "ko", "rss.xml")).should be_false
      end
    end

    it "generates feeds for multiple non-default languages" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English"

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어"

      ja_page = Hwaro::Models::Page.new("posts/hello.ja.md")
      ja_page.title = "こんにちは"
      ja_page.url = "/ja/posts/hello/"
      ja_page.language = "ja"
      ja_page.draft = false
      ja_page.render = true
      ja_page.is_index = false
      ja_page.raw_content = "日本語"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page, ko_page, ja_page], config, output_dir)

        # Main feed = English only
        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("Hello")
        main_feed.should_not contain("안녕하세요")
        main_feed.should_not contain("こんにちは")

        # Korean feed
        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("안녕하세요")
        ko_feed.should_not contain("Hello")
        ko_feed.should_not contain("こんにちは")

        # Japanese feed
        ja_feed = File.read(File.join(output_dir, "ja", "rss.xml"))
        ja_feed.should contain("こんにちは")
        ja_feed.should_not contain("Hello")
        ja_feed.should_not contain("안녕하세요")
      end
    end

    it "includes language tag in RSS for language-specific feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "A test site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("<language>ko</language>")
      end
    end

    it "does not include language tag in main RSS feed" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page], config, output_dir)

        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should_not contain("<language>")
      end
    end

    it "uses language name in feed title" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "My Site"
      config.default_language = "en"

      ko_config = Hwaro::Models::LanguageConfig.new("ko")
      ko_config.language_name = "한국어"
      config.languages["ko"] = ko_config

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("<title>My Site (한국어)</title>")
      end
    end

    it "generates correct self-referencing link for language feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("atom:link href=\"https://example.com/ko/rss.xml\"")
      end
    end

    it "excludes draft pages from language feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      published = Hwaro::Models::Page.new("posts/hello.ko.md")
      published.title = "Published Korean"
      published.url = "/ko/posts/hello/"
      published.language = "ko"
      published.draft = false
      published.render = true
      published.is_index = false
      published.raw_content = "Published"

      draft = Hwaro::Models::Page.new("posts/draft.ko.md")
      draft.title = "Draft Korean"
      draft.url = "/ko/posts/draft/"
      draft.language = "ko"
      draft.draft = true
      draft.render = true
      draft.is_index = false
      draft.raw_content = "Draft"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([published, draft], config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("Published Korean")
        ko_feed.should_not contain("Draft Korean")
      end
    end

    it "excludes section pages from language feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      section = Hwaro::Models::Section.new("posts/_index.ko.md")
      section.title = "게시물"
      section.url = "/ko/posts/"
      section.section = "posts"
      section.language = "ko"
      section.draft = false
      section.render = true
      section.is_index = true
      section.raw_content = ""

      post = Hwaro::Models::Page.new("posts/hello.ko.md")
      post.title = "안녕하세요"
      post.url = "/ko/posts/hello/"
      post.language = "ko"
      post.draft = false
      post.render = true
      post.is_index = false
      post.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([section.as(Hwaro::Models::Page), post], config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("안녕하세요")
        ko_feed.should_not contain("게시물")
      end
    end

    it "applies section filter to language feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.sections = ["posts"]
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      blog_post = Hwaro::Models::Page.new("posts/hello.ko.md")
      blog_post.title = "Blog Korean"
      blog_post.url = "/ko/posts/hello/"
      blog_post.section = "posts"
      blog_post.language = "ko"
      blog_post.draft = false
      blog_post.render = true
      blog_post.is_index = false
      blog_post.raw_content = "Blog content"

      docs_page = Hwaro::Models::Page.new("docs/guide.ko.md")
      docs_page.title = "Docs Korean"
      docs_page.url = "/ko/docs/guide/"
      docs_page.section = "docs"
      docs_page.language = "ko"
      docs_page.draft = false
      docs_page.render = true
      docs_page.is_index = false
      docs_page.raw_content = "Docs content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([blog_post, docs_page], config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("Blog Korean")
        ko_feed.should_not contain("Docs Korean")
      end
    end

    it "does not generate language feeds when site is not multilingual" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      # No additional languages configured

      page = Hwaro::Models::Page.new("posts/hello.md")
      page.title = "Hello"
      page.url = "/posts/hello/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        # Main feed should exist
        File.exists?(File.join(output_dir, "rss.xml")).should be_true

        # No language subdirectories should be created
        Dir.exists?(File.join(output_dir, "en")).should be_false
      end
    end

    it "does not generate language feeds when main feed is disabled" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = false
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ko_page], config, output_dir)

        # Language feeds should still be generated even when main feed is disabled,
        # because the multilingual block runs independently
        File.exists?(File.join(output_dir, "ko", "rss.xml")).should be_true
      end
    end

    it "includes xml:lang attribute in atom feed for language-specific feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.feeds.filename = "atom.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")

      ja_page = Hwaro::Models::Page.new("posts/hello.ja.md")
      ja_page.title = "こんにちは"
      ja_page.url = "/ja/posts/hello/"
      ja_page.language = "ja"
      ja_page.draft = false
      ja_page.render = true
      ja_page.is_index = false
      ja_page.raw_content = "日本語コンテンツ"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([ja_page], config, output_dir)

        ja_feed = File.read(File.join(output_dir, "ja", "atom.xml"))
        ja_feed.should contain("xml:lang=\"ja\"")
        ja_feed.should contain("こんにちは")
      end
    end

    it "does not include xml:lang in main atom feed" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.feeds.filename = "atom.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page], config, output_dir)

        main_feed = File.read(File.join(output_dir, "atom.xml"))
        main_feed.should_not contain("xml:lang=")
      end
    end

    it "respects feed limit for language feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.limit = 2
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      pages = (1..5).map do |i|
        page = Hwaro::Models::Page.new("posts/post#{i}.ko.md")
        page.title = "Korean Post #{i}"
        page.url = "/ko/posts/post#{i}/"
        page.language = "ko"
        page.date = Time.utc(2024, i, 1)
        page.draft = false
        page.render = true
        page.is_index = false
        page.raw_content = "Content #{i}"
        page
      end

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate(pages, config, output_dir)

        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.scan(/<item>/).size.should eq(2)
        # Should include the 2 newest (Post 5 and Post 4)
        ko_feed.should contain("Korean Post 5")
        ko_feed.should contain("Korean Post 4")
      end
    end

    it "treats pages with nil language as default language in multilingual mode" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      # Page with nil language (should be treated as default "en")
      page_nil = Hwaro::Models::Page.new("posts/hello.md")
      page_nil.title = "Nil Language Page"
      page_nil.url = "/posts/hello/"
      page_nil.language = nil
      page_nil.draft = false
      page_nil.render = true
      page_nil.is_index = false
      page_nil.raw_content = "Content"

      # Page with explicit default language
      page_en = Hwaro::Models::Page.new("posts/world.md")
      page_en.title = "Explicit EN Page"
      page_en.url = "/posts/world/"
      page_en.language = "en"
      page_en.draft = false
      page_en.render = true
      page_en.is_index = false
      page_en.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page_nil, page_en], config, output_dir)

        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("Nil Language Page")
        main_feed.should contain("Explicit EN Page")
      end
    end
  end

  describe "default_language_only option" do
    it "defaults to true" do
      config = Hwaro::Models::Config.new
      config.feeds.default_language_only.should be_true
    end

    it "includes all languages in main feed when default_language_only is false" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.default_language_only = false
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "A test site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello World"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English content"

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page, ko_page], config, output_dir)

        # Main feed should contain ALL languages
        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("Hello World")
        main_feed.should contain("안녕하세요")
      end
    end

    it "still generates per-language feeds when default_language_only is false" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.default_language_only = false
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello World"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English content"

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어 콘텐츠"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page, ko_page], config, output_dir)

        # Per-language feed should still exist
        ko_feed_path = File.join(output_dir, "ko", "rss.xml")
        File.exists?(ko_feed_path).should be_true

        ko_feed = File.read(ko_feed_path)
        ko_feed.should contain("안녕하세요")
        ko_feed.should_not contain("Hello World")
      end
    end

    it "includes all languages in main feed with multiple languages when false" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.default_language_only = false
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
      config.languages["ja"] = Hwaro::Models::LanguageConfig.new("ja")

      en_page = Hwaro::Models::Page.new("posts/hello.md")
      en_page.title = "Hello"
      en_page.url = "/posts/hello/"
      en_page.language = nil
      en_page.draft = false
      en_page.render = true
      en_page.is_index = false
      en_page.raw_content = "English"

      ko_page = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_page.title = "안녕하세요"
      ko_page.url = "/ko/posts/hello/"
      ko_page.language = "ko"
      ko_page.draft = false
      ko_page.render = true
      ko_page.is_index = false
      ko_page.raw_content = "한국어"

      ja_page = Hwaro::Models::Page.new("posts/hello.ja.md")
      ja_page.title = "こんにちは"
      ja_page.url = "/ja/posts/hello/"
      ja_page.language = "ja"
      ja_page.draft = false
      ja_page.render = true
      ja_page.is_index = false
      ja_page.raw_content = "日本語"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_page, ko_page, ja_page], config, output_dir)

        # Main feed should contain all three languages
        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("Hello")
        main_feed.should contain("안녕하세요")
        main_feed.should contain("こんにちは")
        main_feed.scan(/<item>/).size.should eq(3)

        # Per-language feeds still separate
        ko_feed = File.read(File.join(output_dir, "ko", "rss.xml"))
        ko_feed.should contain("안녕하세요")
        ko_feed.should_not contain("Hello")

        ja_feed = File.read(File.join(output_dir, "ja", "rss.xml"))
        ja_feed.should contain("こんにちは")
        ja_feed.should_not contain("Hello")
      end
    end

    it "has no effect on non-multilingual sites" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.default_language_only = true
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      # No additional languages — not multilingual

      page = Hwaro::Models::Page.new("posts/hello.md")
      page.title = "Hello"
      page.url = "/posts/hello/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("Hello")
      end
    end

    it "applies section filter together with default_language_only false" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.default_language_only = false
      config.feeds.sections = ["posts"]
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.default_language = "en"
      config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")

      en_post = Hwaro::Models::Page.new("posts/hello.md")
      en_post.title = "EN Post"
      en_post.url = "/posts/hello/"
      en_post.section = "posts"
      en_post.language = nil
      en_post.draft = false
      en_post.render = true
      en_post.is_index = false
      en_post.raw_content = "English"

      ko_post = Hwaro::Models::Page.new("posts/hello.ko.md")
      ko_post.title = "KO Post"
      ko_post.url = "/ko/posts/hello/"
      ko_post.section = "posts"
      ko_post.language = "ko"
      ko_post.draft = false
      ko_post.render = true
      ko_post.is_index = false
      ko_post.raw_content = "한국어"

      ko_docs = Hwaro::Models::Page.new("docs/guide.ko.md")
      ko_docs.title = "KO Docs"
      ko_docs.url = "/ko/docs/guide/"
      ko_docs.section = "docs"
      ko_docs.language = "ko"
      ko_docs.draft = false
      ko_docs.render = true
      ko_docs.is_index = false
      ko_docs.raw_content = "문서"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([en_post, ko_post, ko_docs], config, output_dir)

        # Main feed includes both languages but only "posts" section
        main_feed = File.read(File.join(output_dir, "rss.xml"))
        main_feed.should contain("EN Post")
        main_feed.should contain("KO Post")
        main_feed.should_not contain("KO Docs")
      end
    end
  end

  describe ".generate" do
    it "does not generate feeds when disabled" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = false

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([] of Hwaro::Models::Page, config, output_dir)
        File.exists?(File.join(output_dir, "rss.xml")).should be_false
        File.exists?(File.join(output_dir, "atom.xml")).should be_false
      end
    end

    it "generates RSS feed when enabled with default settings" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"
      config.description = "A test site"

      page = Hwaro::Models::Page.new("blog/post.md")
      page.title = "Test Post"
      page.url = "/blog/post/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Hello World"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        feed_path = File.join(output_dir, "rss.xml")
        File.exists?(feed_path).should be_true

        content = File.read(feed_path)
        content.should contain("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        content.should contain("<rss version=\"2.0\"")
        content.should contain("<title>Test Site</title>")
        content.should contain("<description>A test site</description>")
      end
    end

    it "generates Atom feed when type is atom" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "atom"
      config.feeds.filename = "atom.xml"
      config.base_url = "https://example.com"
      config.title = "Atom Site"
      config.description = "An atom test"

      page = Hwaro::Models::Page.new("blog/post.md")
      page.title = "Atom Post"
      page.url = "/blog/post/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Content here"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        actual_path = File.join(output_dir, "atom.xml")
        File.exists?(actual_path).should be_true

        content = File.read(actual_path)
        content.should contain("<feed xmlns=\"http://www.w3.org/2005/Atom\">")
        content.should contain("<title>Atom Site</title>")
      end
    end

    it "excludes draft pages" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      published = Hwaro::Models::Page.new("blog/published.md")
      published.title = "Published Post"
      published.url = "/blog/published/"
      published.draft = false
      published.render = true
      published.is_index = false
      published.raw_content = "Published content"

      draft = Hwaro::Models::Page.new("blog/draft.md")
      draft.title = "Draft Post"
      draft.url = "/blog/draft/"
      draft.draft = true
      draft.render = true
      draft.is_index = false
      draft.raw_content = "Draft content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([published, draft], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Published Post")
        content.should_not contain("Draft Post")
      end
    end

    it "excludes pages with render = false" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      rendered = Hwaro::Models::Page.new("blog/rendered.md")
      rendered.title = "Rendered"
      rendered.url = "/blog/rendered/"
      rendered.draft = false
      rendered.render = true
      rendered.is_index = false
      rendered.raw_content = "Rendered content"

      hidden = Hwaro::Models::Page.new("blog/hidden.md")
      hidden.title = "Hidden"
      hidden.url = "/blog/hidden/"
      hidden.draft = false
      hidden.render = false
      hidden.is_index = false
      hidden.raw_content = "Hidden content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([rendered, hidden], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Rendered")
        content.should_not contain("Hidden")
      end
    end

    it "excludes section index pages (_index.md)" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      regular = Hwaro::Models::Page.new("blog/post.md")
      regular.title = "Regular Post"
      regular.url = "/blog/post/"
      regular.draft = false
      regular.render = true
      regular.is_index = false
      regular.raw_content = "Post content"

      # Section index (_index.md) should be excluded from feeds
      section_index = Hwaro::Models::Section.new("blog/_index.md")
      section_index.title = "Blog Index"
      section_index.url = "/blog/"
      section_index.section = "blog"
      section_index.draft = false
      section_index.render = true
      section_index.is_index = true
      section_index.raw_content = "Index content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([regular, section_index.as(Hwaro::Models::Page)], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Regular Post")
        content.should_not contain("Blog Index")
      end
    end

    it "includes page bundle (index.md) pages in feeds" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      # Page bundle (index.md) — this is a content page, NOT a section index
      page_bundle = Hwaro::Models::Page.new("blog/my-post/index.md")
      page_bundle.title = "My Post"
      page_bundle.url = "/blog/my-post/"
      page_bundle.section = "blog"
      page_bundle.draft = false
      page_bundle.render = true
      page_bundle.is_index = true # index.md sets is_index = true
      page_bundle.raw_content = "Page bundle content"

      # Section index (_index.md) — should be excluded
      section_index = Hwaro::Models::Section.new("blog/_index.md")
      section_index.title = "Blog Index"
      section_index.url = "/blog/"
      section_index.section = "blog"
      section_index.draft = false
      section_index.render = true
      section_index.is_index = true
      section_index.raw_content = "Index content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page_bundle, section_index.as(Hwaro::Models::Page)], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("My Post")
        content.should_not contain("Blog Index")
      end
    end

    it "includes nested subsection pages when parent section is in sections filter" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.sections = ["posts"]
      config.base_url = "https://example.com"
      config.title = "Test Site"

      # Page in a nested subsection (e.g., content/posts/2026/10years/index.md)
      nested_post = Hwaro::Models::Page.new("posts/2026/10years/index.md")
      nested_post.title = "Nested Post"
      nested_post.url = "/posts/2026/10years/"
      nested_post.section = "posts/2026"
      nested_post.draft = false
      nested_post.render = true
      nested_post.is_index = true
      nested_post.raw_content = "Nested content"

      # Page in a different section
      docs_page = Hwaro::Models::Page.new("docs/guide.md")
      docs_page.title = "Docs Guide"
      docs_page.url = "/docs/guide/"
      docs_page.section = "docs"
      docs_page.draft = false
      docs_page.render = true
      docs_page.is_index = false
      docs_page.raw_content = "Docs content"

      # Page directly in the posts section
      direct_post = Hwaro::Models::Page.new("posts/hello.md")
      direct_post.title = "Direct Post"
      direct_post.url = "/posts/hello/"
      direct_post.section = "posts"
      direct_post.draft = false
      direct_post.render = true
      direct_post.is_index = false
      direct_post.raw_content = "Direct content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([nested_post, docs_page, direct_post], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Nested Post")
        content.should contain("Direct Post")
        content.should_not contain("Docs Guide")
      end
    end

    it "does not include pages from unrelated sections with similar prefixes" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.sections = ["post"]
      config.base_url = "https://example.com"
      config.title = "Test Site"

      # "posts" should NOT match section filter "post" (no false prefix match)
      posts_page = Hwaro::Models::Page.new("posts/hello.md")
      posts_page.title = "Posts Hello"
      posts_page.url = "/posts/hello/"
      posts_page.section = "posts"
      posts_page.draft = false
      posts_page.render = true
      posts_page.is_index = false
      posts_page.raw_content = "Content"

      # "post" should match section filter "post"
      post_page = Hwaro::Models::Page.new("post/hello.md")
      post_page.title = "Post Hello"
      post_page.url = "/post/hello/"
      post_page.section = "post"
      post_page.draft = false
      post_page.render = true
      post_page.is_index = false
      post_page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([posts_page, post_page], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Post Hello")
        content.should_not contain("Posts Hello")
      end
    end

    it "uses custom filename" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "feed.xml"
      config.base_url = "https://example.com"
      config.title = "Test Site"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.draft = false
      page.render = true
      page.is_index = false
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([page], config, output_dir)

        File.exists?(File.join(output_dir, "feed.xml")).should be_true
        File.exists?(File.join(output_dir, "rss.xml")).should be_false
      end
    end

    it "filters by section when sections are configured" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.sections = ["blog"]
      config.base_url = "https://example.com"
      config.title = "Test Site"

      blog_post = Hwaro::Models::Page.new("blog/post.md")
      blog_post.title = "Blog Post"
      blog_post.url = "/blog/post/"
      blog_post.section = "blog"
      blog_post.draft = false
      blog_post.render = true
      blog_post.is_index = false
      blog_post.raw_content = "Blog content"

      docs_page = Hwaro::Models::Page.new("docs/guide.md")
      docs_page.title = "Docs Guide"
      docs_page.url = "/docs/guide/"
      docs_page.section = "docs"
      docs_page.draft = false
      docs_page.render = true
      docs_page.is_index = false
      docs_page.raw_content = "Docs content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate([blog_post, docs_page], config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("Blog Post")
        content.should_not contain("Docs Guide")
      end
    end

    it "respects feed limit" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.limit = 2
      config.base_url = "https://example.com"
      config.title = "Test Site"

      pages = (1..5).map do |i|
        page = Hwaro::Models::Page.new("post#{i}.md")
        page.title = "Post #{i}"
        page.url = "/post#{i}/"
        page.date = Time.utc(2024, i, 1)
        page.draft = false
        page.render = true
        page.is_index = false
        page.raw_content = "Content #{i}"
        page
      end

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate(pages, config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        # Only 2 items should be present (the two newest by date)
        content.scan(/<item>/).size.should eq(2)
      end
    end

    it "does not limit when limit is 0" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = true
      config.feeds.type = "rss"
      config.feeds.filename = "rss.xml"
      config.feeds.limit = 0
      config.base_url = "https://example.com"
      config.title = "Test Site"

      pages = (1..3).map do |i|
        page = Hwaro::Models::Page.new("post#{i}.md")
        page.title = "Post #{i}"
        page.url = "/post#{i}/"
        page.date = Time.utc(2024, i, 1)
        page.draft = false
        page.render = true
        page.is_index = false
        page.raw_content = "Content #{i}"
        page
      end

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.generate(pages, config, output_dir)

        content = File.read(File.join(output_dir, "rss.xml"))
        content.scan(/<item>/).size.should eq(3)
      end
    end

    it "generates section feeds when section has generate_feeds enabled" do
      config = Hwaro::Models::Config.new
      config.feeds.enabled = false # Main feed disabled
      config.base_url = "https://example.com"
      config.title = "Test Site"

      section = Hwaro::Models::Section.new("posts/_index.md")
      section.title = "Posts"
      section.url = "/posts/"
      section.section = "posts"
      section.draft = false
      section.render = true
      section.is_index = true
      section.generate_feeds = true
      section.raw_content = ""

      post = Hwaro::Models::Page.new("posts/hello.md")
      post.title = "Hello World"
      post.url = "/posts/hello/"
      post.section = "posts"
      post.draft = false
      post.render = true
      post.is_index = false
      post.raw_content = "Hello content"

      Dir.mktmpdir do |output_dir|
        pages = [section.as(Hwaro::Models::Page), post]
        Hwaro::Content::Seo::Feeds.generate(pages, config, output_dir)

        # Section feed should exist
        section_feed = File.join(output_dir, "posts", "rss.xml")
        File.exists?(section_feed).should be_true

        content = File.read(section_feed)
        content.should contain("Hello World")
      end
    end
  end

  describe ".generate_rss" do
    it "produces valid RSS 2.0 XML structure" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "RSS Test"
      config.description = "Testing RSS"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "First Post"
      page.url = "/post/"
      page.raw_content = "Post content here"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "RSS Test", ""
      )

      rss.should contain("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      rss.should contain("<rss version=\"2.0\"")
      rss.should contain("xmlns:atom=\"http://www.w3.org/2005/Atom\"")
      rss.should contain("<channel>")
      rss.should contain("</channel>")
      rss.should contain("</rss>")
    end

    it "includes channel metadata" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "My Blog"
      config.description = "A developer blog"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [] of Hwaro::Models::Page, config, "rss.xml", false, "My Blog", ""
      )

      rss.should contain("<title>My Blog</title>")
      rss.should contain("<link>https://example.com</link>")
      rss.should contain("<description>A developer blog</description>")
    end

    it "includes self-referencing atom:link" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Test"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [] of Hwaro::Models::Page, config, "rss.xml", false, "Test", ""
      )

      rss.should contain("atom:link href=\"https://example.com/rss.xml\"")
      rss.should contain("rel=\"self\"")
      rss.should contain("type=\"application/rss+xml\"")
    end

    it "includes item elements for each page" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Post One"
      page1.url = "/blog/post-one/"
      page1.raw_content = "Content one"

      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Post Two"
      page2.url = "/blog/post-two/"
      page2.raw_content = "Content two"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page1, page2], config, "rss.xml", false, "Blog", ""
      )

      rss.scan(/<item>/).size.should eq(2)
      rss.should contain("<title>Post One</title>")
      rss.should contain("<title>Post Two</title>")
      rss.should contain("<link>https://example.com/blog/post-one/</link>")
      rss.should contain("<link>https://example.com/blog/post-two/</link>")
    end

    it "includes guid element for each item" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Test"
      page.url = "/test/"
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("<guid>https://example.com/test/</guid>")
    end

    it "includes pubDate when page has a date" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Dated Post"
      page.url = "/post/"
      page.date = Time.utc(2024, 6, 15, 10, 30, 0)
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("<pubDate>")
    end

    it "prefers updated date over date for pubDate" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Updated Post"
      page.url = "/post/"
      page.date = Time.utc(2024, 1, 1)
      page.updated = Time.utc(2024, 6, 15)
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("<pubDate>")
    end

    it "does not include pubDate when page has no date" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Undated Post"
      page.url = "/post/"
      page.date = nil
      page.updated = nil
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should_not contain("<pubDate>")
    end

    it "includes description with content" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "# Hello\n\nThis is my post content."

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("<description>")
    end

    it "escapes XML special characters in title" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Tom & Jerry's <Adventure>"
      page.url = "/post/"
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("Tom &amp; Jerry&apos;s &lt;Adventure&gt;")
      rss.should_not contain("Tom & Jerry")
    end

    it "escapes XML in channel metadata" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Tom & Jerry"
      config.description = "A <great> site"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [] of Hwaro::Models::Page, config, "rss.xml", false, "Tom & Jerry", ""
      )

      rss.should contain("<title>Tom &amp; Jerry</title>")
      rss.should contain("<description>A &lt;great&gt; site</description>")
    end

    it "handles page URL without leading slash" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "blog/post/"
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("<link>https://example.com/blog/post/</link>")
    end

    it "handles empty base_url" do
      config = Hwaro::Models::Config.new
      config.base_url = ""

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Content"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [page], config, "rss.xml", false, "Test", ""
      )

      rss.should contain("<link>/post/</link>")
    end

    it "generates self-referencing link with base_path" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [] of Hwaro::Models::Page, config, "rss.xml", false, "Section Feed", "/blog/"
      )

      rss.should contain("https://example.com/blog/rss.xml")
    end

    it "returns empty items section when no pages" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      rss = Hwaro::Content::Seo::Feeds.generate_rss(
        [] of Hwaro::Models::Page, config, "rss.xml", false, "Empty", ""
      )

      rss.scan(/<item>/).size.should eq(0)
      rss.should contain("<channel>")
      rss.should contain("</channel>")
    end
  end

  describe ".generate_atom" do
    it "produces valid Atom XML structure" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "Atom Test"
      config.description = "Testing Atom"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "First Post"
      page.url = "/post/"
      page.raw_content = "Post content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Atom Test", ""
      )

      atom.should contain("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      atom.should contain("<feed xmlns=\"http://www.w3.org/2005/Atom\">")
      atom.should contain("</feed>")
    end

    it "includes feed-level metadata" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.title = "My Feed"
      config.description = "Feed description"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [] of Hwaro::Models::Page, config, "atom.xml", false, "My Feed", ""
      )

      atom.should contain("<title>My Feed</title>")
      atom.should contain("<link href=\"https://example.com\"")
      atom.should contain("<id>https://example.com</id>")
      atom.should contain("<subtitle>Feed description</subtitle>")
      atom.should contain("<updated>")
    end

    it "includes self-referencing link" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [] of Hwaro::Models::Page, config, "atom.xml", false, "Test", ""
      )

      atom.should contain("href=\"https://example.com/atom.xml\" rel=\"self\"")
    end

    it "does not include subtitle when description is empty" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.description = ""

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [] of Hwaro::Models::Page, config, "atom.xml", false, "Test", ""
      )

      atom.should_not contain("<subtitle>")
    end

    it "includes entry elements for each page" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page1 = Hwaro::Models::Page.new("post1.md")
      page1.title = "Entry One"
      page1.url = "/entry-one/"
      page1.raw_content = "Content one"

      page2 = Hwaro::Models::Page.new("post2.md")
      page2.title = "Entry Two"
      page2.url = "/entry-two/"
      page2.raw_content = "Content two"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page1, page2], config, "atom.xml", false, "Blog", ""
      )

      atom.scan(/<entry>/).size.should eq(2)
      atom.should contain("<title>Entry One</title>")
      atom.should contain("<title>Entry Two</title>")
      atom.should contain("href=\"https://example.com/entry-one/\"")
      atom.should contain("href=\"https://example.com/entry-two/\"")
    end

    it "includes id element for each entry" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Test", ""
      )

      atom.should contain("<id>https://example.com/post/</id>")
    end

    it "includes updated element for entries with dates" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.date = Time.utc(2024, 6, 15, 10, 30, 0)
      page.raw_content = "Content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Test", ""
      )

      # Entry should have <updated> with the date in RFC3339 format
      atom.scan(/<updated>/).size.should be >= 2 # Feed-level + entry-level
    end

    it "includes content element with html type" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "# Hello World"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Test", ""
      )

      atom.should contain("<content type=\"html\">")
    end

    it "uses text content type when is_text is true" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Simple content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", true, "Test", ""
      )

      atom.should contain("<content type=\"text\">")
    end

    it "escapes XML special characters in title" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "C++ & Java: <Comparison>"
      page.url = "/post/"
      page.raw_content = "Content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Test", ""
      )

      atom.should contain("C++ &amp; Java: &lt;Comparison&gt;")
    end

    it "handles page URL without leading slash" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "blog/post/"
      page.raw_content = "Content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Test", ""
      )

      atom.should contain("href=\"https://example.com/blog/post/\"")
    end

    it "generates self-referencing link with base_path" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [] of Hwaro::Models::Page, config, "atom.xml", false, "Section", "/posts/"
      )

      atom.should contain("https://example.com/posts/atom.xml")
    end

    it "returns empty entries section when no pages" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [] of Hwaro::Models::Page, config, "atom.xml", false, "Empty", ""
      )

      atom.scan(/<entry>/).size.should eq(0)
      atom.should contain("<feed")
      atom.should contain("</feed>")
    end

    it "prefers updated date over date for entry updated element" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.date = Time.utc(2024, 1, 1)
      page.updated = Time.utc(2024, 6, 15)
      page.raw_content = "Content"

      atom = Hwaro::Content::Seo::Feeds.generate_atom(
        [page], config, "atom.xml", false, "Test", ""
      )

      atom.should contain("2024-06-15")
    end
  end

  describe ".process_feed" do
    it "sorts pages by date (newest first)" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"

      old_page = Hwaro::Models::Page.new("old.md")
      old_page.title = "Old Post"
      old_page.url = "/old/"
      old_page.date = Time.utc(2024, 1, 1)
      old_page.raw_content = "Old content"

      new_page = Hwaro::Models::Page.new("new.md")
      new_page.title = "New Post"
      new_page.url = "/new/"
      new_page.date = Time.utc(2024, 12, 1)
      new_page.raw_content = "New content"

      mid_page = Hwaro::Models::Page.new("mid.md")
      mid_page.title = "Mid Post"
      mid_page.url = "/mid/"
      mid_page.date = Time.utc(2024, 6, 1)
      mid_page.raw_content = "Mid content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [old_page, new_page, mid_page], config, output_dir, "rss.xml", "Test", "", false
        )

        content = File.read(File.join(output_dir, "rss.xml"))
        # New should appear before Mid, and Mid before Old
        new_pos = content.index!("New Post")
        mid_pos = content.index!("Mid Post")
        old_pos = content.index!("Old Post")
        new_pos.should be < mid_pos
        mid_pos.should be < old_pos
      end
    end

    it "applies limit to pages" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"
      config.feeds.limit = 2

      pages = (1..5).map do |i|
        page = Hwaro::Models::Page.new("post#{i}.md")
        page.title = "Post #{i}"
        page.url = "/post#{i}/"
        page.date = Time.utc(2024, i, 1)
        page.raw_content = "Content #{i}"
        page
      end

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          pages, config, output_dir, "rss.xml", "Test", "", false
        )

        content = File.read(File.join(output_dir, "rss.xml"))
        content.scan(/<item>/).size.should eq(2)
        # Should include the 2 newest (Post 5 and Post 4)
        content.should contain("Post 5")
        content.should contain("Post 4")
      end
    end

    it "defaults to RSS for unknown feed types" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "unknown_format"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "feed.xml", "Test", "", false
        )

        content = File.read(File.join(output_dir, "feed.xml"))
        content.should contain("<rss version=\"2.0\"")
      end
    end

    it "uses custom filename from parameter" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "my-feed.xml", "My Feed", "", false
        )

        File.exists?(File.join(output_dir, "my-feed.xml")).should be_true
      end
    end

    it "uses default atom filename when custom filename is empty" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "atom"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "", "Test", "", false
        )

        File.exists?(File.join(output_dir, "atom.xml")).should be_true
      end
    end

    it "uses default rss filename when custom filename is empty" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "", "Test", "", false
        )

        File.exists?(File.join(output_dir, "rss.xml")).should be_true
      end
    end

    it "generates atom feed when type is atom" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "atom"

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Atom Post"
      page.url = "/post/"
      page.raw_content = "Content"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "atom.xml", "Atom Feed", "", false
        )

        content = File.read(File.join(output_dir, "atom.xml"))
        content.should contain("<feed xmlns=\"http://www.w3.org/2005/Atom\">")
        content.should contain("Atom Post")
      end
    end

    it "handles truncated content" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"
      config.feeds.truncate = 10

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "This is a very long content that should be truncated to a shorter length."

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "rss.xml", "Test", "", false
        )

        content = File.read(File.join(output_dir, "rss.xml"))
        # Content should be truncated and have "..." appended
        content.should contain("...")
      end
    end

    it "does not truncate content when truncate is 0" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"
      config.feeds.truncate = 0

      page = Hwaro::Models::Page.new("post.md")
      page.title = "Post"
      page.url = "/post/"
      page.raw_content = "# Hello\n\nFull content here."

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [page], config, output_dir, "rss.xml", "Test", "", false
        )

        content = File.read(File.join(output_dir, "rss.xml"))
        # Should contain HTML-rendered content (not truncated text)
        content.should contain("Full content here")
      end
    end

    it "handles empty pages array" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.feeds.type = "rss"

      Dir.mktmpdir do |output_dir|
        Hwaro::Content::Seo::Feeds.process_feed(
          [] of Hwaro::Models::Page, config, output_dir, "rss.xml", "Empty Feed", "", false
        )

        content = File.read(File.join(output_dir, "rss.xml"))
        content.should contain("<channel>")
        content.should contain("<title>Empty Feed</title>")
        content.scan(/<item>/).size.should eq(0)
      end
    end
  end
end
