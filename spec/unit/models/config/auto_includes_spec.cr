require "../../../spec_helper"
require "../../../support/build_helper"

describe Hwaro::Models::AutoIncludesConfig do
  it "skips files [static] exclude keeps out of the build" do
    config = <<-TOML
      title = "t"
      base_url = "http://localhost"
      [auto_includes]
      enabled = true
      dirs = ["assets/css"]
      [static]
      exclude = ["assets/css/10-k.css"]
      TOML
    build_site(
      config,
      content_files: {"index.md" => "+++\ntitle = \"h\"\n+++\n"},
      template_files: {"page.html" => "{{ auto_includes_css }}", "section.html" => "{{ auto_includes_css }}"},
      static_files: {"assets/css/00-a.css" => "a{}", "assets/css/10-k.css" => "k{}"},
    ) do
      html = File.read("public/index.html")
      html.should contain("/assets/css/00-a.css")
      html.should_not contain("10-k.css")
      File.exists?("public/assets/css/10-k.css").should be_false
    end
  end
end
