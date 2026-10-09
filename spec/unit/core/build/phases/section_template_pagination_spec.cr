require "../../../../spec_helper"
require "../../../../support/build_helper"

# A section that names its own template (`template = "blogindex"`, or one
# inherited through `[cascade]`) is still a section: it paginates and gets
# `section_list`/`paginator` like the built-in `section` template does.
private def paginated_posts(template_line : String, &)
  content = {"posts/_index.md" => "+++\ntitle = \"Posts\"\npaginate = 2\n#{template_line}+++\n"}
  (1..5).each { |i| content["posts/p#{i}.md"] = "+++\ntitle = \"P#{i}\"\ndate = 2024-01-0#{i}\n+++\nbody" }
  templates = {
    "page.html"      => "{{ content }}",
    "section.html"   => "DEFAULT list={{ section_list | length }} pagers={{ paginator.number_pagers }}",
    "blogindex.html" => "CUSTOM list={{ section_list | length }} pagers={{ paginator.number_pagers }}",
  }
  build_site(BASIC_CONFIG, content_files: content, template_files: templates) { |dir| yield dir }
end

describe "section pagination with a custom template" do
  it "paginates a section that sets template = \"blogindex\"" do
    paginated_posts("template = \"blogindex\"\n") do |dir|
      first = File.read(File.join(dir, "public/posts/index.html"))
      first.should contain("CUSTOM")
      first.should contain("pagers=3")
      first.should_not contain("list=0")
      File.exists?(File.join(dir, "public/posts/page/2/index.html")).should be_true
      File.exists?(File.join(dir, "public/posts/page/3/index.html")).should be_true
    end
  end

  it "still paginates a section on the built-in template" do
    paginated_posts("") do |dir|
      File.read(File.join(dir, "public/posts/index.html")).should contain("DEFAULT")
      File.exists?(File.join(dir, "public/posts/page/3/index.html")).should be_true
    end
  end

  it "leaves a custom-template section alone under the site-wide [pagination] default" do
    content = {"posts/_index.md" => "+++\ntitle = \"Posts\"\ntemplate = \"blogindex\"\n+++\n"}
    (1..5).each { |i| content["posts/p#{i}.md"] = "+++\ntitle = \"P#{i}\"\ndate = 2024-01-0#{i}\n+++\nbody" }
    templates = {
      "page.html"      => "{{ content }}",
      "section.html"   => "DEFAULT",
      "blogindex.html" => "CUSTOM count={{ section.pages_count }}",
    }
    config = BASIC_CONFIG + "\n[pagination]\nenabled = true\nper_page = 2\n"
    build_site(config, content_files: content, template_files: templates) do |dir|
      File.read(File.join(dir, "public/posts/index.html")).should contain("CUSTOM count=5")
      File.exists?(File.join(dir, "public/posts/page/2/index.html")).should be_false
    end
  end
end
