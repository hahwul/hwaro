require "../spec_helper"

# Stability regression specs for the importer subsystem. Each describe block
# matches one verified finding from the 2026-08 importer stability audit:
# crash-on-bad-input paths (invalid UTF-8, unreadable directories, overflowing
# numbers, truncated DOCTYPE windows) and silent data-loss paths (null-key
# fallback chains, first-occurrence extension stripping, empty taxonomy terms,
# O(n^2) HTML conversion blowups).

private def build_wxr(item_fields : String) : String
  <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"
         xmlns:content="http://purl.org/rss/1.0/modules/content/"
         xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/"
         xmlns:dc="http://purl.org/dc/elements/1.1/"
         xmlns:wp="http://wordpress.org/export/1.2/">
      <channel>
        <item>
    #{item_fields}
        </item>
      </channel>
    </rss>
    XML
end

describe "importer stability" do
  # (1) `parse_lenient` rescued only Time::Format::Error around
  # Time.parse_rfc3339, but a well-formed RFC 3339 string with an impossible
  # date ("2024-02-30") raises ArgumentError, which escaped to the caller.
  describe "DateUtils.parse_lenient" do
    it "returns nil for an RFC 3339 string with an out-of-range date" do
      Hwaro::Utils::DateUtils.parse_lenient("2024-02-30T00:00:00Z").should be_nil
    end

    it "still parses a valid RFC 3339 date" do
      parsed = Hwaro::Utils::DateUtils.parse_lenient("2024-02-28T10:20:30Z")
      parsed.should_not be_nil
      parsed.try(&.year).should eq(2024)
    end
  end

  # (2) A single invalid UTF-8 byte in a markdown source made every regex
  # pass raise ArgumentError, dropping the whole file with a cryptic error.
  # `read_text` is the single choke point, so it scrubs.
  describe "invalid UTF-8 in markdown sources" do
    it "imports a Jekyll post containing an invalid UTF-8 byte" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.open(File.join(posts_dir, "2024-01-02-scrub.md"), "w") do |f|
          f << "---\ntitle: Scrub Me\n---\n\nBody "
          f.write_byte(0xFF_u8)
          f << " tail.\n"
        end

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::JekyllImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "jekyll", path: dir, output_dir: output_dir,
          ))

        result.error_count.should eq(0)
        result.imported_count.should eq(1)
        content = File.read(File.join(output_dir, "posts", "scrub.md"))
        content.should contain(%(title = "Scrub Me"))
        content.should contain("tail.")
      end
    end
  end

  # (3) An invalid UTF-8 byte anywhere in a WXR file made the DOCTYPE guard's
  # regex raise ArgumentError, aborting the whole import before parsing.
  describe "invalid UTF-8 in a WXR export" do
    it "imports a WXR whose content carries an invalid byte" do
      Dir.mktmpdir do |dir|
        wxr = File.join(dir, "export.xml")
        wxr_text = build_wxr(<<-ITEM)
          <title>Hello</title>
          <wp:post_type>post</wp:post_type>
          <wp:status>publish</wp:status>
          <wp:post_name>hello</wp:post_name>
          <wp:post_date>2024-01-02 03:04:05</wp:post_date>
          <content:encoded><![CDATA[<p>Hi ITEM_BYTE there</p>]]></content:encoded>
          ITEM
        # Splice an invalid byte where the placeholder sits.
        before, _, after = wxr_text.partition("ITEM_BYTE")
        File.open(wxr, "w") do |f|
          f << before
          f.write_byte(0xFF_u8)
          f << after
        end

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::WordPressImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "wordpress", path: wxr, output_dir: output_dir,
          ))

        result.error_count.should eq(0)
        result.imported_count.should eq(1)
        File.exists?(File.join(output_dir, "posts", "hello.md")).should be_true
      end
    end
  end

  # (4) `File.exists?` is true for a directory, so passing a directory as the
  # WXR path crashed with "Is a directory" instead of the friendly error.
  describe "WXR path pointing at a directory" do
    it "refuses with a friendly message instead of raising" do
      Dir.mktmpdir do |dir|
        result = Hwaro::Services::Importers::WordPressImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "wordpress", path: dir, output_dir: File.join(dir, "out"),
          ))

        result.success.should be_false
        result.message.should contain(dir)
      end
    end
  end

  # (5) `safe_filename_component` split with a regex, which raises on the
  # invalid UTF-8 that URI.decode can produce (`a%ffb`), erroring the item.
  describe "percent-encoded invalid UTF-8 in a WordPress slug" do
    it "imports the item with a scrubbed filename" do
      Dir.mktmpdir do |dir|
        wxr = File.join(dir, "export.xml")
        File.write(wxr, build_wxr(<<-ITEM))
          <title>Bad Slug</title>
          <wp:post_type>post</wp:post_type>
          <wp:status>publish</wp:status>
          <wp:post_name>a%ffb</wp:post_name>
          <content:encoded><![CDATA[<p>Body</p>]]></content:encoded>
          ITEM

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::WordPressImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "wordpress", path: wxr, output_dir: output_dir,
          ))

        result.error_count.should eq(0)
        result.imported_count.should eq(1)
        written = Dir.glob(File.join(output_dir, "posts", "*.md"))
        written.size.should eq(1)
        File.basename(written.first).should eq("a�b.md")
      end
    end
  end

  # (6) A Notion internal link whose target URI-decodes to invalid UTF-8 made
  # the 32-hex regex raise, dropping the whole note.
  describe "invalid UTF-8 in a decoded Notion link target" do
    it "imports the note instead of erroring" do
      Dir.mktmpdir do |dir|
        vault = File.join(dir, "export")
        FileUtils.mkdir_p(vault)
        File.write(
          File.join(vault, "Note abcdef1234567890.md"),
          "# Note\n\nSee [Sub](Sub%ff%20abcdef0123456789abcdef0123456789ab.md) page.\n"
        )

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::NotionImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "notion", path: vault, output_dir: output_dir,
          ))

        result.error_count.should eq(0)
        result.imported_count.should eq(1)
      end
    end
  end

  # (7) An unreadable subdirectory raised File::AccessDeniedError out of
  # `Dir.children` in the middle of the walk, aborting the entire import.
  describe "unreadable subdirectory in the source tree" do
    it "skips it and imports the readable files" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        locked_dir = File.join(posts_dir, "locked")
        FileUtils.mkdir_p(locked_dir)
        File.write(File.join(posts_dir, "2024-01-02-open.md"), "---\ntitle: Open\n---\nBody.\n")
        File.write(File.join(locked_dir, "2024-01-03-hidden.md"), "---\ntitle: Hidden\n---\nBody.\n")
        File.chmod(locked_dir, 0o000)

        # Running as root would make the directory readable anyway.
        readable_anyway = begin
          Dir.children(locked_dir)
          true
        rescue File::Error
          false
        end

        begin
          unless readable_anyway
            output_dir = File.join(dir, "out")
            result = Hwaro::Services::Importers::JekyllImporter.new.run(
              Hwaro::Config::Options::ImportOptions.new(
                source_type: "jekyll", path: dir, output_dir: output_dir,
              ))

            result.imported_count.should eq(1)
            File.exists?(File.join(output_dir, "posts", "open.md")).should be_true
          end
        ensure
          File.chmod(locked_dir, 0o755)
        end
      end
    end
  end

  # (8) An 11ty data-file path that turns out to be a directory raised a bare
  # IO::Error ("Is a directory") past the `File::Error` rescue, aborting the
  # whole import before a single file was read.
  describe "Eleventy data file that is a directory" do
    it "skips it and imports the content" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "blog")
        FileUtils.mkdir_p(File.join(blog_dir, "blog.11tydata.json"))
        File.write(File.join(blog_dir, "post.md"), "---\ntitle: Post\n---\nBody.\n")

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: dir, output_dir: output_dir,
          ))

        result.imported_count.should eq(1)
        File.exists?(File.join(output_dir, "blog", "post.md")).should be_true
      end
    end
  end

  # (9) A Hugo `weight` that parses as a huge/non-finite Float64 overflowed
  # `to_i64`, erroring the whole file. The weight is ignored instead.
  describe "Hugo weight out of Int64 range" do
    it "imports the page and drops the unusable weight" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "content", "posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(File.join(posts_dir, "big.md"), "---\ntitle: Big\nweight: 1.0e300\n---\nBody.\n")
        File.write(File.join(posts_dir, "small.md"), "---\ntitle: Small\nweight: 2.0\n---\nBody.\n")

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::HugoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hugo", path: dir, output_dir: output_dir,
          ))

        result.error_count.should eq(0)
        result.imported_count.should eq(2)
        File.read(File.join(output_dir, "posts", "big.md")).should_not contain("weight")
        File.read(File.join(output_dir, "posts", "small.md")).should contain("weight = 2")
      end
    end
  end

  # (10) A trailing slash on the source path broke the File.dirname-based
  # prefix strip ("site" vs "site/"), misclassifying the site-root index.md.
  describe "Eleventy source path with a trailing slash" do
    it "still recognizes the site-root index" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.md"), "---\ntitle: Home\n---\nWelcome.\n")
        File.write(File.join(dir, "about.md"), "---\ntitle: About\n---\nAbout.\n")

        output_dir = File.join(dir, "out")
        result = Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: "#{dir}/", output_dir: output_dir,
          ))

        result.imported_count.should eq(2)
        File.exists?(File.join(output_dir, "index.md")).should be_true
      end
    end
  end

  # (11) `yaml["a"]? || yaml["b"]?` treats a present-but-null key as truthy
  # (YAML::Any is a struct), silently discarding every fallback after it.
  describe "null-key fallback chains" do
    it "Astro: falls back to `date` when `pubDate` is null" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)
        File.write(
          File.join(blog_dir, "post.md"),
          "---\ntitle: Post\npubDate:\ndate: 2024-03-04\nheroImage:\ncover: /img/c.png\n---\nBody.\n"
        )

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::AstroImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "astro", path: dir, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "blog", "post.md"))
        content.should contain("date = ")
        content.should contain("2024-03-04")
        content.should contain(%(image = "/img/c.png"))
      end
    end

    it "Jekyll: falls back to `description` when `excerpt` is null" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "2024-01-02-post.md"),
          "---\ntitle: Post\nexcerpt:\ndescription: Real summary\n---\nBody.\n"
        )

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::JekyllImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "jekyll", path: dir, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "posts", "post.md"))
        content.should contain(%(description = "Real summary"))
      end
    end

    it "Hexo: falls back to `thumbnail` when `cover` is null" do
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, "source", "_posts")
        FileUtils.mkdir_p(posts_dir)
        File.write(
          File.join(posts_dir, "post.md"),
          "---\ntitle: Post\ndescription:\nexcerpt: From excerpt\ncover:\nthumbnail: /img/t.png\n---\nBody.\n"
        )

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::HexoImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "hexo", path: dir, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "posts", "post.md"))
        content.should contain(%(image = "/img/t.png"))
        content.should contain(%(description = "From excerpt"))
      end
    end

    it "Eleventy: falls back to `excerpt` when `description` is null" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "blog")
        FileUtils.mkdir_p(blog_dir)
        File.write(
          File.join(blog_dir, "post.md"),
          "---\ntitle: Post\ndescription:\nexcerpt: Fallback text\nimage:\nfeaturedImage: /img/f.png\n---\nBody.\n"
        )

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::EleventyImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "eleventy", path: dir, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "blog", "post.md"))
        content.should contain(%(description = "Fallback text"))
        content.should contain(%(image = "/img/f.png"))
      end
    end
  end

  # (12) `sub(File.extname(...))` strips the FIRST occurrence of the
  # extension substring, so `sub/deep.md.old.md` registered the wrong
  # link-map key and a path wiki-link to it fell back to a dead slug.
  describe "Obsidian extension stripping" do
    it "resolves a path wiki-link to a note whose stem contains .md" do
      Dir.mktmpdir do |dir|
        vault = File.join(dir, "vault")
        FileUtils.mkdir_p(File.join(vault, "sub"))
        File.write(File.join(vault, "sub", "deep.md.old.md"), "---\ntitle: Deep Old\n---\nOld note.\n")
        File.write(File.join(vault, "linker.md"), "---\ntitle: Linker\n---\nSee [[sub/deep.md.old]].\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::ObsidianImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "obsidian", path: vault, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "posts", "linker.md"))
        content.should contain("(/sub/deep-old/)")
      end
    end
  end

  # (13) The array branch of `collect_string_list` didn't filter empty
  # strings (the string branch does), emitting an empty taxonomy term.
  describe "empty strings in tag arrays" do
    it "drops empty items from an Astro tags array" do
      Dir.mktmpdir do |dir|
        blog_dir = File.join(dir, "src", "content", "blog")
        FileUtils.mkdir_p(blog_dir)
        File.write(File.join(blog_dir, "post.md"), "---\ntitle: Post\ntags: [\"\", \"a\"]\n---\nBody.\n")

        output_dir = File.join(dir, "out")
        Hwaro::Services::Importers::AstroImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "astro", path: dir, output_dir: output_dir,
          ))

        content = File.read(File.join(output_dir, "blog", "post.md"))
        content.should contain(%(tags = ["a"]))
      end
    end
  end

  # (14) Every lazy-body regex pass except the anchor pass was unbounded, so
  # adversarial markup (many unclosed tags) degraded to O(n^2). The bounded
  # rewrite must not change output for normal documents — this expected
  # string was captured from the converter BEFORE the bounding change.
  describe "HtmlToMarkdown bounded passes" do
    it "converts a normal nested document byte-identically to the unbounded version" do
      html = <<-HTML
        <h1>Main Title</h1>
        <p>Intro paragraph with <strong>bold</strong>, <em>italic</em>, <code>inline_code()</code> and <del>gone</del>.</p>
        <h2>Section &amp; Sub</h2>
        <p>A link: <a href="https://example.com/a?b=1&amp;c=2">Example</a> and an image <img src="/img/pic.png" alt="A pic"/> inline.</p>
        <blockquote><p>Quoted line one.</p><p>Quoted line two.</p></blockquote>
        <ul>
          <li>alpha</li>
          <li>beta<ul><li>beta-one</li><li>beta-two</li></ul></li>
          <li>gamma</li>
        </ul>
        <ol>
          <li>first</li>
          <li>second<ol><li>second-one</li></ol></li>
        </ol>
        <pre><code>def hello
          puts "hi &lt;world&gt;"
        end</code></pre>
        <table>
          <thead><tr><th>Name</th><th>Value</th></tr></thead>
          <tbody><tr><td>one</td><td>1 | one</td></tr><tr><td>two</td><td>2</td></tr></tbody>
        </table>
        <hr/>
        <p>Tail paragraph.<br/>Second line &#8212; done&#8230;</p>
        HTML

      expected = "# Main Title\n\nIntro paragraph with **bold**, *italic*, `inline_code()` and ~~gone~~.\n\n" \
                 "## Section & Sub\n\nA link: [Example](https://example.com/a?b=1&c=2) and an image " \
                 "![A pic](/img/pic.png) inline.\n\n> Quoted line one.Quoted line two.\n\n" \
                 "- alpha\n- beta\n  - beta-one\n  - beta-two\n- gamma\n\n" \
                 "1. first\n2. second\n   1. second-one\n\n" \
                 "```\ndef hello\n  puts \"hi <world>\"\nend\n```\n\n" \
                 "| Name | Value |\n| --- | --- |\n| one | 1 \\| one |\n| two | 2 |\n\n" \
                 "---\n\nTail paragraph.  \nSecond line -- done..."

      Hwaro::Services::Importers::HtmlToMarkdown.convert(html).should eq(expected)
    end

    it "keeps converting a long (multi-KB) code block to a fence" do
      code = (["line = compute(#{"x" * 40})"] * 300).join("\n")
      html = "<p>Intro</p><pre><code>#{code}</code></pre>"
      converted = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      converted.should contain("```\nline = compute(")
      converted.should contain("Intro")
    end

    it "completes on unclosed <pre><code> spam (the quadratic two-literal-tail pass)" do
      html = "<pre><code>x" * 30_000 + "</code>"
      converted = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      converted.should contain("x")
      converted.should_not contain("<pre>")
    end

    it "completes on a document of tens of thousands of unclosed <p> tags" do
      html = "<p>data" * 30_000
      converted = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      converted.should contain("datadata")
      converted.should_not contain("<p>")
    end

    it "completes on pathologically deep nested lists" do
      depth = 500
      html = "<ul><li>x" * depth + "</li></ul>" * depth
      converted = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      converted.should contain("- x")
      converted.should_not contain("<ul>")
    end
  end

  # (15) The anti-ENTITY DOCTYPE guard scanned only the first 64 KB after
  # <!DOCTYPE; an internal subset longer than the window smuggled its
  # <!ENTITY> declarations past the scan.
  describe "WXR DOCTYPE longer than the scan window" do
    it "refuses a WXR whose DOCTYPE runs past the guard window" do
      Dir.mktmpdir do |dir|
        wxr = File.join(dir, "export.xml")
        filler = "<!-- #{"a" * 70_000} -->"
        doc = <<-XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE rss [
          #{filler}
          <!ENTITY smuggled "boom">
          ]>
          <rss version="2.0"
               xmlns:content="http://purl.org/rss/1.0/modules/content/"
               xmlns:wp="http://wordpress.org/export/1.2/">
            <channel>
              <item>
                <title>Hi</title>
                <wp:post_type>post</wp:post_type>
                <wp:status>publish</wp:status>
                <wp:post_name>hi</wp:post_name>
                <content:encoded><![CDATA[<p>Body</p>]]></content:encoded>
              </item>
            </channel>
          </rss>
          XML
        File.write(wxr, doc)

        result = Hwaro::Services::Importers::WordPressImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "wordpress", path: wxr, output_dir: File.join(dir, "out"),
          ))

        result.success.should be_false
        result.message.should contain("declares XML entities")
      end
    end

    # Review follow-up: the guard seeded its scan from the first `<!DOCTYPE`
    # match anywhere in the file, so a post body that merely mentions one
    # (a DTD tutorial with unbalanced brackets in prose) never "closed" the
    # scan and got the whole import refused.
    it "imports a WXR whose post body merely mentions <!DOCTYPE" do
      Dir.mktmpdir do |dir|
        wxr = File.join(dir, "export.xml")
        body = %(Example: <!DOCTYPE note [ ... then array[0 and list[1 keep "these unclosed)
        item = <<-ITEM
          <title>DTD Tutorial</title>
          <wp:post_type>post</wp:post_type>
          <wp:status>publish</wp:status>
          <wp:post_name>dtd-tutorial</wp:post_name>
          <content:encoded><![CDATA[<p>#{body}</p>]]></content:encoded>
          ITEM
        File.write(wxr, build_wxr(item))

        result = Hwaro::Services::Importers::WordPressImporter.new.run(
          Hwaro::Config::Options::ImportOptions.new(
            source_type: "wordpress", path: wxr, output_dir: File.join(dir, "out"),
          ))

        result.success.should be_true
        result.imported_count.should eq(1)
      end
    end
  end

  # Review follow-up: a <pre><code> body longer than the bounded pass's
  # ceiling fell through to the plain <pre> pass with its <code> wrapper
  # still attached, leaving literal tags inside the emitted fence.
  describe "oversized pre+code blocks" do
    it "strips the code wrapper from a body past the bounded-pass ceiling" do
      body = "line\n" * 15_000 # ~75k chars, past MAX_CODE_BODY_CHARS
      converted = Hwaro::Services::Importers::HtmlToMarkdown.convert(
        "<p>Intro</p><pre><code class=\"language-x\">#{body}</code></pre>"
      )
      converted.should_not contain("<code")
      converted.should_not contain("</code>")
      converted.should contain("```\nline\n")
    end
  end
end
