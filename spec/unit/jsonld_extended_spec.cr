require "../spec_helper"
require "json"

describe Hwaro::Content::Seo::JsonLd do
  describe ".faq_page" do
    it "generates FAQPage JSON-LD from faq_questions/faq_answers" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/faq/"
      page.extra["faq_questions"] = ["What is Hwaro?", "How to install?"].as(String | Bool | Int64 | Float64 | Array(String))
      page.extra["faq_answers"] = ["A static site generator.", "Run crystal build."].as(String | Bool | Int64 | Float64 | Array(String))

      config = Hwaro::Models::Config.new
      result = Hwaro::Content::Seo::JsonLd.faq_page(page, config)

      result.should contain("application/ld+json")
      result.should contain("FAQPage")
      result.should contain("What is Hwaro?")
      result.should contain("A static site generator.")
      result.should contain("How to install?")
    end

    it "generates FAQPage JSON-LD from faq pairs array" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/faq/"
      page.extra["faq"] = ["Q1", "A1", "Q2", "A2"].as(String | Bool | Int64 | Float64 | Array(String))

      config = Hwaro::Models::Config.new
      result = Hwaro::Content::Seo::JsonLd.faq_page(page, config)

      result.should contain("FAQPage")
      result.should contain("Q1")
      result.should contain("A1")
      result.should contain("Q2")
      result.should contain("A2")
    end

    it "returns empty when no FAQ data" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      Hwaro::Content::Seo::JsonLd.faq_page(page, config).should eq("")
    end

    # The documented primary form `[[extra.faq]]` parses to an Array of
    # Hash(String, ExtraValue). Malformed entries (missing answer, or a
    # non-hash element) must be silently dropped, not crash.
    it "builds FAQPage from a table-array hash form, dropping malformed entries" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/faq/"

      arr = [
        {"question" => "A?".as(Hwaro::Models::ExtraValue), "answer" => "B".as(Hwaro::Models::ExtraValue)}.as(Hwaro::Models::ExtraValue),
        {"question" => "C?".as(Hwaro::Models::ExtraValue)}.as(Hwaro::Models::ExtraValue), # missing answer
        "bare-string".as(Hwaro::Models::ExtraValue),                                      # non-hash element
      ] of Hwaro::Models::ExtraValue
      page.extra["faq"] = arr.as(Hwaro::Models::ExtraValue)

      config = Hwaro::Models::Config.new
      result = Hwaro::Content::Seo::JsonLd.faq_page(page, config)

      json_str = result.gsub(/<\/?script[^>]*>/, "")
      json = JSON.parse(json_str)
      json["@type"].as_s.should eq("FAQPage")
      entities = json["mainEntity"].as_a
      entities.size.should eq(1)
      entities[0]["@type"].as_s.should eq("Question")
      entities[0]["name"].as_s.should eq("A?")
      entities[0]["acceptedAnswer"]["text"].as_s.should eq("B")
    end
  end

  describe ".how_to" do
    it "generates HowTo JSON-LD from howto_names/howto_texts" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/tutorial/"
      page.title = "Getting Started"
      page.description = "A tutorial"
      page.extra["howto_names"] = ["Install", "Configure", "Run"].as(String | Bool | Int64 | Float64 | Array(String))
      page.extra["howto_texts"] = ["Run install command.", "Edit config.", "Run build."].as(String | Bool | Int64 | Float64 | Array(String))

      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      result = Hwaro::Content::Seo::JsonLd.how_to(page, config)

      result.should contain("HowTo")
      result.should contain("Getting Started")
      result.should contain("HowToStep")
      result.should contain("Install")
      result.should contain("Run install command.")

      # Parse JSON to verify structure
      json_str = result.gsub(/<\/?script[^>]*>/, "")
      json = JSON.parse(json_str)
      json["@type"].as_s.should eq("HowTo")
      json["step"].as_a.size.should eq(3)
      json["step"].as_a[0]["position"].as_i.should eq(1)
    end

    it "returns empty when no steps data" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      Hwaro::Content::Seo::JsonLd.how_to(page, config).should eq("")
    end

    # The documented primary form `[[extra.howto_steps]]` parses to an Array
    # of Hash(String, ExtraValue). Malformed entries (missing text, or a
    # non-hash element) must be silently dropped, not crash.
    it "builds HowTo from a table-array hash form, dropping malformed entries" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/tutorial/"
      page.title = "Getting Started"

      arr = [
        {"name" => "Install".as(Hwaro::Models::ExtraValue), "text" => "Run install command.".as(Hwaro::Models::ExtraValue)}.as(Hwaro::Models::ExtraValue),
        {"name" => "Configure".as(Hwaro::Models::ExtraValue)}.as(Hwaro::Models::ExtraValue), # missing text
        "bare-string".as(Hwaro::Models::ExtraValue),                                         # non-hash element
      ] of Hwaro::Models::ExtraValue
      page.extra["howto_steps"] = arr.as(Hwaro::Models::ExtraValue)

      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      result = Hwaro::Content::Seo::JsonLd.how_to(page, config)

      json_str = result.gsub(/<\/?script[^>]*>/, "")
      json = JSON.parse(json_str)
      json["@type"].as_s.should eq("HowTo")
      steps = json["step"].as_a
      steps.size.should eq(1)
      steps[0]["@type"].as_s.should eq("HowToStep")
      steps[0]["name"].as_s.should eq("Install")
      steps[0]["text"].as_s.should eq("Run install command.")
    end
  end

  describe ".website" do
    it "generates WebSite JSON-LD" do
      config = Hwaro::Models::Config.new
      config.title = "My Site"
      config.base_url = "https://example.com"
      config.description = "A great site"

      result = Hwaro::Content::Seo::JsonLd.website(config)

      result.should contain("WebSite")
      result.should contain("My Site")
      result.should contain("https://example.com/")
      result.should contain("A great site")
    end

    it "includes SearchAction when search is enabled" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.search.enabled = true

      result = Hwaro::Content::Seo::JsonLd.website(config)

      result.should contain("SearchAction")
      result.should contain("search_term_string")
    end

    it "omits SearchAction when search is disabled" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      config.search.enabled = false

      result = Hwaro::Content::Seo::JsonLd.website(config)

      result.should_not contain("SearchAction")
    end

    it "returns empty when base_url is empty" do
      config = Hwaro::Models::Config.new
      Hwaro::Content::Seo::JsonLd.website(config).should eq("")
    end
  end

  describe ".organization" do
    it "generates Organization JSON-LD" do
      config = Hwaro::Models::Config.new
      config.title = "My Org"
      config.base_url = "https://example.com"
      config.description = "An organization"

      result = Hwaro::Content::Seo::JsonLd.organization(config)

      result.should contain("Organization")
      result.should contain("My Org")
      result.should contain("https://example.com/")
    end

    it "includes logo when provided" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      result = Hwaro::Content::Seo::JsonLd.organization(config, "/images/logo.png")

      result.should contain("logo")
      result.should contain("https://example.com/images/logo.png")
    end

    it "returns empty when base_url is empty" do
      config = Hwaro::Models::Config.new
      Hwaro::Content::Seo::JsonLd.organization(config).should eq("")
    end
  end

  describe ".person" do
    it "generates Person JSON-LD" do
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      result = Hwaro::Content::Seo::JsonLd.person("John Doe", config, url: "/about/", image: "/images/john.jpg")

      result.should contain("Person")
      result.should contain("John Doe")
      result.should contain("https://example.com/about/")
      result.should contain("https://example.com/images/john.jpg")
    end
  end

  describe ".article" do
    it "resolves the author display name from site.authors" do
      page = Hwaro::Models::Page.new("post.md")
      page.title = "Hello"
      page.url = "/blog/hello/"
      page.authors = ["jdoe"] # raw frontmatter id

      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      site = Hwaro::Models::Site.new(config)
      site.authors["jdoe"] = Crinja::Value.new({
        "key"  => Crinja::Value.new("jdoe"),
        "name" => Crinja::Value.new("Jane Doe"),
      })

      result = Hwaro::Content::Seo::JsonLd.article(page, config, site)
      result.should contain("Jane Doe")
      result.should_not contain("\"name\":\"jdoe\"")
    end

    it "falls back to the raw id when no site/author data is available" do
      page = Hwaro::Models::Page.new("post.md")
      page.title = "Hello"
      page.url = "/blog/hello/"
      page.authors = ["jdoe"]
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      result = Hwaro::Content::Seo::JsonLd.article(page, config)
      result.should contain("jdoe")
    end
  end

  describe ".for_page" do
    it "auto-detects FAQ schema type" do
      page = Hwaro::Models::Page.new("test.md")
      page.extra["schema_type"] = "FAQ".as(String | Bool | Int64 | Float64 | Array(String))
      page.extra["faq"] = ["Q", "A"].as(String | Bool | Int64 | Float64 | Array(String))

      config = Hwaro::Models::Config.new
      result = Hwaro::Content::Seo::JsonLd.for_page(page, config)

      result.should contain("FAQPage")
    end

    it "auto-detects HowTo schema type" do
      page = Hwaro::Models::Page.new("test.md")
      page.extra["schema_type"] = "HowTo".as(String | Bool | Int64 | Float64 | Array(String))
      page.extra["howto_steps"] = ["Step 1", "Do this"].as(String | Bool | Int64 | Float64 | Array(String))

      config = Hwaro::Models::Config.new
      result = Hwaro::Content::Seo::JsonLd.for_page(page, config)

      result.should contain("HowTo")
    end

    it "returns empty for unknown schema type" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      Hwaro::Content::Seo::JsonLd.for_page(page, config).should eq("")
    end
  end

  describe ".all_tags" do
    it "includes extended schema when schema_type is set" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/faq/"
      page.title = "FAQ"
      page.is_index = true
      page.extra["schema_type"] = "FAQ".as(String | Bool | Int64 | Float64 | Array(String))
      page.extra["faq_questions"] = ["Q1"].as(String | Bool | Int64 | Float64 | Array(String))
      page.extra["faq_answers"] = ["A1"].as(String | Bool | Int64 | Float64 | Array(String))

      config = Hwaro::Models::Config.new
      result = Hwaro::Content::Seo::JsonLd.all_tags(page, config)

      result.should contain("Article")
      result.should contain("FAQPage")
    end
  end

  describe "script-context escaping" do
    it "escapes <, >, & as \\uXXXX so JSON-LD can't break out of <script> (dogfooding find)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/post/"
      # The `<!--<script>` prefix triggers the HTML "script data double
      # escape" trap; a later real </script> would not close the element.
      page.title = "Break <!--<script>out</script> attempt & more"

      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"
      result = Hwaro::Content::Seo::JsonLd.article(page, config)

      # No raw HTML-significant characters survive inside the <script> body.
      body = result.sub(%(<script type="application/ld+json">), "").sub("</script>", "")
      body.should_not contain("<")
      body.should_not contain(">")
      body.should contain("\\u003c")
      body.should contain("\\u003e")
      body.should contain("\\u0026")

      # …and it still decodes back to the original title.
      json = JSON.parse(body)
      json["headline"].as_s.should eq("Break <!--<script>out</script> attempt & more")
    end
  end
end
