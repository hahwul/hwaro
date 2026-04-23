require "../spec_helper"

# =============================================================================
# Front matter parsing tests
#
# These tests verify that the Markdown processor correctly parses front matter
# in both TOML (+++) and YAML (---) formats, including edge cases that could
# cause site breakage if mishandled (extra fields, missing fields, malformed
# input, special characters, etc.).
# =============================================================================

describe Hwaro::Content::Processors::Markdown do
  processor = Hwaro::Content::Processors::Markdown.new

  # ---------------------------------------------------------------------------
  # TOML front matter
  # ---------------------------------------------------------------------------
  describe "TOML front matter parsing" do
    it "parses basic TOML fields" do
      raw = <<-MD
        +++
        title = "My Post"
        draft = false
        +++
        Content here
        MD

      result = processor.parse(raw)
      result[:title].should eq("My Post")
      result[:draft].should be_false
      result[:content].should contain("Content here")
    end

    it "parses description and image" do
      raw = <<-MD
        +++
        title = "Post"
        description = "A brief summary"
        image = "/images/hero.jpg"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:description].should eq("A brief summary")
      result[:image].should eq("/images/hero.jpg")
    end

    it "parses tags array" do
      raw = <<-MD
        +++
        title = "Post"
        tags = ["crystal", "programming", "web"]
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq(["crystal", "programming", "web"])
    end

    it "parses aliases array" do
      raw = <<-MD
        +++
        title = "Post"
        aliases = ["/old-url/", "/legacy/page/"]
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:aliases].should eq(["/old-url/", "/legacy/page/"])
    end

    it "parses date field" do
      raw = <<-MD
        +++
        title = "Post"
        date = "2024-06-15"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
    end

    it "parses updated field" do
      raw = <<-MD
        +++
        title = "Post"
        date = "2024-01-01"
        updated = "2024-06-15"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:updated].should_not be_nil
    end

    it "parses toc field" do
      raw = <<-MD
        +++
        title = "Doc"
        toc = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:toc].should be_true
    end

    it "parses render = false" do
      raw = <<-MD
        +++
        title = "Hidden"
        render = false
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:render].should be_false
    end

    it "parses in_sitemap = false" do
      raw = <<-MD
        +++
        title = "NoSitemap"
        in_sitemap = false
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:in_sitemap].should be_false
    end

    it "parses slug field" do
      raw = <<-MD
        +++
        title = "Original Title"
        slug = "custom-slug"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:slug].should eq("custom-slug")
    end

    it "parses path field (custom path)" do
      raw = <<-MD
        +++
        title = "Post"
        path = "/archive/2024/my-post/"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:custom_path].should eq("/archive/2024/my-post/")
    end

    it "parses template field" do
      raw = <<-MD
        +++
        title = "Special"
        template = "landing"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:template].should eq("landing")
    end

    it "parses redirect_to field" do
      raw = <<-MD
        +++
        title = "Redirect"
        redirect_to = "/new-location/"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:redirect_to].should eq("/new-location/")
    end

    it "parses weight field" do
      raw = <<-MD
        +++
        title = "Weighted"
        weight = 42
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:weight].should eq(42)
    end

    it "parses authors array" do
      raw = <<-MD
        +++
        title = "Post"
        authors = ["alice", "bob"]
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:authors].should eq(["alice", "bob"])
    end

    it "parses in_search_index = false" do
      raw = <<-MD
        +++
        title = "NoSearch"
        in_search_index = false
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:in_search_index].should be_false
    end

    it "parses insert_anchor_links = true" do
      raw = <<-MD
        +++
        title = "Anchored"
        insert_anchor_links = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:insert_anchor_links].should be_true
    end

    it "parses transparent = true (section property)" do
      raw = <<-MD
        +++
        title = "2024"
        transparent = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:transparent].should be_true
    end

    it "parses generate_feeds = true" do
      raw = <<-MD
        +++
        title = "Blog"
        generate_feeds = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:generate_feeds].should be_true
    end

    it "parses paginate and pagination_enabled" do
      raw = <<-MD
        +++
        title = "Section"
        paginate = 10
        pagination_enabled = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:paginate].should eq(10)
      result[:pagination_enabled].should be_true
    end

    it "parses sort_by and reverse" do
      raw = <<-MD
        +++
        title = "Section"
        sort_by = "weight"
        reverse = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:sort_by].should eq("weight")
      result[:reverse].should be_true
    end

    it "parses page_template field" do
      raw = <<-MD
        +++
        title = "Section"
        page_template = "blog_post"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:page_template].should eq("blog_post")
    end

    it "parses paginate_path field" do
      raw = <<-MD
        +++
        title = "Section"
        paginate_path = "p"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:paginate_path].should eq("p")
    end

    it "extracts extra fields from [extra] table" do
      raw = <<-MD
        +++
        title = "Post"

        [extra]
        custom_field = "hello"
        custom_bool = true
        custom_int = 99
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:extra].has_key?("extra").should be_true
      # The extra should contain "custom_field" within the nested structure
      # Since [extra] is parsed as a TOML subtable, it becomes extra["extra"]
    end

    it "extracts top-level extra fields not in known keys" do
      raw = <<-MD
        +++
        title = "Post"
        my_custom_key = "custom_value"
        another_key = true
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:extra].has_key?("my_custom_key").should be_true
      result[:extra].has_key?("another_key").should be_true
    end

    it "extracts taxonomies from front matter" do
      raw = <<-MD
        +++
        title = "Post"
        tags = ["crystal", "web"]
        categories = ["tech", "programming"]
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:taxonomies].has_key?("tags").should be_true
      result[:taxonomies]["tags"].should eq(["crystal", "web"])
      result[:taxonomies].has_key?("categories").should be_true
      result[:taxonomies]["categories"].should eq(["tech", "programming"])
    end

    it "returns front_matter_keys" do
      raw = <<-MD
        +++
        title = "Post"
        draft = false
        tags = ["a"]
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:front_matter_keys].should contain("title")
      result[:front_matter_keys].should contain("draft")
      result[:front_matter_keys].should contain("tags")
    end
  end

  # ---------------------------------------------------------------------------
  # YAML front matter
  # ---------------------------------------------------------------------------
  describe "YAML front matter parsing" do
    it "parses basic YAML fields" do
      raw = <<-MD
        ---
        title: My Post
        draft: false
        ---
        Content here
        MD

      result = processor.parse(raw)
      result[:title].should eq("My Post")
      result[:draft].should be_false
      result[:content].should contain("Content here")
    end

    it "parses description and image" do
      raw = <<-MD
        ---
        title: Post
        description: A brief summary
        image: /images/hero.jpg
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:description].should eq("A brief summary")
      result[:image].should eq("/images/hero.jpg")
    end

    it "parses tags array" do
      raw = <<-MD
        ---
        title: Post
        tags:
          - crystal
          - programming
          - web
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq(["crystal", "programming", "web"])
    end

    it "parses inline tags array" do
      raw = <<-MD
        ---
        title: Post
        tags: [crystal, web]
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq(["crystal", "web"])
    end

    it "parses aliases array" do
      raw = <<-MD
        ---
        title: Post
        aliases:
          - /old-url/
          - /legacy/page/
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:aliases].should eq(["/old-url/", "/legacy/page/"])
    end

    it "parses date field" do
      raw = <<-MD
        ---
        title: Post
        date: "2024-06-15"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
    end

    it "parses toc field" do
      raw = <<-MD
        ---
        title: Doc
        toc: true
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:toc].should be_true
    end

    it "parses render: false" do
      raw = <<-MD
        ---
        title: Hidden
        render: false
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:render].should be_false
    end

    it "parses slug field" do
      raw = <<-MD
        ---
        title: Original
        slug: custom-slug
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:slug].should eq("custom-slug")
    end

    it "parses redirect_to field" do
      raw = <<-MD
        ---
        title: Redirect
        redirect_to: /new-location/
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:redirect_to].should eq("/new-location/")
    end

    it "parses weight field" do
      raw = <<-MD
        ---
        title: Weighted
        weight: 42
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:weight].should eq(42)
    end

    it "parses authors array" do
      raw = <<-MD
        ---
        title: Post
        authors:
          - alice
          - bob
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:authors].should eq(["alice", "bob"])
    end

    it "parses transparent and generate_feeds" do
      raw = <<-MD
        ---
        title: Section
        transparent: true
        generate_feeds: true
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:transparent].should be_true
      result[:generate_feeds].should be_true
    end

    it "parses paginate and pagination_enabled" do
      raw = <<-MD
        ---
        title: Section
        paginate: 5
        pagination_enabled: true
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:paginate].should eq(5)
      result[:pagination_enabled].should be_true
    end

    it "parses sort_by and reverse" do
      raw = <<-MD
        ---
        title: Section
        sort_by: title
        reverse: true
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:sort_by].should eq("title")
      result[:reverse].should be_true
    end

    it "extracts YAML extra fields not in known keys" do
      raw = <<-MD
        ---
        title: Post
        my_custom_key: custom_value
        another_key: true
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:extra].has_key?("my_custom_key").should be_true
      result[:extra].has_key?("another_key").should be_true
    end

    it "extracts taxonomies from YAML front matter" do
      raw = <<-MD
        ---
        title: Post
        tags:
          - crystal
          - web
        categories:
          - tech
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:taxonomies].has_key?("tags").should be_true
      result[:taxonomies]["tags"].should eq(["crystal", "web"])
      result[:taxonomies].has_key?("categories").should be_true
      result[:taxonomies]["categories"].should eq(["tech"])
    end
  end

  # ---------------------------------------------------------------------------
  # JSON front matter ({...} balanced at file start)
  # ---------------------------------------------------------------------------
  describe "JSON front matter parsing" do
    it "parses basic JSON fields" do
      raw = <<-MD
        {
          "title": "My JSON Post",
          "draft": false
        }

        Content here
        MD

      result = processor.parse(raw)
      result[:title].should eq("My JSON Post")
      result[:draft].should be_false
      result[:content].should contain("Content here")
    end

    it "parses description and image" do
      raw = <<-MD
        {"title": "Post", "description": "A brief summary", "image": "/images/hero.jpg"}

        Body
        MD

      result = processor.parse(raw)
      result[:description].should eq("A brief summary")
      result[:image].should eq("/images/hero.jpg")
    end

    it "parses tags array" do
      raw = <<-MD
        {"title": "Tagged", "tags": ["crystal", "web"]}

        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq(["crystal", "web"])
      result[:taxonomies].has_key?("tags").should be_true
      result[:taxonomies]["tags"].should eq(["crystal", "web"])
    end

    it "parses integer and boolean fields" do
      raw = <<-MD
        {"title": "P", "weight": 5, "toc": true, "draft": true}

        Body
        MD

      result = processor.parse(raw)
      result[:weight].should eq(5)
      result[:toc].should be_true
      result[:draft].should be_true
    end

    it "parses date as ISO string" do
      raw = <<-MD
        {"title": "Dated", "date": "2024-01-15"}

        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
      result[:date].not_nil!.year.should eq(2024)
    end

    it "captures unknown keys into extra" do
      raw = <<-MD
        {"title": "P", "custom_field": "hello", "rating": 4}

        Body
        MD

      result = processor.parse(raw)
      result[:extra]["custom_field"].should eq("hello")
      result[:extra]["rating"].should eq(4_i64)
    end

    it "handles nested braces inside string values" do
      raw = <<-MD
        {"title": "Tricky {nested}", "description": "a } b { c"}

        Body
        MD

      result = processor.parse(raw)
      result[:title].should eq("Tricky {nested}")
      result[:description].should eq("a } b { c")
    end

    it "handles escaped quotes inside strings" do
      raw = %({"title": "She said \\"hi\\"", "description": "x"}\n\nBody\n)

      result = processor.parse(raw)
      result[:title].should eq(%(She said "hi"))
    end

    it "leaves content untouched when file does not start with {" do
      # Leading whitespace means the { is not at byte 0, so this is not a JSON
      # frontmatter block — parser should fall through to the no-frontmatter path.
      raw = " {\"not\": \"frontmatter\"}\n\nBody\n"

      result = processor.parse(raw)
      result[:title].should eq("Untitled")
      result[:content].should contain("Body")
    end

    it "extracts non-taxonomy-keyword arrays into taxonomies" do
      raw = <<-MD
        {"title": "P", "tags": ["a"], "categories": ["tech"]}

        Body
        MD

      result = processor.parse(raw)
      result[:taxonomies]["tags"].should eq(["a"])
      result[:taxonomies]["categories"].should eq(["tech"])
    end
  end

  # ---------------------------------------------------------------------------
  # Default values (no front matter or missing fields)
  # ---------------------------------------------------------------------------
  describe "default values" do
    it "uses 'Untitled' when title is missing" do
      raw = <<-MD
        ---
        draft: false
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:title].should eq("Untitled")
    end

    it "defaults draft to false" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:draft].should be_false
    end

    it "defaults render to true" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:render].should be_true
    end

    it "defaults in_sitemap to true" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:in_sitemap].should be_true
    end

    it "defaults toc to false" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:toc].should be_false
    end

    it "defaults weight to 0" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:weight].should eq(0)
    end

    it "defaults in_search_index to true" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:in_search_index].should be_true
    end

    it "defaults insert_anchor_links to false" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:insert_anchor_links].should be_false
    end

    it "defaults paginate_path to 'page'" do
      raw = <<-MD
        ---
        title: Section
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:paginate_path].should eq("page")
    end

    it "defaults tags to empty array" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq([] of String)
    end

    it "defaults aliases to empty array" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:aliases].should eq([] of String)
    end

    it "defaults authors to empty array" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:authors].should eq([] of String)
    end

    it "defaults extra to empty hash" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:extra].empty?.should be_true
    end

    it "defaults description to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:description].should be_nil
    end

    it "defaults image to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:image].should be_nil
    end

    it "defaults date to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should be_nil
    end

    it "defaults slug to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:slug].should be_nil
    end

    it "defaults custom_path to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:custom_path].should be_nil
    end

    it "defaults redirect_to to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:redirect_to].should be_nil
    end

    it "defaults transparent to false" do
      raw = <<-MD
        ---
        title: Section
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:transparent].should be_false
    end

    it "defaults generate_feeds to false" do
      raw = <<-MD
        ---
        title: Section
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:generate_feeds].should be_false
    end

    it "defaults paginate to nil" do
      raw = <<-MD
        ---
        title: Section
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:paginate].should be_nil
    end

    it "defaults pagination_enabled to nil" do
      raw = <<-MD
        ---
        title: Section
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:pagination_enabled].should be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # No front matter at all
  # ---------------------------------------------------------------------------
  describe "content without front matter" do
    it "returns default values and treats entire content as body" do
      raw = "# Hello World\n\nJust content, no front matter."

      result = processor.parse(raw)
      result[:title].should eq("Untitled")
      result[:draft].should be_false
      result[:content].should contain("# Hello World")
      result[:content].should contain("Just content, no front matter.")
    end

    it "handles empty string input" do
      result = processor.parse("")
      result[:title].should eq("Untitled")
      result[:content].should eq("")
    end

    it "handles whitespace-only input" do
      result = processor.parse("   \n\n  \n")
      result[:title].should eq("Untitled")
    end
  end

  # ---------------------------------------------------------------------------
  # Malformed front matter recovery
  # ---------------------------------------------------------------------------
  describe "malformed front matter" do
    it "raises HWARO_E_CONTENT for invalid TOML when a file path is given" do
      raw = <<-MD
        +++
        title = "Valid"
        invalid_syntax :::
        +++
        Body content
        MD

      err = expect_raises(Hwaro::HwaroError) do
        processor.parse(raw, "test.md")
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
      err.exit_code.should eq(5)
      (err.message || "").should contain("test.md")
    end

    it "raises HWARO_E_CONTENT for invalid YAML when a file path is given" do
      raw = <<-MD
        ---
        title: Valid
        invalid: [unterminated
        ---
        Body content
        MD

      err = expect_raises(Hwaro::HwaroError) do
        processor.parse(raw, "test.md")
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
      err.exit_code.should eq(5)
      (err.message || "").should contain("test.md")
    end

    it "falls back to defaults when no file path is given (library use)" do
      raw_toml = <<-MD
        +++
        title = "Valid"
        invalid_syntax :::
        +++
        Body content
        MD
      result = processor.parse(raw_toml)
      # Library-style invocation preserves the previous graceful behaviour
      result[:content].should contain("Body content")

      raw_yaml = <<-MD
        ---
        title: Valid
        invalid: [unterminated
        ---
        Body content
        MD
      result = processor.parse(raw_yaml)
      result[:content].should contain("Body content")
    end

    it "handles TOML front matter with empty body" do
      raw = <<-MD
        +++
        title = "Empty Body"
        +++
        MD

      result = processor.parse(raw)
      result[:title].should eq("Empty Body")
    end

    it "handles YAML front matter with empty body" do
      raw = <<-MD
        ---
        title: Empty Body
        ---
        MD

      result = processor.parse(raw)
      result[:title].should eq("Empty Body")
    end
  end

  # ---------------------------------------------------------------------------
  # Special characters and Unicode
  # ---------------------------------------------------------------------------
  describe "special characters in front matter" do
    it "handles Unicode title in YAML" do
      raw = <<-MD
        ---
        title: 안녕하세요
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:title].should eq("안녕하세요")
    end

    it "handles Unicode title in TOML" do
      raw = <<-MD
        +++
        title = "日本語のタイトル"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:title].should eq("日本語のタイトル")
    end

    it "handles title with quotes in YAML" do
      raw = <<-MD
        ---
        title: "Title with 'single' and inner quotes"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:title].should contain("single")
    end

    it "handles title with special markdown characters" do
      raw = <<-MD
        ---
        title: "Title with # and * and [brackets]"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:title].should contain("#")
      result[:title].should contain("*")
    end

    it "handles description with HTML entities" do
      raw = <<-MD
        ---
        title: Post
        description: "Desc with <b>bold</b> & ampersands"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:description].not_nil!.should contain("<b>bold</b>")
      result[:description].not_nil!.should contain("&")
    end

    it "handles empty tags array in YAML" do
      raw = <<-MD
        ---
        title: Post
        tags: []
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq([] of String)
    end

    it "handles empty tags array in TOML" do
      raw = <<-MD
        +++
        title = "Post"
        tags = []
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:tags].should eq([] of String)
    end

    it "handles empty authors array in YAML" do
      raw = <<-MD
        ---
        title: Post
        authors: []
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:authors].should eq([] of String)
    end

    it "handles empty aliases array in TOML" do
      raw = <<-MD
        +++
        title = "Post"
        aliases = []
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:aliases].should eq([] of String)
    end
  end

  # ---------------------------------------------------------------------------
  # Content body extraction
  # ---------------------------------------------------------------------------
  describe "content body extraction" do
    it "separates TOML front matter from content body" do
      raw = "+++\ntitle = \"Test\"\n+++\nLine 1\nLine 2\nLine 3"

      result = processor.parse(raw)
      result[:title].should eq("Test")
      result[:content].should contain("Line 1")
      result[:content].should contain("Line 2")
      result[:content].should contain("Line 3")
      result[:content].should_not contain("+++")
      result[:content].should_not contain("title")
    end

    it "separates YAML front matter from content body" do
      raw = "---\ntitle: Test\n---\nLine 1\nLine 2\nLine 3"

      result = processor.parse(raw)
      result[:title].should eq("Test")
      result[:content].should contain("Line 1")
      result[:content].should contain("Line 2")
      result[:content].should contain("Line 3")
      result[:content].should_not contain("---")
    end

    it "preserves markdown formatting in content body" do
      raw = <<-MD
        ---
        title: Test
        ---
        # Heading

        **Bold** and *italic* text.

        - List item 1
        - List item 2

        ```
        code block
        ```
        MD

      result = processor.parse(raw)
      result[:content].should contain("# Heading")
      result[:content].should contain("**Bold**")
      result[:content].should contain("- List item 1")
    end
  end

  # ---------------------------------------------------------------------------
  # Combined fields (comprehensive TOML)
  # ---------------------------------------------------------------------------
  describe "comprehensive TOML front matter" do
    it "parses all supported fields together" do
      raw = <<-MD
        +++
        title = "Complete Post"
        description = "Full description"
        image = "/img/cover.jpg"
        draft = false
        date = "2024-06-15"
        updated = "2024-07-01"
        toc = true
        render = true
        in_sitemap = true
        slug = "complete"
        weight = 10
        tags = ["crystal", "test"]
        aliases = ["/old/"]
        authors = ["alice"]
        in_search_index = true
        insert_anchor_links = true
        redirect_to = ""
        +++
        Full body content here.
        MD

      result = processor.parse(raw)
      result[:title].should eq("Complete Post")
      result[:description].should eq("Full description")
      result[:image].should eq("/img/cover.jpg")
      result[:draft].should be_false
      result[:date].should_not be_nil
      result[:updated].should_not be_nil
      result[:toc].should be_true
      result[:render].should be_true
      result[:in_sitemap].should be_true
      result[:slug].should eq("complete")
      result[:weight].should eq(10)
      result[:tags].should eq(["crystal", "test"])
      result[:aliases].should eq(["/old/"])
      result[:authors].should eq(["alice"])
      result[:in_search_index].should be_true
      result[:insert_anchor_links].should be_true
      result[:content].should contain("Full body content here.")
    end
  end

  # ---------------------------------------------------------------------------
  # Combined fields (comprehensive YAML)
  # ---------------------------------------------------------------------------
  describe "comprehensive YAML front matter" do
    it "parses all supported fields together" do
      raw = <<-MD
        ---
        title: Complete Post
        description: Full description
        image: /img/cover.jpg
        draft: false
        date: "2024-06-15"
        updated: "2024-07-01"
        toc: true
        render: true
        in_sitemap: true
        slug: complete
        weight: 10
        tags:
          - crystal
          - test
        aliases:
          - /old/
        authors:
          - alice
        in_search_index: true
        insert_anchor_links: true
        ---
        Full body content here.
        MD

      result = processor.parse(raw)
      result[:title].should eq("Complete Post")
      result[:description].should eq("Full description")
      result[:image].should eq("/img/cover.jpg")
      result[:draft].should be_false
      result[:date].should_not be_nil
      result[:updated].should_not be_nil
      result[:toc].should be_true
      result[:render].should be_true
      result[:in_sitemap].should be_true
      result[:slug].should eq("complete")
      result[:weight].should eq(10)
      result[:tags].should eq(["crystal", "test"])
      result[:aliases].should eq(["/old/"])
      result[:authors].should eq(["alice"])
      result[:in_search_index].should be_true
      result[:insert_anchor_links].should be_true
      result[:content].should contain("Full body content here.")
    end
  end

  # ---------------------------------------------------------------------------
  # Series and expires fields
  # ---------------------------------------------------------------------------
  describe "series and expires fields" do
    it "parses series from TOML" do
      raw = <<-MD
        +++
        title = "Part 1"
        series = "My Tutorial"
        series_weight = 1
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:series].should eq("My Tutorial")
      result[:series_weight].should eq(1)
    end

    it "parses series from YAML" do
      raw = <<-MD
        ---
        title: Part 2
        series: My Tutorial
        series_weight: 2
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:series].should eq("My Tutorial")
      result[:series_weight].should eq(2)
    end

    it "defaults series to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:series].should be_nil
      result[:series_weight].should eq(0)
    end

    it "parses expires from TOML" do
      raw = <<-MD
        +++
        title = "Expiring"
        expires = "2025-12-31"
        +++
        Body
        MD

      result = processor.parse(raw)
      result[:expires].should_not be_nil
      result[:expires].not_nil!.year.should eq(2025)
    end

    it "parses expires from YAML" do
      raw = <<-MD
        ---
        title: Expiring
        expires: "2025-06-30"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:expires].should_not be_nil
      result[:expires].not_nil!.month.should eq(6)
    end

    it "defaults expires to nil" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:expires].should be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Date parsing edge cases
  # ---------------------------------------------------------------------------
  describe "date parsing" do
    it "parses ISO 8601 date" do
      raw = <<-MD
        ---
        title: Post
        date: "2024-01-15"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
      result[:date].not_nil!.year.should eq(2024)
      result[:date].not_nil!.month.should eq(1)
      result[:date].not_nil!.day.should eq(15)
    end

    it "parses date with time component" do
      raw = <<-MD
        ---
        title: Post
        date: "2024-06-15T10:30:00"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
      result[:date].not_nil!.year.should eq(2024)
    end

    it "handles nil date gracefully" do
      raw = <<-MD
        ---
        title: Post
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should be_nil
    end

    it "parses RFC 3339 date with timezone" do
      raw = <<-MD
        ---
        title: Post
        date: "2024-06-15T10:30:00+09:00"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
      result[:date].not_nil!.year.should eq(2024)
      result[:date].not_nil!.month.should eq(6)
    end

    it "parses RFC 3339 date with Z timezone" do
      raw = <<-MD
        ---
        title: Post
        date: "2024-01-01T00:00:00Z"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
      result[:date].not_nil!.year.should eq(2024)
    end

    it "parses date with space-separated time" do
      raw = <<-MD
        ---
        title: Post
        date: "2024-06-15 14:30:00"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should_not be_nil
      result[:date].not_nil!.hour.should eq(14)
    end

    it "handles empty date string gracefully" do
      raw = <<-MD
        ---
        title: Post
        date: ""
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should be_nil
    end

    it "handles invalid date string gracefully" do
      raw = <<-MD
        ---
        title: Post
        date: "not-a-date"
        ---
        Body
        MD

      result = processor.parse(raw)
      result[:date].should be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Anchor links and TOC
  # ---------------------------------------------------------------------------
  describe "render_with_anchors" do
    it "inserts anchor links before heading content" do
      content = "# Hello World"
      html, _toc = processor.render_with_anchors(content, anchor_style: "before")
      html.should contain("anchor")
      html.should contain("href=\"#hello-world\"")
    end

    it "inserts anchor links after heading content" do
      content = "# Hello World"
      html, _toc = processor.render_with_anchors(content, anchor_style: "after")
      html.should contain("anchor")
      html.should contain("href=\"#hello-world\"")
    end

    it "does not insert anchors with default heading style" do
      content = "# Hello World"
      html, _toc = processor.render_with_anchors(content, anchor_style: "heading")
      html.should_not contain("class=\"anchor\"")
    end

    it "returns TOC headers" do
      content = "# H1\n## H2\n### H3"
      _html, toc = processor.render_with_anchors(content)
      toc.size.should be >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # TOC with duplicate heading IDs
  # ---------------------------------------------------------------------------
  describe "TOC duplicate heading IDs" do
    it "generates unique IDs for duplicate headings" do
      content = "## Section\n\nContent\n\n## Section\n\nMore content\n\n## Section"
      html, _toc = Hwaro::Processor::Markdown.render(content)
      # All three headings should have unique IDs
      html.should contain("id=\"section\"")
      html.should contain("id=\"section-1\"")
      html.should contain("id=\"section-2\"")
    end

    it "builds nested TOC tree" do
      content = "## Parent\n\n### Child\n\n## Sibling"
      _html, toc = Hwaro::Processor::Markdown.render(content)
      toc.size.should eq(2)             # Parent and Sibling at top level
      toc[0].children.size.should eq(1) # Child under Parent
    end
  end

  # ---------------------------------------------------------------------------
  # Markdown render edge cases
  # ---------------------------------------------------------------------------
  describe "render edge cases" do
    it "handles content with no headings or images" do
      content = "Just a simple paragraph."
      html, toc = Hwaro::Processor::Markdown.render(content)
      html.should contain("simple paragraph")
      toc.should be_empty
    end

    it "handles empty content" do
      _html, toc = Hwaro::Processor::Markdown.render("")
      toc.should be_empty
    end

    it "handles content with only inline HTML" do
      content = "Hello <strong>world</strong>"
      html, _toc = Hwaro::Processor::Markdown.render(content)
      html.should contain("<strong>world</strong>")
    end
  end
end
