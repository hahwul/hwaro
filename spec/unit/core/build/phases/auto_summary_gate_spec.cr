require "../../../../spec_helper"
require "../../../../support/build_helper"

# =============================================================================
# The automatic excerpt is a second markdown render of every page, so it is
# only computed when something can print it (ParseContent#auto_summary_read?).
# Its absence is unobservable in the output by design, so these examples read
# `page.auto_summary` off the builder. The ones expecting nil fail on the
# ungated code, which computed the excerpt for every page.
# =============================================================================

private GATE_BODY = "+++\ntitle = \"A\"\n+++\n\nSome body words for the excerpt.\n"

private def gate_config(extra : String = "") : String
  <<-TOML
    title = "Gate"
    base_url = "http://localhost"
    #{extra}
    TOML
end

private def gate_templates(page : String = "{{ content }}") : Hash(String, String)
  {"page.html" => page, "section.html" => "{{ content }}", "index.html" => "home"}
end

private def gated_page(builder : Hwaro::Core::Build::Builder) : Hwaro::Models::Page
  builder.site.not_nil!.pages.find! { |p| p.title == "A" }
end

private def gate_options : Hwaro::Config::Options::BuildOptions
  Hwaro::Config::Options::BuildOptions.new(output_dir: "public", verbose: false, profile: false)
end

describe "Automatic summary gate" do
  it "skips the excerpt when no template, SEO tag or feed reads it" do
    build_site(gate_config, content_files: {"posts/a.md" => GATE_BODY}, template_files: gate_templates) do |_, builder|
      gated_page(builder).auto_summary.should be_nil
    end
  end

  it "computes it for a template that names summary" do
    build_site(gate_config, content_files: {"posts/a.md" => GATE_BODY},
      template_files: gate_templates("{{ content }}<i>{{ page.summary }}</i>")) do |_, builder|
      gated_page(builder).auto_summary.should eq("Some body words for the excerpt.")
      File.read("public/posts/a/index.html").should contain("<i><p>Some body words for the excerpt.</p></i>")
    end
  end

  it "computes it for templates that read page fields without naming them" do
    {
      "{{ page | tojson }}",
      "{% for k, v in page %}{{ v }}{% endfor %}",
      "{{ page }}",
      "{{ page | list }}",
      "{% for f in site.data.fields %}{{ page[f] }}{% endfor %}",
      "{{ page | attr(field) }}",
    }.each do |template|
      build_site(gate_config, content_files: {"posts/a.md" => GATE_BODY},
        template_files: gate_templates(template)) do |_, builder|
        gated_page(builder).auto_summary.should_not be_nil, template
      end
    end
  end

  it "computes it for og/twitter tags, which fall back to it" do
    build_site(gate_config, content_files: {"posts/a.md" => GATE_BODY},
      template_files: gate_templates("{{ og_all_tags }}{{ content }}")) do |_, builder|
      gated_page(builder).auto_summary.should_not be_nil
    end
  end

  it "computes it for RSS and JSON feeds but not for the built-in Atom writer" do
    {"rss" => true, "json" => true, "atom" => false}.each do |type, read|
      build_site(gate_config("[feeds]\nenabled = true\ntype = \"#{type}\""),
        content_files: {"posts/a.md" => GATE_BODY}, template_files: gate_templates) do |_, builder|
        gated_page(builder).auto_summary.nil?.should eq(!read), type
      end
    end
  end

  it "computes it for a section feed" do
    content = {
      "posts/_index.md" => "+++\ntitle = \"Posts\"\ngenerate_feeds = true\n+++\n",
      "posts/a.md"      => GATE_BODY,
    }
    build_site(gate_config, content_files: content, template_files: gate_templates) do |_, builder|
      gated_page(builder).auto_summary.should_not be_nil
    end
  end

  it "fills every page's excerpt when a serve template edit adds the first reader" do
    content = {
      "posts/_index.md" => "+++\ntitle = \"Posts\"\n+++\n",
      "posts/a.md"      => GATE_BODY,
      "posts/b.md"      => "+++\ntitle = \"B\"\n+++\n\nOther body.\n",
    }
    build_site(gate_config, content_files: content, template_files: gate_templates) do |_, builder|
      gated_page(builder).auto_summary.should be_nil

      # A layout-only edit: on its own it would skip the summary recompute.
      File.write("templates/section.html", "{% for p in section.pages %}[{{ p.title }}={{ p.summary }}]{% endfor %}")
      builder.run_rerender(gate_options).should be_true

      gated_page(builder).auto_summary.should eq("Some body words for the excerpt.")
      File.read("public/posts/index.html").should contain("[A=<p>Some body words for the excerpt.</p>]")
      File.read("public/posts/index.html").should contain("[B=<p>Other body.</p>]")
    end
  end
end
