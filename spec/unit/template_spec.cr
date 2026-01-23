require "../spec_helper"

describe Hwaro::Content::Processors::Template do
  describe ".process" do
    it "processes simple if condition (true)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_url == "/about/" %}
      <p>About page</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>About page</p>")
    end

    it "processes simple if condition (false)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/contact/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_url == "/about/" %}
      <p>About page</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>About page</p>")
    end

    it "processes if/else condition (if branch)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_url == "/about/" %}
      <p>About page</p>
      {% else %}
      <p>Other page</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>About page</p>")
      result.should_not contain("<p>Other page</p>")
    end

    it "processes if/else condition (else branch)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/contact/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_url == "/about/" %}
      <p>About page</p>
      {% else %}
      <p>Other page</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>About page</p>")
      result.should contain("<p>Other page</p>")
    end

    it "processes inequality condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_section != "docs" %}
      <p>Not docs</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Not docs</p>")
    end

    it "processes variable interpolation" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test Page"
      page.url = "/test/"
      page.section = "blog"
      config = Hwaro::Models::Config.new
      config.title = "My Site"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <h1>{{ page_title }}</h1>
      <p>Section: {{ page_section }}</p>
      <p>Site: {{ site_title }}</p>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<h1>Test Page</h1>")
      result.should contain("<p>Section: blog</p>")
      result.should contain("<p>Site: My Site</p>")
    end

    it "processes page object properties" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.draft = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page.draft %}
      <p>Draft</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Draft</p>")
    end

    it "processes page object not draft" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Test"
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if not page.draft %}
      <p>Published</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Published</p>")
    end

    it "processes filters" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "hello world"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <h1>{{ page_title | upper }}</h1>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<h1>HELLO WORLD</h1>")
    end

    it "processes default filter" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = nil
      config = Hwaro::Models::Config.new
      # config.description defaults to nil in the constructor

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("empty_var", nil)

      template = <<-TPL
      <p>{{ empty_var | default("No description") }}</p>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>No description</p>")
    end

    it "processes elif branches" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "docs"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_section == "blog" %}
      <p>Blog</p>
      {% elif page_section == "docs" %}
      <p>Documentation</p>
      {% else %}
      <p>Other</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Blog</p>")
      result.should contain("<p>Documentation</p>")
      result.should_not contain("<p>Other</p>")
    end

    it "processes for loop" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("items", ["apple", "banana", "cherry"])

      template = <<-TPL
      <ul>
      {% for item in items %}
      <li>{{ item }}</li>
      {% endfor %}
      </ul>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<li>apple</li>")
      result.should contain("<li>banana</li>")
      result.should contain("<li>cherry</li>")
    end

    it "processes nested conditionals" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_section == "blog" %}
        {% if not page.draft %}
        <p>Published blog post</p>
        {% endif %}
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Published blog post</p>")
    end

    it "processes logical and condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_section == "blog" and not page.draft %}
      <p>Published blog post</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Published blog post</p>")
    end

    it "processes logical or condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "news"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_section == "blog" or page_section == "news" %}
      <p>Content section</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Content section</p>")
    end

    it "processes string startswith filter" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/blog/my-post/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page_url is startswith("/blog/") %}
      <p>Blog post</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Blog post</p>")
    end

    it "processes empty check with equality" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = nil
      config = Hwaro::Models::Config.new
      # config.description defaults to nil in the constructor

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("empty_var", "")

      template = <<-TPL
      {% if empty_var == "" %}
      <p>No description</p>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>No description</p>")
    end

    it "processes page.toc boolean property" do
      page = Hwaro::Models::Page.new("test.md")
      page.toc = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      {% if page.toc %}
      <div class="toc">Table of Contents</div>
      {% endif %}
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<div class=\"toc\">Table of Contents</div>")
    end

    it "processes base_url variable" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <a href="{{ base_url }}/about/">About</a>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<a href=\"https://example.com/about/\">About</a>")
    end

    it "processes site object" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.title = "My Site"
      config.description = "A great site"
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <h1>{{ site.title }}</h1>
      <p>{{ site.description }}</p>
      <a href="{{ site.base_url }}">Home</a>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<h1>My Site</h1>")
      result.should contain("<p>A great site</p>")
      result.should contain("<a href=\"https://example.com\">Home</a>")
    end

    it "adds custom variables to context" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("custom_var", "custom value")
      context.add("is_special", true)
      context.add("count", 42)

      template = <<-TPL
      <p>{{ custom_var }}</p>
      {% if is_special %}<p>Special!</p>{% endif %}
      <p>Count: {{ count }}</p>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>custom value</p>")
      result.should contain("<p>Special!</p>")
      result.should contain("<p>Count: 42</p>")
    end
  end

  describe "TemplateEngine" do
    it "creates engine with custom filters" do
      engine = Hwaro::Content::Processors::TemplateEngine.new
      engine.env.should_not be_nil
    end

    it "renders template with variables" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Hello World"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      engine = Hwaro::Content::Processors::TemplateEngine.new
      result = engine.render("<h1>{{ page_title }}</h1>", context)

      result.should eq("<h1>Hello World</h1>")
    end
  end

  describe "Custom Filters" do
    it "processes slugify filter" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("text", "Hello World! This is a Test")

      template = "{{ text | slugify }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("hello-world-this-is-a-test")
    end

    it "processes strip_html filter" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("html", "<p>Hello <strong>World</strong></p>")

      template = "{{ html | strip_html }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("Hello World")
    end

    it "processes truncate_words filter" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("text", "one two three four five six seven eight nine ten")

      template = "{{ text | truncate_words(length=5) }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("one two three four five...")
    end

    it "processes xml_escape filter" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.add("text", "<tag attr=\"value\">content</tag>")

      template = "{{ text | xml_escape }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("&lt;tag attr=&quot;value&quot;&gt;content&lt;/tag&gt;")
    end
  end

  describe "Custom Tests" do
    it "processes startswith test" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/blog/post/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{% if page_url is startswith(\"/blog/\") %}yes{% else %}no{% endif %}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("yes")
    end

    it "processes endswith test" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Hello World!"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{% if page_title is endswith(\"!\") %}yes{% else %}no{% endif %}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("yes")
    end

    it "processes containing test" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/products/software/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{% if page_url is containing(\"products\") %}yes{% else %}no{% endif %}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("yes")
    end

    it "processes defined test" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = "A description"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{% if page_title is defined %}yes{% else %}no{% endif %}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("yes")
    end
  end

  describe "Custom Functions" do
    it "processes now function" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{{ now() }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      # Should contain a date-like string
      result.should match(/\d{4}-\d{2}-\d{2}/)
    end

    it "processes url_for function" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.base_url = "https://example.com"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{{ url_for(path=\"/about/\") }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("https://example.com/about/")
    end
  end

  describe "Time-related Variables" do
    it "provides current_year variable" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{{ current_year }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq(Time.local.year.to_s)
    end

    it "provides current_date variable" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{{ current_date }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should match(/\d{4}-\d{2}-\d{2}/)
    end

    it "provides current_datetime variable" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "{{ current_datetime }}"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end

    it "can use current_year in footer copyright" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = "© {{ current_year }} My Site"
      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should eq("© #{Time.local.year} My Site")
    end
  end
end
