require "../spec_helper"

private def config_with(permalinks : Hash(String, String), default_language : String = "en") : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.permalinks = permalinks
  config.default_language = default_language
  config
end

private def resolve(
  path : String,
  config : Hwaro::Models::Config?,
  slug : String? = nil,
  custom_path : String? = nil,
  language : String? = nil,
  date : Time? = nil,
  title : String = "",
) : String
  Hwaro::Utils::PermalinkResolver.resolve_url(
    path, config,
    slug: slug, custom_path: custom_path, language: language,
    date: date, title: title,
  )
end

describe Hwaro::Utils::PermalinkResolver do
  describe ".pattern?" do
    it "detects a :token segment" do
      Hwaro::Utils::PermalinkResolver.pattern?("/:year/:month/:slug/").should be_true
      Hwaro::Utils::PermalinkResolver.pattern?(":year/:slug").should be_true
    end

    it "treats plain directory targets as remaps" do
      Hwaro::Utils::PermalinkResolver.pattern?("archive/2023").should be_false
      Hwaro::Utils::PermalinkResolver.pattern?("").should be_false
    end

    it "detects a token buried in a compound segment" do
      # These are not expandable (see validate_pattern!), but they must be seen
      # as patterns so they get rejected instead of shipping a literal colon.
      Hwaro::Utils::PermalinkResolver.pattern?("/:year/post-:slug/").should be_true
      Hwaro::Utils::PermalinkResolver.pattern?("/blog-:slug/").should be_true
    end

    # A colon is legal inside a URL path segment. Treating any `:identifier`
    # as a token made a plain directory remap look like a malformed pattern,
    # and `validate_pattern!` aborted the build with HWARO_E_CONFIG on config
    # that had published fine — for a target containing no hwaro token at all.
    it "treats a colon inside a segment as a literal remap, not a token" do
      Hwaro::Utils::PermalinkResolver.pattern?("/wiki/pros:cons/").should be_false
      Hwaro::Utils::PermalinkResolver.pattern?("notes/a:b").should be_false
      # `:slugs` is not `:slug` — the embedded match is closed with \b.
      Hwaro::Utils::PermalinkResolver.pattern?("/docs/faq:slugs/").should be_false
    end
  end

  describe ".validate_pattern!" do
    it "accepts every valid token" do
      Hwaro::Utils::PermalinkResolver.validate_pattern!(
        "posts", "/:year/:month/:day/:slug/:title/:section/:filename/"
      )
    end

    it "raises a classified config error for an unknown token" do
      ex = expect_raises(Hwaro::HwaroError, /Unknown token ':yaer'/) do
        Hwaro::Utils::PermalinkResolver.validate_pattern!("posts", "/:yaer/:slug/")
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end

    it "raises a classified config error for a token mixed into a segment" do
      # expand_pattern substitutes whole segments only, so `post-:slug` used to
      # sail through both checks and ship a directory literally named
      # `post-:slug` (illegal on NTFS, unescaped in the URLs pointing at it).
      ex = expect_raises(Hwaro::HwaroError, /'post-:slug'/) do
        Hwaro::Utils::PermalinkResolver.validate_pattern!("posts", "/:year/post-:slug/")
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (ex.hint || "").should contain("whole path segments")

      expect_raises(Hwaro::HwaroError, /'blog-:slug'/) do
        Hwaro::Utils::PermalinkResolver.validate_pattern!("blog", "/blog-:slug/")
      end
    end

    it "accepts a literal colon inside a segment" do
      # Control for the check above: only a KNOWN token embedded in a larger
      # segment is a mistake. `cons` is not a token, so this is a directory.
      Hwaro::Utils::PermalinkResolver.validate_pattern!("notes", "/wiki/pros:cons/")
      Hwaro::Utils::PermalinkResolver.validate_pattern!("docs", "/docs/faq:slugs/")
    end
  end

  describe ".resolve_url with token patterns" do
    it "expands date tokens with zero padding" do
      config = config_with({"posts" => ":year/:month/:day/:slug"})
      url = resolve("posts/hello.md", config, date: Time.utc(2026, 3, 5))
      url.should eq("/2026/03/05/hello/")
    end

    it "prefers the front-matter slug for :slug" do
      config = config_with({"posts" => ":year/:slug"})
      url = resolve("posts/long-file-name.md", config, slug: "short", date: Time.utc(2026, 3, 5))
      url.should eq("/2026/short/")
    end

    it "does not re-slugify the filename for :slug" do
      config = config_with({"posts" => ":slug"})
      resolve("posts/Hello_World.md", config).should eq("/Hello_World/")
    end

    it "slugifies the page title for :title" do
      config = config_with({"posts" => ":title"})
      resolve("posts/x.md", config, title: "Hello World! 안녕").should eq("/hello-world-안녕/")
    end

    it "falls back to the :slug value when the title slugifies to empty" do
      config = config_with({"posts" => ":title"})
      resolve("posts/fallback-name.md", config, title: "!!!").should eq("/fallback-name/")
      resolve("posts/fallback-name.md", config, title: "!!!", slug: "sluggy").should eq("/sluggy/")
    end

    it "expands :section to the page's directory path" do
      config = config_with({"posts" => ":section/:year/:slug"})
      url = resolve("posts/tech/deep.md", config, date: Time.utc(2026, 1, 2))
      url.should eq("/posts/tech/2026/deep/")
    end

    it "collapses an empty :section instead of emitting //" do
      # An empty source is a pattern-only catch-all, so root-level pages
      # (whose section is empty) can flow through :section patterns.
      config = config_with({"" => ":section/:slug"})
      resolve("root-page.md", config).should eq("/root-page/")
      resolve("deep/nested-page.md", config).should eq("/deep/nested-page/")
    end

    it "expands :filename to the file stem even when a slug is set" do
      config = config_with({"posts" => ":filename"})
      resolve("posts/original.md", config, slug: "overridden").should eq("/original/")
    end

    it "keeps literal segments in the pattern" do
      config = config_with({"posts" => "blog/:year/:slug"})
      url = resolve("posts/x.md", config, date: Time.utc(2026, 3, 5))
      url.should eq("/blog/2026/x/")
    end

    it "matches subdirectories under the rule source as a prefix" do
      config = config_with({"posts" => ":year/:slug"})
      url = resolve("posts/tech/nested.md", config, date: Time.utc(2025, 12, 31))
      url.should eq("/2025/nested/")
    end

    it "honors the first matching rule" do
      config = config_with({
        "posts"      => ":year/:slug",
        "posts/tech" => "never/:slug",
      })
      url = resolve("posts/tech/x.md", config, date: Time.utc(2026, 3, 5))
      url.should eq("/2026/x/")
    end

    it "prefixes the language before the pattern output" do
      config = config_with({"posts" => ":year/:month/:day/:slug"})
      url = resolve("posts/x.ko.md", config, language: "ko", date: Time.utc(2026, 3, 5))
      url.should eq("/ko/2026/03/05/x/")
    end

    it "does not prefix the default language" do
      config = config_with({"posts" => ":year/:slug"})
      url = resolve("posts/x.md", config, language: "en", date: Time.utc(2026, 3, 5))
      url.should eq("/2026/x/")
    end

    it "lets custom_path win over a pattern rule" do
      config = config_with({"posts" => ":year/:slug"})
      url = resolve("posts/x.md", config, custom_path: "/pinned/here/", date: Time.utc(2026, 3, 5))
      url.should eq("/pinned/here/")
    end

    it "skips pattern rules for section index pages" do
      config = config_with({"posts" => ":year/:slug"})
      resolve("posts/_index.md", config).should eq("/posts/")
    end

    it "skips pattern rules for bundle index pages" do
      config = config_with({"posts" => ":year/:slug"})
      resolve("posts/my-post/index.md", config).should eq("/posts/my-post/")
    end

    it "lets an index page fall through a pattern rule to a later remap" do
      config = config_with({
        "blog"      => ":year/:slug",
        "blog/news" => "news",
      })
      resolve("blog/news/_index.md", config).should eq("/news/")
    end

    it "keeps an empty-source plain remap inert" do
      config = config_with({"" => "archive"})
      resolve("a.md", config).should eq("/a/")
      resolve("blog/a.md", config).should eq("/blog/a/")
    end

    it "raises a classified content error when a date token has no date" do
      config = config_with({"posts" => ":year/:month/:slug"})
      ex = expect_raises(Hwaro::HwaroError, /posts\/undated\.md matches \[permalinks\] rule "posts" \(pattern ':year\/:month\/:slug'\) which requires a date/) do
        resolve("posts/undated.md", config)
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
      ex.hint.should_not be_nil
    end

    it "raises a classified config error for an unvalidated unknown token" do
      config = config_with({"posts" => ":bogus/:slug"})
      ex = expect_raises(Hwaro::HwaroError, /Unknown token ':bogus'/) do
        resolve("posts/x.md", config)
      end
      ex.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end
  end

  describe ".resolve_url_lenient" do
    it "falls back to the directory URL and reports when a date token has no date" do
      config = config_with({"posts" => ":year/:month/:slug"})
      url, error = Hwaro::Utils::PermalinkResolver.resolve_url_lenient(
        "posts/undated.md", config,
        slug: nil, custom_path: nil, language: nil, date: nil, title: "",
      )
      url.should eq("/posts/undated/")
      error.not_nil!.should contain("requires a date, but the page has none")
    end

    it "returns no error when the date is present" do
      config = config_with({"posts" => ":year/:slug"})
      url, error = Hwaro::Utils::PermalinkResolver.resolve_url_lenient(
        "posts/x.md", config,
        slug: nil, custom_path: nil, language: nil, date: Time.utc(2026, 3, 5), title: "",
      )
      url.should eq("/2026/x/")
      error.should be_nil
    end

    it "still raises for unknown tokens (config errors are never deferred)" do
      config = config_with({"posts" => ":bogus/:slug"})
      expect_raises(Hwaro::HwaroError, /Unknown token ':bogus'/) do
        Hwaro::Utils::PermalinkResolver.resolve_url_lenient(
          "posts/x.md", config,
          slug: nil, custom_path: nil, language: nil, date: nil, title: "",
        )
      end
    end
  end

  describe ".resolve_url with plain remaps" do
    it "keeps directory-remap semantics for plain targets" do
      config = config_with({"old/posts" => "archive"})
      resolve("old/posts/2024/a.md", config).should eq("/archive/2024/a/")
    end

    it "returns the untouched URL when no rule matches" do
      config = config_with({"old/posts" => "archive"})
      resolve("blog/a.md", config).should eq("/blog/a/")
    end

    it "handles a nil config" do
      resolve("blog/a.md", nil).should eq("/blog/a/")
    end
  end

  # Regression: `slug` is documented as "Custom URL slug", but index pages
  # skipped it entirely — so converting a page to bundle layout (which is what
  # `hwaro new --bundle` and multilingual siblings produce) silently reverted
  # its URL to the directory name with no warning.
  describe ".resolve_url with a bundle slug" do
    it "renames the leaf bundle's own segment" do
      resolve("blog/my-post/index.md", nil, slug: "renamed").should eq("/blog/renamed/")
    end

    it "renames a top-level leaf bundle" do
      resolve("my-post/index.md", nil, slug: "renamed").should eq("/renamed/")
    end

    it "leaves section indexes alone so their children stay under them" do
      resolve("blog/_index.md", nil, slug: "renamed").should eq("/blog/")
    end

    it "never moves the homepage" do
      resolve("index.md", nil, slug: "renamed").should eq("/")
    end

    it "keeps the directory name when no slug is set" do
      resolve("blog/my-post/index.md", nil).should eq("/blog/my-post/")
    end

    it "prefixes the language before the renamed segment" do
      config = config_with({} of String => String)
      resolve("blog/my-post/index.ko.md", config, slug: "renamed", language: "ko")
        .should eq("/ko/blog/renamed/")
    end

    it "renames the segment the remap moved it to" do
      config = config_with({"old" => "archive"})
      resolve("old/my-post/index.md", config, slug: "renamed").should eq("/archive/renamed/")
    end
  end
end
