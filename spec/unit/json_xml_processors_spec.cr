require "../spec_helper"

describe Hwaro::Content::Processors::Json do
  describe "#name" do
    it "returns 'json'" do
      processor = Hwaro::Content::Processors::Json.new
      processor.name.should eq("json")
    end
  end

  describe "#extensions" do
    it "returns ['.json']" do
      processor = Hwaro::Content::Processors::Json.new
      processor.extensions.should eq([".json"])
    end
  end

  describe "#priority" do
    it "returns 50" do
      processor = Hwaro::Content::Processors::Json.new
      processor.priority.should eq(50)
    end
  end

  describe "#process" do
    it "minifies JSON by default" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "title": "Hello",
        "count": 42,
        "active": true
      }
      JSON

      result = processor.process(input, context)
      result.content.should eq(%q({"title":"Hello","count":42,"active":true}))
      result.error.should be_nil
    end

    it "minifies JSON with nested objects" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "person": {
          "name": "Alice",
          "age": 30
        }
      }
      JSON

      result = processor.process(input, context)
      result.content.should eq(%q({"person":{"name":"Alice","age":30}}))
    end

    it "minifies JSON with arrays" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "tags": [
          "crystal",
          "programming",
          "test"
        ]
      }
      JSON

      result = processor.process(input, context)
      result.content.should eq(%q({"tags":["crystal","programming","test"]}))
    end

    it "minifies a JSON array at root level" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      [
        { "id": 1, "name": "first" },
        { "id": 2, "name": "second" }
      ]
      JSON

      result = processor.process(input, context)
      result.content.should eq(%q([{"id":1,"name":"first"},{"id":2,"name":"second"}]))
    end

    it "returns content unchanged when minify is false" do
      processor = Hwaro::Content::Processors::Json.new(minify: false)
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = %q({"key": "value"})
      result = processor.process(input, context)
      result.content.should eq(input)
    end

    it "handles already minified JSON" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = %q({"key":"value","num":1})
      result = processor.process(input, context)
      result.content.should eq(input)
    end

    it "returns error for invalid JSON" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "{invalid json content"
      result = processor.process(input, context)
      result.error.should_not be_nil
      result.error.not_nil!.should contain("JSON parsing failed")
    end

    it "returns error for empty string" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      result = processor.process("", context)
      result.error.should_not be_nil
    end

    it "handles JSON with special characters in strings" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "message": "He said \\"hello\\"",
        "path": "C:\\\\Users\\\\test"
      }
      JSON

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should contain("He said \\\"hello\\\"")
    end

    it "handles JSON with null values" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "name": "Test",
        "value": null
      }
      JSON

      result = processor.process(input, context)
      result.content.should eq(%q({"name":"Test","value":null}))
    end

    it "handles JSON with numeric values" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "integer": 42,
        "float": 3.14,
        "negative": -10,
        "zero": 0
      }
      JSON

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should contain("42")
      result.content.should contain("3.14")
      result.content.should contain("-10")
    end

    it "handles deeply nested JSON" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-JSON
      {
        "level1": {
          "level2": {
            "level3": {
              "value": "deep"
            }
          }
        }
      }
      JSON

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should eq(%q({"level1":{"level2":{"level3":{"value":"deep"}}}}))
    end

    it "handles empty JSON object" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "  {  }  "
      result = processor.process(input, context)
      result.content.should eq("{}")
    end

    it "handles empty JSON array" do
      processor = Hwaro::Content::Processors::Json.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "  [  ]  "
      result = processor.process(input, context)
      result.content.should eq("[]")
    end
  end

  describe "registration" do
    it "is registered in the processor registry" do
      Hwaro::Content::Processors::Registry.has?("json").should be_true
    end
  end
end

describe Hwaro::Content::Processors::Xml do
  describe "#name" do
    it "returns 'xml'" do
      processor = Hwaro::Content::Processors::Xml.new
      processor.name.should eq("xml")
    end
  end

  describe "#extensions" do
    it "returns ['.xml']" do
      processor = Hwaro::Content::Processors::Xml.new
      processor.extensions.should eq([".xml"])
    end
  end

  describe "#priority" do
    it "returns 40" do
      processor = Hwaro::Content::Processors::Xml.new
      processor.priority.should eq(40)
    end
  end

  describe "#process" do
    it "minifies XML by default" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root>
        <item>
          <title>Hello</title>
        </item>
      </root>
      XML

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should_not contain("\n")
      result.content.should contain("<root>")
      result.content.should contain("<title>Hello</title>")
      result.content.should contain("</root>")
    end

    it "removes whitespace between tags" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "<root>  \n  <child>value</child>  \n</root>"
      result = processor.process(input, context)
      result.content.should contain("<root><child>value</child></root>")
    end

    it "removes leading and trailing whitespace" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "   <root><item/></root>   "
      result = processor.process(input, context)
      result.content.should_not start_with(" ")
      result.content.should_not end_with(" ")
    end

    it "returns content unchanged when minify is false" do
      processor = Hwaro::Content::Processors::Xml.new(minify: false)
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "<root>\n  <item/>\n</root>"
      result = processor.process(input, context)
      result.content.should eq(input)
    end

    it "handles already minified XML" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "<root><item>value</item></root>"
      result = processor.process(input, context)
      result.content.should eq(input)
    end

    it "minifies XML with attributes" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-XML
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/</loc>
        </url>
      </urlset>
      XML

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should contain("<urlset")
      result.content.should contain("<loc>https://example.com/</loc>")
    end

    it "handles self-closing tags" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-XML
      <root>
        <empty/>
        <also-empty />
      </root>
      XML

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should contain("<empty/>")
    end

    it "handles XML declaration" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>"
      result = processor.process(input, context)
      result.content.should contain("<?xml")
      result.content.should contain("<root/>")
    end

    it "minifies RSS feed XML" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>https://example.com</link>
          <item>
            <title>Post 1</title>
            <link>https://example.com/post1/</link>
          </item>
        </channel>
      </rss>
      XML

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should_not contain("\n")
      result.content.should contain("<title>Test Feed</title>")
      result.content.should contain("<title>Post 1</title>")
    end

    it "minifies sitemap XML" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/</loc>
          <lastmod>2024-01-01</lastmod>
          <changefreq>weekly</changefreq>
          <priority>1.0</priority>
        </url>
        <url>
          <loc>https://example.com/about/</loc>
          <changefreq>monthly</changefreq>
          <priority>0.8</priority>
        </url>
      </urlset>
      XML

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should_not contain("\n")
      result.content.should contain("https://example.com/")
      result.content.should contain("https://example.com/about/")
    end

    it "handles empty XML content" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      result = processor.process("", context)
      result.error.should be_nil
      result.content.should eq("")
    end

    it "handles whitespace-only content" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      result = processor.process("   \n  \n   ", context)
      result.error.should be_nil
      result.content.should eq("")
    end

    it "handles Atom feed XML" do
      processor = Hwaro::Content::Processors::Xml.new
      context = Hwaro::Content::Processors::ProcessorContext.new

      input = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Feed</title>
        <link href="https://example.com" />
        <entry>
          <title>Entry 1</title>
          <link href="https://example.com/entry1/" />
          <content type="html">Some content</content>
        </entry>
      </feed>
      XML

      result = processor.process(input, context)
      result.error.should be_nil
      result.content.should_not contain("\n")
      result.content.should contain("<title>Test Feed</title>")
      result.content.should contain("<title>Entry 1</title>")
    end
  end

  describe "registration" do
    it "is registered in the processor registry" do
      Hwaro::Content::Processors::Registry.has?("xml").should be_true
    end
  end
end
