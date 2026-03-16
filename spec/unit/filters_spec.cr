require "../spec_helper"
require "../../src/content/processors/template"

# Helper to render a template string through the Hwaro template engine
private def render_filter(template_str : String, vars : Hash(String, Crinja::Value) = {} of String => Crinja::Value) : String
  engine = Hwaro::Content::Processors::TemplateEngine.new
  engine.render(template_str, vars)
end

# Helper to build a Crinja::Value from an array of hashes
private def crinja_hash_array(items : Array(Hash(String, String))) : Crinja::Value
  arr = items.map do |h|
    hash = {} of Crinja::Value => Crinja::Value
    h.each { |k, v| hash[Crinja::Value.new(k)] = Crinja::Value.new(v) }
    Crinja::Value.new(hash)
  end
  Crinja::Value.new(arr)
end

# =============================================================================
# Collection Filters
# =============================================================================
describe "CollectionFilters" do
  describe "where" do
    it "filters array of hashes by attribute value" do
      items = crinja_hash_array([
        {"name" => "Alice", "role" => "admin"},
        {"name" => "Bob", "role" => "user"},
        {"name" => "Carol", "role" => "admin"},
      ])

      vars = {"items" => items}
      result = render_filter("{% for item in items | where(attribute='role', value='admin') %}{{ item.name }},{% endfor %}", vars)
      result.should contain("Alice")
      result.should contain("Carol")
      result.should_not contain("Bob")
    end

    it "returns empty array when no items match" do
      items = crinja_hash_array([
        {"name" => "Alice", "role" => "admin"},
      ])

      vars = {"items" => items}
      result = render_filter("{% for item in items | where(attribute='role', value='guest') %}{{ item.name }}{% endfor %}", vars)
      result.strip.should eq("")
    end

    it "returns empty array for non-array input" do
      vars = {"items" => Crinja::Value.new("not an array")}
      result = render_filter("{% for item in items | where(attribute='x', value='y') %}found{% endfor %}", vars)
      result.strip.should eq("")
    end

    it "handles missing attribute gracefully" do
      items = crinja_hash_array([
        {"name" => "Alice"},
        {"name" => "Bob", "role" => "admin"},
      ])

      vars = {"items" => items}
      result = render_filter("{% for item in items | where(attribute='role', value='admin') %}{{ item.name }},{% endfor %}", vars)
      result.should contain("Bob")
      result.should_not contain("Alice")
    end
  end

  describe "sort_by" do
    it "sorts array of hashes by attribute" do
      items = crinja_hash_array([
        {"name" => "Charlie", "weight" => "3"},
        {"name" => "Alice", "weight" => "1"},
        {"name" => "Bob", "weight" => "2"},
      ])

      vars = {"items" => items}
      result = render_filter("{% for item in items | sort_by(attribute='weight') %}{{ item.name }},{% endfor %}", vars)
      result.should eq("Alice,Bob,Charlie,")
    end

    it "sorts in reverse order" do
      items = crinja_hash_array([
        {"name" => "Alice", "weight" => "1"},
        {"name" => "Bob", "weight" => "2"},
        {"name" => "Charlie", "weight" => "3"},
      ])

      vars = {"items" => items}
      result = render_filter("{% for item in items | sort_by(attribute='weight', reverse=true) %}{{ item.name }},{% endfor %}", vars)
      result.should eq("Charlie,Bob,Alice,")
    end

    it "sorts by name alphabetically" do
      items = crinja_hash_array([
        {"name" => "Cherry"},
        {"name" => "Apple"},
        {"name" => "Banana"},
      ])

      vars = {"items" => items}
      result = render_filter("{% for item in items | sort_by(attribute='name') %}{{ item.name }},{% endfor %}", vars)
      result.should eq("Apple,Banana,Cherry,")
    end

    it "returns empty array for non-array input" do
      vars = {"items" => Crinja::Value.new("not an array")}
      result = render_filter("{% for item in items | sort_by(attribute='x') %}found{% endfor %}", vars)
      result.strip.should eq("")
    end

    it "handles missing attribute by treating as empty string" do
      items = crinja_hash_array([
        {"name" => "Bob"},
        {"name" => "Alice", "weight" => "1"},
      ])

      vars = {"items" => items}
      # Missing attribute treated as "", so comes first
      result = render_filter("{% for item in items | sort_by(attribute='weight') %}{{ item.name }},{% endfor %}", vars)
      result.should eq("Bob,Alice,")
    end
  end

  describe "group_by" do
    it "groups array of hashes by attribute" do
      items = crinja_hash_array([
        {"name" => "Alice", "dept" => "eng"},
        {"name" => "Bob", "dept" => "sales"},
        {"name" => "Carol", "dept" => "eng"},
      ])

      vars = {"items" => items}
      result = render_filter(
        "{% for group in items | group_by(attribute='dept') %}{{ group.grouper }}:{% for item in group.list %}{{ item.name }},{% endfor %};{% endfor %}",
        vars
      )
      result.should contain("eng:")
      result.should contain("sales:")
      result.should contain("Alice")
      result.should contain("Bob")
      result.should contain("Carol")
    end

    it "returns empty array for non-array input" do
      vars = {"items" => Crinja::Value.new("not an array")}
      result = render_filter("{% for group in items | group_by(attribute='x') %}found{% endfor %}", vars)
      result.strip.should eq("")
    end

    it "groups items with missing attribute under empty string key" do
      items = crinja_hash_array([
        {"name" => "Alice", "dept" => "eng"},
        {"name" => "Bob"},
      ])

      vars = {"items" => items}
      result = render_filter(
        "{% for group in items | group_by(attribute='dept') %}[{{ group.grouper }}]{% endfor %}",
        vars
      )
      result.should contain("[eng]")
      result.should contain("[]")
    end
  end
end

# =============================================================================
# Date Filters
# =============================================================================
describe "DateFilters" do
  describe "date" do
    it "formats a date string with default format" do
      vars = {"d" => Crinja::Value.new("2024-06-15")}
      result = render_filter("{{ d | date }}", vars)
      result.strip.should eq("2024-06-15")
    end

    it "formats a date string with custom format" do
      vars = {"d" => Crinja::Value.new("2024-06-15")}
      result = render_filter("{{ d | date(format='%Y/%m/%d') }}", vars)
      result.strip.should eq("2024/06/15")
    end

    it "formats a Time value with default format" do
      vars = {"d" => Crinja::Value.new(Time.utc(2024, 3, 20))}
      result = render_filter("{{ d | date }}", vars)
      result.strip.should eq("2024-03-20")
    end

    it "formats a Time value with custom format" do
      vars = {"d" => Crinja::Value.new(Time.utc(2024, 3, 20, 14, 30, 0))}
      result = render_filter("{{ d | date(format='%H:%M') }}", vars)
      result.strip.should eq("14:30")
    end

    it "formats a Time value with year only" do
      vars = {"d" => Crinja::Value.new(Time.utc(2024, 12, 25))}
      result = render_filter("{{ d | date(format='%Y') }}", vars)
      result.strip.should eq("2024")
    end

    it "returns original value for unparseable string" do
      vars = {"d" => Crinja::Value.new("not a date")}
      result = render_filter("{{ d | date }}", vars)
      result.strip.should eq("not a date")
    end

    it "converts non-string non-time values to string" do
      vars = {"d" => Crinja::Value.new(12345)}
      result = render_filter("{{ d | date }}", vars)
      result.strip.should eq("12345")
    end
  end
end

# =============================================================================
# String Filters
# =============================================================================
describe "StringFilters" do
  describe "truncate_words" do
    it "truncates text to specified word count" do
      vars = {"text" => Crinja::Value.new("one two three four five six")}
      result = render_filter("{{ text | truncate_words(length=3) }}", vars)
      result.strip.should eq("one two three...")
    end

    it "does not truncate when text has fewer words than limit" do
      vars = {"text" => Crinja::Value.new("one two")}
      result = render_filter("{{ text | truncate_words(length=5) }}", vars)
      result.strip.should eq("one two")
    end

    it "uses custom ending" do
      vars = {"text" => Crinja::Value.new("one two three four")}
      result = render_filter("{{ text | truncate_words(length=2, end=' [more]') }}", vars)
      result.strip.should eq("one two [more]")
    end

    it "uses default of 50 words" do
      words = (1..60).map { |i| "word#{i}" }.join(" ")
      vars = {"text" => Crinja::Value.new(words)}
      result = render_filter("{{ text | truncate_words }}", vars)
      result.strip.should end_with("...")
      # Should have 50 words + "..."
      result.strip.split(/\s+/).size.should be <= 51
    end

    it "handles empty string" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("{{ text | truncate_words(length=5) }}", vars)
      result.strip.should eq("")
    end

    it "handles single word" do
      vars = {"text" => Crinja::Value.new("hello")}
      result = render_filter("{{ text | truncate_words(length=1) }}", vars)
      result.strip.should eq("hello")
    end
  end

  describe "slugify" do
    it "converts text to URL slug" do
      vars = {"text" => Crinja::Value.new("Hello World")}
      result = render_filter("{{ text | slugify }}", vars)
      result.strip.should eq("hello-world")
    end

    it "removes special characters" do
      vars = {"text" => Crinja::Value.new("Hello! World? #2024")}
      result = render_filter("{{ text | slugify }}", vars)
      result.strip.should eq("hello-world-2024")
    end

    it "handles multiple spaces and hyphens" do
      vars = {"text" => Crinja::Value.new("  hello   world  ")}
      result = render_filter("{{ text | slugify }}", vars)
      result.strip.should eq("hello-world")
    end

    it "handles empty string" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("{{ text | slugify }}", vars)
      result.strip.should eq("")
    end

    it "preserves numbers" do
      vars = {"text" => Crinja::Value.new("Part 3 of 10")}
      result = render_filter("{{ text | slugify }}", vars)
      result.strip.should eq("part-3-of-10")
    end
  end

  describe "split" do
    it "splits string by default separator (comma)" do
      vars = {"text" => Crinja::Value.new("a, b, c")}
      result = render_filter("{% for item in text | split %}[{{ item }}]{% endfor %}", vars)
      result.should contain("[a]")
      result.should contain("[b]")
      result.should contain("[c]")
    end

    it "splits string by custom separator" do
      vars = {"text" => Crinja::Value.new("a|b|c")}
      result = render_filter("{% for item in text | split(pat='|') %}[{{ item }}]{% endfor %}", vars)
      result.should contain("[a]")
      result.should contain("[b]")
      result.should contain("[c]")
    end

    it "returns single-element array when separator not found" do
      vars = {"text" => Crinja::Value.new("hello")}
      result = render_filter("{{ text | split(pat='|') | length }}", vars)
      result.strip.should eq("1")
    end

    it "handles empty string" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("{{ text | split | length }}", vars)
      result.strip.should eq("1")
    end
  end

  describe "trim" do
    it "removes leading and trailing whitespace" do
      vars = {"text" => Crinja::Value.new("  hello  ")}
      result = render_filter("[{{ text | trim }}]", vars)
      result.strip.should eq("[hello]")
    end

    it "handles string with no extra whitespace" do
      vars = {"text" => Crinja::Value.new("hello")}
      result = render_filter("[{{ text | trim }}]", vars)
      result.strip.should eq("[hello]")
    end

    it "handles string with only whitespace" do
      vars = {"text" => Crinja::Value.new("   ")}
      result = render_filter("[{{ text | trim }}]", vars)
      result.strip.should eq("[]")
    end

    it "preserves internal whitespace" do
      vars = {"text" => Crinja::Value.new("  hello world  ")}
      result = render_filter("[{{ text | trim }}]", vars)
      result.strip.should eq("[hello world]")
    end

    it "handles tabs and newlines" do
      vars = {"text" => Crinja::Value.new("\thello\n")}
      result = render_filter("[{{ text | trim }}]", vars)
      result.strip.should eq("[hello]")
    end
  end
end

# =============================================================================
# Misc Filters
# =============================================================================
describe "MiscFilters" do
  describe "jsonify" do
    it "encodes a string as JSON" do
      vars = {"text" => Crinja::Value.new("hello world")}
      result = render_filter("{{ text | jsonify }}", vars)
      result.strip.should eq("\"hello world\"")
    end

    it "encodes a string with special characters" do
      vars = {"text" => Crinja::Value.new("say \"hello\"")}
      result = render_filter("{{ text | jsonify }}", vars)
      result.strip.should contain("\\\"")
    end

    it "encodes empty string" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("{{ text | jsonify }}", vars)
      result.strip.should eq("\"\"")
    end
  end

  describe "default" do
    it "returns original value when not empty" do
      vars = {"text" => Crinja::Value.new("hello")}
      result = render_filter("{{ text | default(value='fallback') }}", vars)
      result.strip.should eq("hello")
    end

    it "returns default value when empty string" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("{{ text | default(value='fallback') }}", vars)
      result.strip.should eq("fallback")
    end

    it "returns default value for undefined variable" do
      result = render_filter("{{ undefined_var | default(value='fallback') }}")
      result.strip.should eq("fallback")
    end

    it "uses empty string as default when no value specified" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("[{{ text | default }}]", vars)
      result.strip.should eq("[]")
    end

    it "returns original numeric value as string when not empty" do
      vars = {"num" => Crinja::Value.new(42)}
      result = render_filter("{{ num | default(value='zero') }}", vars)
      result.strip.should eq("42")
    end
  end
end

# =============================================================================
# HTML Filters
# =============================================================================
describe "HtmlFilters" do
  describe "strip_html" do
    it "removes HTML tags" do
      vars = {"html" => Crinja::Value.new("<p>Hello <b>World</b></p>")}
      result = render_filter("{{ html | strip_html }}", vars)
      result.strip.should eq("Hello World")
    end

    it "removes self-closing tags" do
      vars = {"html" => Crinja::Value.new("Hello<br/>World")}
      result = render_filter("{{ html | strip_html }}", vars)
      # TextUtils.strip_html inserts space at tag boundaries for word separation
      result.strip.should eq("Hello World")
    end

    it "handles text without HTML" do
      vars = {"html" => Crinja::Value.new("plain text")}
      result = render_filter("{{ html | strip_html }}", vars)
      result.strip.should eq("plain text")
    end

    it "handles empty string" do
      vars = {"html" => Crinja::Value.new("")}
      result = render_filter("{{ html | strip_html }}", vars)
      result.strip.should eq("")
    end

    it "removes nested tags" do
      vars = {"html" => Crinja::Value.new("<div><p><span>deep</span></p></div>")}
      result = render_filter("{{ html | strip_html }}", vars)
      result.strip.should eq("deep")
    end

    it "removes tags with attributes" do
      vars = {"html" => Crinja::Value.new("<a href=\"https://example.com\" class=\"link\">Click</a>")}
      result = render_filter("{{ html | strip_html }}", vars)
      result.strip.should eq("Click")
    end
  end

  describe "markdownify" do
    it "converts markdown to HTML" do
      vars = {"md" => Crinja::Value.new("**bold**")}
      result = render_filter("{{ md | markdownify }}", vars)
      result.should contain("<strong>bold</strong>")
    end

    it "converts markdown headings" do
      vars = {"md" => Crinja::Value.new("# Title")}
      result = render_filter("{{ md | markdownify }}", vars)
      result.should contain("<h1>")
      result.should contain("Title")
    end

    it "converts markdown links" do
      vars = {"md" => Crinja::Value.new("[link](https://example.com)")}
      result = render_filter("{{ md | markdownify }}", vars)
      result.should contain("<a href=\"https://example.com\">link</a>")
    end

    it "handles plain text" do
      vars = {"md" => Crinja::Value.new("plain text")}
      result = render_filter("{{ md | markdownify }}", vars)
      result.should contain("plain text")
    end

    it "converts markdown lists" do
      vars = {"md" => Crinja::Value.new("- item1\n- item2")}
      result = render_filter("{{ md | markdownify }}", vars)
      result.should contain("<li>")
      result.should contain("item1")
      result.should contain("item2")
    end
  end

  describe "xml_escape" do
    it "escapes ampersand" do
      vars = {"text" => Crinja::Value.new("Tom & Jerry")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should eq("Tom &amp; Jerry")
    end

    it "escapes angle brackets" do
      vars = {"text" => Crinja::Value.new("<script>alert('xss')</script>")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should contain("&lt;script&gt;")
      result.strip.should contain("&lt;/script&gt;")
    end

    it "escapes double quotes" do
      vars = {"text" => Crinja::Value.new("say \"hello\"")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should contain("&quot;")
    end

    it "escapes single quotes" do
      vars = {"text" => Crinja::Value.new("it's")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should contain("&apos;")
    end

    it "handles text without special characters" do
      vars = {"text" => Crinja::Value.new("hello world")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should eq("hello world")
    end

    it "handles empty string" do
      vars = {"text" => Crinja::Value.new("")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should eq("")
    end

    it "escapes multiple special characters" do
      vars = {"text" => Crinja::Value.new("<a href=\"url\">M&M's</a>")}
      result = render_filter("{{ text | xml_escape }}", vars)
      result.strip.should contain("&lt;")
      result.strip.should contain("&gt;")
      result.strip.should contain("&amp;")
      result.strip.should contain("&quot;")
      result.strip.should contain("&apos;")
    end
  end

  describe "safe" do
    it "marks content as safe (no escaping)" do
      vars = {"html" => Crinja::Value.new("<b>bold</b>")}
      result = render_filter("{{ html | safe }}", vars)
      result.strip.should eq("<b>bold</b>")
    end

    it "preserves HTML entities" do
      vars = {"html" => Crinja::Value.new("<p class=\"test\">hello</p>")}
      result = render_filter("{{ html | safe }}", vars)
      result.strip.should eq("<p class=\"test\">hello</p>")
    end
  end
end

# =============================================================================
# URL Filters
# =============================================================================
describe "UrlFilters" do
  describe "absolute_url" do
    it "prepends base_url to relative path starting with /" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "/blog/post/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | absolute_url }}", context)
      result.strip.should eq("https://example.com/blog/post/")
    end

    it "prepends base_url with slash to relative path without leading /" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "blog/post/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | absolute_url }}", context)
      result.strip.should eq("https://example.com/blog/post/")
    end

    it "returns absolute URL unchanged" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "https://other.com/page/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | absolute_url }}", context)
      result.strip.should eq("https://other.com/page/")
    end

    it "returns http URL unchanged" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "http://other.com/page/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | absolute_url }}", context)
      result.strip.should eq("http://other.com/page/")
    end

    it "strips trailing slash from base_url to avoid double slash" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "/about/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | absolute_url }}", context)
      result.strip.should eq("https://example.com/about/")
    end
  end

  describe "relative_url" do
    it "returns path-only URL (strips protocol and host)" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "/blog/post/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | relative_url }}", context)
      result.strip.should eq("/blog/post/")
    end

    it "returns path without leading / unchanged" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "blog/post/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | relative_url }}", context)
      result.strip.should eq("blog/post/")
    end

    it "includes base_url path component" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com/subdir/"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("my_url", "/about/")

      result = Hwaro::Content::Processors::Template.process("{{ my_url | relative_url }}", context)
      result.strip.should eq("/subdir/about/")
    end
  end
end

# =============================================================================
# Filter Chaining
# =============================================================================
describe "Filter Chaining" do
  it "chains strip_html and truncate_words" do
    vars = {"html" => Crinja::Value.new("<p>one</p> <p>two</p> <p>three</p> <p>four</p> <p>five</p>")}
    result = render_filter("{{ html | strip_html | truncate_words(length=3) }}", vars)
    result.strip.should end_with("...")
  end

  it "chains slugify and truncate_words" do
    vars = {"text" => Crinja::Value.new("Hello Beautiful World")}
    result = render_filter("{{ text | slugify }}", vars)
    result.strip.should eq("hello-beautiful-world")
  end

  it "chains split and length" do
    vars = {"text" => Crinja::Value.new("a,b,c,d")}
    result = render_filter("{{ text | split | length }}", vars)
    result.strip.should eq("4")
  end

  it "chains default and trim" do
    vars = {"text" => Crinja::Value.new("")}
    result = render_filter("[{{ text | default(value='  hello  ') | trim }}]", vars)
    result.strip.should eq("[hello]")
  end

  it "chains xml_escape and safe" do
    vars = {"text" => Crinja::Value.new("Tom & Jerry")}
    result = render_filter("{{ text | xml_escape | safe }}", vars)
    result.strip.should eq("Tom &amp; Jerry")
  end

  it "chains where and sort_by on collections" do
    items = crinja_hash_array([
      {"name" => "Charlie", "role" => "admin", "weight" => "3"},
      {"name" => "Alice", "role" => "admin", "weight" => "1"},
      {"name" => "Bob", "role" => "user", "weight" => "2"},
      {"name" => "Diana", "role" => "admin", "weight" => "2"},
    ])

    vars = {"items" => items}
    result = render_filter(
      "{% for item in items | where(attribute='role', value='admin') | sort_by(attribute='weight') %}{{ item.name }},{% endfor %}",
      vars
    )
    result.should eq("Alice,Diana,Charlie,")
  end
end

# =============================================================================
# Collection Filters — unique, flatten, compact
# =============================================================================
describe "CollectionFilters (extended)" do
  describe "unique" do
    it "removes duplicate values from an array" do
      items = Crinja::Value.new([1, 2, 2, 3, 1].map { |n| Crinja::Value.new(n) })
      vars = {"items" => items}
      result = render_filter("{% for i in items | unique %}{{ i }},{% endfor %}", vars)
      result.should eq("1,2,3,")
    end

    it "removes duplicate strings" do
      items = Crinja::Value.new(["a", "b", "a", "c"].map { |s| Crinja::Value.new(s) })
      vars = {"items" => items}
      result = render_filter("{% for i in items | unique %}{{ i }},{% endfor %}", vars)
      result.should eq("a,b,c,")
    end

    it "returns empty array for empty input" do
      items = Crinja::Value.new([] of Crinja::Value)
      vars = {"items" => items}
      result = render_filter("{% for i in items | unique %}{{ i }}{% endfor %}", vars)
      result.should eq("")
    end
  end

  describe "flatten" do
    it "flattens nested arrays one level" do
      inner1 = Crinja::Value.new([Crinja::Value.new(1), Crinja::Value.new(2)])
      inner2 = Crinja::Value.new([Crinja::Value.new(3)])
      items = Crinja::Value.new([inner1, inner2])
      vars = {"items" => items}
      result = render_filter("{% for i in items | flatten %}{{ i }},{% endfor %}", vars)
      result.should eq("1,2,3,")
    end

    it "passes through non-array items" do
      inner = Crinja::Value.new([Crinja::Value.new(1), Crinja::Value.new(2)])
      scalar = Crinja::Value.new("hello")
      items = Crinja::Value.new([inner, scalar])
      vars = {"items" => items}
      result = render_filter("{% for i in items | flatten %}{{ i }},{% endfor %}", vars)
      result.should eq("1,2,hello,")
    end
  end

  describe "compact" do
    it "removes nil values from an array" do
      items = Crinja::Value.new([Crinja::Value.new("a"), Crinja::Value.new(nil), Crinja::Value.new("b")])
      vars = {"items" => items}
      result = render_filter("{% for i in items | compact %}{{ i }},{% endfor %}", vars)
      result.should eq("a,b,")
    end

    it "removes empty string values" do
      items = Crinja::Value.new([Crinja::Value.new("a"), Crinja::Value.new(""), Crinja::Value.new("b")])
      vars = {"items" => items}
      result = render_filter("{% for i in items | compact %}{{ i }},{% endfor %}", vars)
      result.should eq("a,b,")
    end
  end
end

# =============================================================================
# Math Filters — ceil, floor
# =============================================================================
describe "MathFilters" do
  describe "ceil" do
    it "rounds up a float" do
      vars = {"val" => Crinja::Value.new(3.2)}
      result = render_filter("{{ val | ceil }}", vars)
      result.should eq("4")
    end

    it "returns same value for integer" do
      vars = {"val" => Crinja::Value.new(5.0)}
      result = render_filter("{{ val | ceil }}", vars)
      result.should eq("5")
    end

    it "rounds up negative float towards zero" do
      vars = {"val" => Crinja::Value.new(-2.3)}
      result = render_filter("{{ val | ceil }}", vars)
      result.should eq("-2")
    end
  end

  describe "floor" do
    it "rounds down a float" do
      vars = {"val" => Crinja::Value.new(3.7)}
      result = render_filter("{{ val | floor }}", vars)
      result.should eq("3")
    end

    it "returns same value for integer" do
      vars = {"val" => Crinja::Value.new(5.0)}
      result = render_filter("{{ val | floor }}", vars)
      result.should eq("5")
    end

    it "rounds down negative float away from zero" do
      vars = {"val" => Crinja::Value.new(-2.3)}
      result = render_filter("{{ val | floor }}", vars)
      result.should eq("-3")
    end
  end
end

# =============================================================================
# Misc Filters — inspect
# =============================================================================
describe "MiscFilters (extended)" do
  describe "inspect" do
    it "inspects a string value" do
      vars = {"val" => Crinja::Value.new("hello")}
      result = render_filter("{{ val | inspect }}", vars)
      result.should eq("\"hello\"")
    end

    it "inspects nil value" do
      vars = {"val" => Crinja::Value.new(nil)}
      result = render_filter("{{ val | inspect }}", vars)
      result.should eq("nil")
    end

    it "inspects a number" do
      vars = {"val" => Crinja::Value.new(42)}
      result = render_filter("{{ val | inspect }}", vars)
      result.should eq("42")
    end

    it "inspects an array" do
      items = Crinja::Value.new([Crinja::Value.new("a"), Crinja::Value.new("b")])
      vars = {"val" => items}
      result = render_filter("{{ val | inspect }}", vars)
      result.should eq("[a, b]")
    end

    it "inspects a boolean" do
      vars = {"val" => Crinja::Value.new(true)}
      result = render_filter("{{ val | inspect }}", vars)
      result.should eq("true")
    end
  end
end
