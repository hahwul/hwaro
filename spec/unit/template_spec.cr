require "../spec_helper"

describe Hwaro::Content::Processors::Template do
  describe ".process" do
    it "processes simple if condition (true)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_url == "/about/" %>
      <p>About page</p>
      <% end %>
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
      <% if page_url == "/about/" %>
      <p>About page</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>About page</p>")
    end

    it "processes unless condition (true - should not show)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% unless page_url == "/about/" %>
      <p>Not about page</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Not about page</p>")
    end

    it "processes unless condition (false - should show)" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/contact/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% unless page_url == "/about/" %>
      <p>Not about page</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Not about page</p>")
    end

    it "processes if/else condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_url == "/about/" %>
      <p>About page</p>
      <% else %>
      <p>Other page</p>
      <% end %>
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
      <% if page_url == "/about/" %>
      <p>About page</p>
      <% else %>
      <p>Other page</p>
      <% end %>
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
      <% if page_section != "docs" %>
      <p>Not docs</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Not docs</p>")
    end

    it "processes starts_with? condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/blog/my-post/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_url.starts_with?("/blog/") %>
      <p>Blog post</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Blog post</p>")
    end

    it "processes ends_with? condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Welcome!"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_title.ends_with?("!") %>
      <p>Exciting!</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Exciting!</p>")
    end

    it "processes includes? condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/products/software/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_url.includes?("products") %>
      <p>Product page</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Product page</p>")
    end

    it "processes empty? condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = nil
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_description.empty? %>
      <p>No description</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>No description</p>")
    end

    it "processes present? condition" do
      page = Hwaro::Models::Page.new("test.md")
      page.description = "A great page"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_description.present? %>
      <p>Has description</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Has description</p>")
    end

    it "processes negation with !" do
      page = Hwaro::Models::Page.new("test.md")
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if !page.draft %>
      <p>Published</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Published</p>")
    end

    it "processes boolean property page.draft" do
      page = Hwaro::Models::Page.new("test.md")
      page.draft = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page.draft %>
      <p>Draft</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Draft</p>")
    end

    it "processes boolean property page.toc" do
      page = Hwaro::Models::Page.new("test.md")
      page.toc = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page.toc %>
      <p>Show TOC</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Show TOC</p>")
    end

    it "processes nested conditionals" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" %>
      <div class="blog">
        <% if !page.draft %>
        <p>Published blog post</p>
        <% end %>
      </div>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<div class=\"blog\">")
      result.should contain("<p>Published blog post</p>")
    end

    it "handles multiple independent conditionals" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      page.toc = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" %>
      <p>Blog section</p>
      <% end %>
      <% if page.toc %>
      <p>Has TOC</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Blog section</p>")
      result.should contain("<p>Has TOC</p>")
    end

    it "processes if/elsif condition (first branch)" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" %>
      <p>Blog section</p>
      <% elsif page_section == "docs" %>
      <p>Docs section</p>
      <% else %>
      <p>Other section</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Blog section</p>")
      result.should_not contain("<p>Docs section</p>")
      result.should_not contain("<p>Other section</p>")
    end

    it "processes if/elsif condition (elsif branch)" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "docs"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" %>
      <p>Blog section</p>
      <% elsif page_section == "docs" %>
      <p>Docs section</p>
      <% else %>
      <p>Other section</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Blog section</p>")
      result.should contain("<p>Docs section</p>")
      result.should_not contain("<p>Other section</p>")
    end

    it "processes if/elsif condition (else branch)" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "about"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" %>
      <p>Blog section</p>
      <% elsif page_section == "docs" %>
      <p>Docs section</p>
      <% else %>
      <p>Other section</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Blog section</p>")
      result.should_not contain("<p>Docs section</p>")
      result.should contain("<p>Other section</p>")
    end

    it "processes multiple elsif branches" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "tutorials"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" %>
      <p>Blog</p>
      <% elsif page_section == "docs" %>
      <p>Docs</p>
      <% elsif page_section == "tutorials" %>
      <p>Tutorials</p>
      <% elsif page_section == "api" %>
      <p>API</p>
      <% else %>
      <p>Other</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Blog</p>")
      result.should_not contain("<p>Docs</p>")
      result.should contain("<p>Tutorials</p>")
      result.should_not contain("<p>API</p>")
      result.should_not contain("<p>Other</p>")
    end

    it "preserves content outside conditionals" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/about/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <header>Header</header>
      <% if page_url == "/about/" %>
      <p>About</p>
      <% end %>
      <footer>Footer</footer>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<header>Header</header>")
      result.should contain("<p>About</p>")
      result.should contain("<footer>Footer</footer>")
    end
  end
end

describe Hwaro::Content::Processors::TemplateContext do
  describe "#get_string" do
    it "returns page_url" do
      page = Hwaro::Models::Page.new("test.md")
      page.url = "/test/"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.get_string("page_url").should eq("/test/")
    end

    it "returns page_section" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.get_string("page_section").should eq("blog")
    end

    it "returns site_title" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new
      config.title = "My Site"

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.get_string("site_title").should eq("My Site")
    end

    it "returns nil for unknown variable" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.get_string("unknown").should be_nil
    end
  end

  describe "#truthy?" do
    it "returns true for page.draft when draft is true" do
      page = Hwaro::Models::Page.new("test.md")
      page.draft = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.truthy?("page.draft").should be_true
    end

    it "returns false for page.draft when draft is false" do
      page = Hwaro::Models::Page.new("test.md")
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.truthy?("page.draft").should be_false
    end

    it "returns true for non-empty string variable" do
      page = Hwaro::Models::Page.new("test.md")
      page.title = "Hello"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.truthy?("page_title").should be_true
    end

    it "returns false for unknown variable" do
      page = Hwaro::Models::Page.new("test.md")
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)
      context.truthy?("unknown_var").should be_false
    end
  end
end

describe "Logical operators" do
  describe "&& (AND)" do
    it "evaluates true && true as true" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" && !page.draft %>
      <p>Published blog post</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Published blog post</p>")
    end

    it "evaluates true && false as false" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      page.draft = true
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" && !page.draft %>
      <p>Published blog post</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Published blog post</p>")
    end

    it "evaluates false && true as false" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "docs"
      page.draft = false
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" && !page.draft %>
      <p>Published blog post</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Published blog post</p>")
    end
  end

  describe "|| (OR)" do
    it "evaluates true || false as true" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "blog"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" || page_section == "news" %>
      <p>Content section</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Content section</p>")
    end

    it "evaluates false || true as true" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "news"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" || page_section == "news" %>
      <p>Content section</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should contain("<p>Content section</p>")
    end

    it "evaluates false || false as false" do
      page = Hwaro::Models::Page.new("test.md")
      page.section = "about"
      config = Hwaro::Models::Config.new

      context = Hwaro::Content::Processors::TemplateContext.new(page, config)

      template = <<-TPL
      <% if page_section == "blog" || page_section == "news" %>
      <p>Content section</p>
      <% end %>
      TPL

      result = Hwaro::Content::Processors::Template.process(template, context)
      result.should_not contain("<p>Content section</p>")
    end
  end
end
