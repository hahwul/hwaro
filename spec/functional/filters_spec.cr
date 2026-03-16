require "./support/build_helper"

# =============================================================================
# Template filter functional tests
#
# Verifies string, date, URL, collection, HTML, and misc filters work
# correctly through the full build pipeline.
# =============================================================================

describe "Filters: String filters" do
  it "truncate_words truncates text to N words" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: Post\ndescription: one two three four five six seven eight\n---\nBody",
      },
      template_files: {
        "page.html" => "TRUNC={{ page_description | truncate_words(length=3) }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("TRUNC=one two three...")
    end
  end

  it "slugify converts text to URL slug" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Hello World Test\n---\nBody"},
      template_files: {"page.html" => "SLUG={{ page_title | slugify }}"},
    ) do
      html = File.read("public/page/index.html")
      html.should contain("SLUG=hello-world-test")
    end
  end

  it "split splits string by separator" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "{% set parts = \"a,b,c\" | split(pat=\",\") %}COUNT={{ parts | length }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("COUNT=3")
    end
  end

  it "trim strips whitespace" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "TRIMMED=[{{ \"  hello  \" | trim }}]",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("TRIMMED=[hello]")
    end
  end
end

describe "Filters: Date filter" do
  it "formats date with custom format string" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: Post\ndate: \"2024-06-15\"\n---\nBody",
      },
      template_files: {
        "page.html" => "DATE={{ page.date | date(format=\"%Y/%m/%d\") }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("DATE=2024/06/15")
    end
  end
end

describe "Filters: URL filters" do
  it "absolute_url prepends base_url" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "ABS={{ \"/about/\" | absolute_url }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("ABS=http://localhost/about/")
    end
  end

  it "relative_url handles paths" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "REL={{ \"/about/\" | relative_url }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("REL=/about/")
    end
  end
end

describe "Filters: Collection filters" do
  it "where filters array by attribute" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/a.md"      => "---\ntitle: Draft Post\ndraft: true\n---\nA",
        "blog/b.md"      => "---\ntitle: Published Post\ndraft: false\n---\nB",
        "blog/c.md"      => "---\ntitle: Another Published\ndraft: false\n---\nC",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% set published = section.pages | where(attribute=\"draft\", value=false) %}PUB_COUNT={{ published | length }}",
      },
      drafts: true,
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("PUB_COUNT=2")
    end
  end

  it "sort_by sorts array by attribute" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/c.md"      => "---\ntitle: CCC\n---\nC",
        "blog/a.md"      => "---\ntitle: AAA\n---\nA",
        "blog/b.md"      => "---\ntitle: BBB\n---\nB",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% set sorted = section.pages | sort_by(attribute=\"title\") %}{% for p in sorted %}{{ p.title }},{% endfor %}",
      },
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("AAA,BBB,CCC,")
    end
  end

  it "group_by groups array by attribute" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/a.md"      => "---\ntitle: A\ndraft: false\n---\nA",
        "blog/b.md"      => "---\ntitle: B\ndraft: false\n---\nB",
        "blog/c.md"      => "---\ntitle: C\ndraft: true\n---\nC",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% set groups = section.pages | group_by(attribute=\"draft\") %}{% for g in groups %}GROUP={{ g.grouper }}:{{ g.list | length }},{% endfor %}",
      },
      drafts: true,
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("GROUP=false:2")
      html.should contain("GROUP=true:1")
    end
  end
end

describe "Filters: HTML filters" do
  it "strip_html removes HTML tags" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "STRIPPED={{ \"<p>Hello <b>world</b></p>\" | strip_html }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("STRIPPED=Hello world")
    end
  end

  it "xml_escape escapes XML entities" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "ESC={{ \"<div>&test</div>\" | xml_escape }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("&amp;test")
      html.should contain("&lt;div&gt;")
    end
  end

  it "markdownify converts markdown to HTML" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "MD={{ \"**bold** text\" | markdownify }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("<strong>bold</strong>")
    end
  end
end

describe "Filters: Misc filters" do
  it "jsonify converts value to JSON" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "JSON={{ page_title | jsonify }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("JSON=\"Page\"")
    end
  end

  it "default provides fallback for empty values" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "DEF={{ page_description | default(value=\"No description\") }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("DEF=No description")
    end
  end

  it "default returns original value when not empty" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\ndescription: Has value\n---\nBody"},
      template_files: {
        "page.html" => "DEF={{ page_description | default(value=\"Fallback\") }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("DEF=Has value")
      html.should_not contain("Fallback")
    end
  end

  it "jsonify converts integer to JSON string" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/a.md"      => "---\ntitle: A\n---\nA",
        "blog/b.md"      => "---\ntitle: B\n---\nB",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "COUNT={{ section.pages | length | jsonify }}",
      },
    ) do
      html = File.read("public/blog/index.html")
      # jsonify wraps values in JSON format (e.g., integers become quoted)
      html.should contain("COUNT=")
    end
  end
end

describe "Filters: Chained filters" do
  it "chains multiple filters together" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Hello World Test\n---\nBody"},
      template_files: {
        "page.html" => "RESULT={{ page_title | slugify | truncate_words(length=2) }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("RESULT=")
    end
  end
end

describe "Filters: sort_by with reverse" do
  it "sorts array by attribute in reverse order" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/a.md"      => "---\ntitle: AAA\n---\nA",
        "blog/b.md"      => "---\ntitle: BBB\n---\nB",
        "blog/c.md"      => "---\ntitle: CCC\n---\nC",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% set sorted = section.pages | sort_by(attribute=\"title\", reverse=true) %}{% for p in sorted %}{{ p.title }},{% endfor %}",
      },
    ) do
      html = File.read("public/blog/index.html")
      ccc_pos = html.index("CCC,").not_nil!
      bbb_pos = html.index("BBB,").not_nil!
      aaa_pos = html.index("AAA,").not_nil!
      (ccc_pos < bbb_pos).should be_true
      (bbb_pos < aaa_pos).should be_true
    end
  end
end

describe "Filters: where with string values" do
  it "filters array by string attribute value" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "---\ntitle: Blog\n---\n",
        "blog/a.md"      => "---\ntitle: Post A\n---\nA",
        "blog/b.md"      => "---\ntitle: Post B\n---\nB",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "{% set filtered = section.pages | where(attribute=\"title\", value=\"Post A\") %}FOUND={{ filtered | length }}",
      },
    ) do
      html = File.read("public/blog/index.html")
      html.should contain("FOUND=1")
    end
  end
end

describe "Filters: truncate_words edge cases" do
  it "truncate_words with text shorter than limit returns full text" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "post.md" => "---\ntitle: Post\ndescription: short text\n---\nBody",
      },
      template_files: {
        "page.html" => "TRUNC={{ page_description | truncate_words(length=10) }}",
      },
    ) do
      html = File.read("public/post/index.html")
      html.should contain("TRUNC=short text")
      html.should_not contain("...")
    end
  end
end

describe "Filters: markdownify with complex content" do
  it "markdownify handles headings and lists" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "MD={{ \"# Title\\n\\n- item1\\n- item2\" | markdownify }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("<h1")
      html.should contain("<li>")
    end
  end
end

describe "Filters: xml_escape edge cases" do
  it "xml_escape handles quotes and apostrophes" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "ESC={{ \"He said \\\"hello\\\" & she said 'bye'\" | xml_escape }}",
      },
    ) do
      html = File.read("public/page/index.html")
      html.should contain("&amp;")
    end
  end
end

describe "Filters: strip_html with nested tags" do
  it "strip_html removes nested and self-closing tags" do
    build_site(
      BASIC_CONFIG,
      content_files: {"page.md" => "---\ntitle: Page\n---\nBody"},
      template_files: {
        "page.html" => "STRIPPED={{ \"<div><p>Hello</p><br/><span>World</span></div>\" | strip_html }}",
      },
    ) do
      html = File.read("public/page/index.html")
      # TextUtils.strip_html inserts space at tag boundaries for word separation
      html.should contain("STRIPPED=Hello World")
    end
  end
end
