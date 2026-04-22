require "../../spec_helper"
require "../../../src/services/importers/wordpress_importer"

BASIC_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>Hello World</title>
      <wp:post_date>2024-01-15 10:30:00</wp:post_date>
      <wp:post_name>hello-world</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <category domain="post_tag" nicename="crystal"><![CDATA[Crystal]]></category>
      <category domain="post_tag" nicename="web"><![CDATA[Web]]></category>
      <category domain="category" nicename="tutorial"><![CDATA[Tutorial]]></category>
      <content:encoded><![CDATA[<p>This is my first post.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[A short excerpt]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

DRAFT_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>Draft Post</title>
      <wp:post_date>2024-02-01 08:00:00</wp:post_date>
      <wp:post_name>draft-post</wp:post_name>
      <wp:status>draft</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<p>Draft content.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

PAGE_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>About Me</title>
      <wp:post_date>2024-03-10 12:00:00</wp:post_date>
      <wp:post_name>about-me</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>page</wp:post_type>
      <content:encoded><![CDATA[<h2>About</h2><p>Some info about me.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[About page]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

MULTI_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>First Post</title>
      <wp:post_date>2024-01-01 00:00:00</wp:post_date>
      <wp:post_name>first-post</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<p>First</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
    <item>
      <title>Second Post</title>
      <wp:post_date>2024-02-01 00:00:00</wp:post_date>
      <wp:post_name>second-post</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<p>Second</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
    <item>
      <title>A Draft</title>
      <wp:post_date>2024-03-01 00:00:00</wp:post_date>
      <wp:post_name>a-draft</wp:post_name>
      <wp:status>draft</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<p>Not published yet.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

UNCATEGORIZED_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>Default Category</title>
      <wp:post_date>2024-04-01 00:00:00</wp:post_date>
      <wp:post_name>default-category</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <category domain="category" nicename="uncategorized"><![CDATA[Uncategorized]]></category>
      <category domain="post_tag" nicename="news"><![CDATA[News]]></category>
      <content:encoded><![CDATA[<p>Body.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

PUBDATE_ONLY_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>PubDate Only</title>
      <pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
      <wp:post_name>pubdate-only</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<p>Body.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

TABLE_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>Table Post</title>
      <wp:post_date>2024-01-15 10:30:00</wp:post_date>
      <wp:post_name>table-post</wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

NO_SLUG_WXR = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0"
    xmlns:wp="http://wordpress.org/export/1.2/"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
  <channel>
    <item>
      <title>My Fancy Title!</title>
      <wp:post_date>2024-05-20 09:00:00</wp:post_date>
      <wp:post_name></wp:post_name>
      <wp:status>publish</wp:status>
      <wp:post_type>post</wp:post_type>
      <content:encoded><![CDATA[<p>Content here.</p>]]></content:encoded>
      <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    </item>
  </channel>
  </rss>
  XML

private def write_wxr(dir : String, content : String) : String
  path = File.join(dir, "export.xml")
  File.write(path, content)
  path
end

private def make_options(wxr_path : String, output_dir : String, drafts : Bool = false) : Hwaro::Config::Options::ImportOptions
  Hwaro::Config::Options::ImportOptions.new(
    source_type: "wordpress",
    path: wxr_path,
    output_dir: output_dir,
    drafts: drafts,
    verbose: false
  )
end

describe Hwaro::Services::Importers::WordPressImporter do
  describe "#run" do
    it "imports a published post with correct frontmatter and body" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, BASIC_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))

        result.success.should be_true
        result.imported_count.should eq(1)
        result.skipped_count.should eq(0)

        file_path = File.join(output_dir, "posts", "hello-world.md")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("title = \"Hello World\"")
        content.should contain("date = \"2024-01-15 10:30:00\"")
        content.should contain("description = \"A short excerpt\"")
        content.should contain(%(tags = ["Crystal", "Web"]))
        content.should contain(%(categories = ["Tutorial"]))
        content.should contain("This is my first post.")
        content.should_not contain("draft")
      end
    end

    it "falls back to <pubDate> when <wp:post_date> is missing" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, PUBDATE_ONLY_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))
        result.imported_count.should eq(1)

        content = File.read(File.join(output_dir, "posts", "pubdate-only.md"))
        # RFC 822 → canonical frontmatter date format. Some exporters
        # omit <wp:post_date> and only populate the RSS <pubDate>; we
        # don't want those posts to arrive dateless.
        content.should contain(%(date = "2024-01-01 00:00:00"))
      end
    end

    it "converts <table> in content to a Markdown pipe-table" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, TABLE_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))
        result.imported_count.should eq(1)

        content = File.read(File.join(output_dir, "posts", "table-post.md"))
        content.should contain("| A | B |")
        content.should contain("| --- | --- |")
        content.should contain("| 1 | 2 |")
      end
    end

    it "skips the default WordPress 'Uncategorized' category" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, UNCATEGORIZED_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))
        result.imported_count.should eq(1)

        content = File.read(File.join(output_dir, "posts", "default-category.md"))
        content.should contain(%(tags = ["News"]))
        # Uncategorized is the placeholder default category — omit it
        # rather than importing every WP post with a bogus "Uncategorized"
        # classification.
        content.should_not contain("Uncategorized")
        content.should_not contain("categories =")
      end
    end

    it "skips drafts by default" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, DRAFT_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))

        result.imported_count.should eq(0)
        result.skipped_count.should eq(1)

        file_path = File.join(output_dir, "posts", "draft-post.md")
        File.exists?(file_path).should be_false
      end
    end

    it "imports drafts when drafts option is true" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, DRAFT_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir, drafts: true))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "draft-post.md")
        File.exists?(file_path).should be_true

        content = File.read(file_path)
        content.should contain("draft = true")
      end
    end

    it "places pages in root output dir, not posts/" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, PAGE_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))

        result.imported_count.should eq(1)

        # Page should be in root, not posts/
        page_path = File.join(output_dir, "about-me.md")
        File.exists?(page_path).should be_true

        posts_path = File.join(output_dir, "posts", "about-me.md")
        File.exists?(posts_path).should be_false

        content = File.read(page_path)
        content.should contain("title = \"About Me\"")
        content.should contain("About page")
      end
    end

    it "handles multiple items and skips drafts in mixed export" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, MULTI_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))

        result.imported_count.should eq(2)
        result.skipped_count.should eq(1)

        File.exists?(File.join(output_dir, "posts", "first-post.md")).should be_true
        File.exists?(File.join(output_dir, "posts", "second-post.md")).should be_true
        File.exists?(File.join(output_dir, "posts", "a-draft.md")).should be_false
      end
    end

    it "falls back to slugified title when post_name is empty" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, NO_SLUG_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options(wxr_path, output_dir))

        result.imported_count.should eq(1)

        file_path = File.join(output_dir, "posts", "my-fancy-title.md")
        File.exists?(file_path).should be_true
      end
    end

    it "returns error when WXR file does not exist" do
      Dir.mktmpdir do |tmpdir|
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result = importer.run(make_options("/nonexistent/file.xml", output_dir))

        result.success.should be_false
        result.message.should contain("not found")
      end
    end

    it "skips duplicate files on second run" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, BASIC_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        result1 = importer.run(make_options(wxr_path, output_dir))
        result1.imported_count.should eq(1)

        result2 = importer.run(make_options(wxr_path, output_dir))
        result2.imported_count.should eq(0)
        result2.skipped_count.should eq(1)
      end
    end

    it "converts HTML content to Markdown" do
      Dir.mktmpdir do |tmpdir|
        wxr_path = write_wxr(tmpdir, PAGE_WXR)
        output_dir = File.join(tmpdir, "content")

        importer = Hwaro::Services::Importers::WordPressImporter.new
        importer.run(make_options(wxr_path, output_dir))

        content = File.read(File.join(output_dir, "about-me.md"))
        content.should contain("## About")
        content.should contain("Some info about me.")
      end
    end
  end
end
