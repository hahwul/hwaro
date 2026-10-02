require "../../../spec_helper"

describe Hwaro::Content::Processors::Xml do
  describe ".minify" do
    it "minifies XML by default" do
      input = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <root>
          <item>
            <title>Hello</title>
          </item>
        </root>
        XML

      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should_not contain("\n")
      result.should contain("<root>")
      result.should contain("<title>Hello</title>")
      result.should contain("</root>")
    end

    it "removes whitespace between tags" do
      input = "<root>  \n  <child>value</child>  \n</root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<root><child>value</child></root>")
    end

    it "removes leading and trailing whitespace" do
      input = "   <root><item/></root>   "
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should_not start_with(" ")
      result.should_not end_with(" ")
    end

    it "handles already minified XML" do
      input = "<root><item>value</item></root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should eq(input)
    end

    it "preserves whitespace and newlines inside a CDATA section" do
      # CDATA is raw character data (RSS <content:encoded>, embedded scripts,
      # pre-formatted code) — its internal whitespace must not be collapsed.
      input = "<root>\n  <![CDATA[ keep   these    spaces\n  and newline ]]>\n</root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<![CDATA[ keep   these    spaces\n  and newline ]]>")
    end

    it "does not collapse cross-line whitespace between tag-like text inside CDATA (A15)" do
      # The `>\s*\n\s*<` collapse is for markup between tags; inside CDATA
      # those bytes are character data and must survive byte-exact.
      input = "<root><d><![CDATA[</a>\n<em>]]></d></root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<![CDATA[</a>\n<em>]]>")
    end

    it "preserves a CDATA section byte-exact while still minifying surrounding markup" do
      input = "<root>\n  <d><![CDATA[pre >\n< post]]></d>\n</root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<![CDATA[pre >\n< post]]>")
      result.should contain("<root><d>")
      result.should contain("</d></root>")
    end

    it "preserves whitespace and newlines inside an XML comment" do
      input = "<root>\n  <!-- keep   these    spaces\n  and newline -->\n</root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<!-- keep   these    spaces\n  and newline -->")
    end

    it "minifies XML with attributes" do
      input = <<-XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url>
            <loc>https://example.com/</loc>
          </url>
        </urlset>
        XML

      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<urlset")
      result.should contain("<loc>https://example.com/</loc>")
    end

    it "handles self-closing tags" do
      input = <<-XML
        <root>
          <empty/>
          <also-empty />
        </root>
        XML

      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<empty/>")
    end

    it "handles XML declaration" do
      input = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should contain("<?xml")
      result.should contain("<root/>")
    end

    it "minifies RSS feed XML" do
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

      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should_not contain("\n")
      result.should contain("<title>Test Feed</title>")
      result.should contain("<title>Post 1</title>")
    end

    it "minifies sitemap XML" do
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

      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should_not contain("\n")
      result.should contain("https://example.com/")
      result.should contain("https://example.com/about/")
    end

    it "handles empty XML content" do
      result = Hwaro::Content::Processors::Xml.minify("")
      result.should eq("")
    end

    it "handles whitespace-only content" do
      result = Hwaro::Content::Processors::Xml.minify("   \n  \n   ")
      result.should eq("")
    end

    it "handles Atom feed XML" do
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

      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should_not contain("\n")
      result.should contain("<title>Test Feed</title>")
      result.should contain("<title>Entry 1</title>")
    end

    it "keeps word-separating whitespace in mixed content" do
      input = "<feed>\n  <t>Hello <b>bold</b>\n  <i>italic</i></t>\n</feed>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should eq("<feed><t>Hello <b>bold</b>\n  <i>italic</i></t></feed>")
    end

    it "keeps whitespace under xml:space=\"preserve\" (and its descendants)" do
      input = "<doc>\n  <pre xml:space=\"preserve\">\n    <a>x</a>\n    <b>y</b>\n  </pre>\n  <c>z</c>\n</doc>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should eq("<doc><pre xml:space=\"preserve\">\n    <a>x</a>\n    <b>y</b>\n  </pre><c>z</c></doc>")
    end

    it "lets xml:space=\"default\" end an inherited preserve" do
      input = "<doc xml:space=\"preserve\"><c xml:space=\"default\">\n  <d/>\n</c></doc>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should eq("<doc xml:space=\"preserve\"><c xml:space=\"default\"><d/></c></doc>")
    end

    it "reads a '>' inside a quoted attribute as part of the tag" do
      input = "<g>text<p><x a=\"1>2\"/></p>\n<q>word</q></g>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should eq(input)
    end

    it "still removes indentation around comments in element-only content" do
      input = "<root>\n  <!-- note -->\n  <a>1</a>\n  <b>2</b>\n</root>"
      result = Hwaro::Content::Processors::Xml.minify(input)
      result.should eq("<root>\n  <!-- note -->\n  <a>1</a><b>2</b></root>")
    end
  end
end
