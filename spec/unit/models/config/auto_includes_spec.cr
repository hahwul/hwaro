require "../../../spec_helper"
require "../../../support/build_helper"

describe Hwaro::Models::AutoIncludesConfig do
  it "only links Sass entries whose source can be published" do
    posix_only!("symlinks")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        Dir.mkdir_p("static/css")
        File.write(".env", ".private { color: red; }")
        File.symlink("../../.env", "static/css/private.scss")
        File.write("theme.scss", ".theme { color: blue; }")
        File.symlink("../../theme.scss", "static/css/theme.scss")

        config = Hwaro::Models::AutoIncludesConfig.new
        config.enabled = true
        config.dirs = ["css"]
        config.sass_enabled = true
        tags = config.css_tags
        tags.should contain("/css/theme.css")
        tags.should_not contain("/css/private.css")
      end
    end
  end

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

  it "percent-encodes file names that would otherwise end the URL path" do
    posix_only!("Windows forbids ? in file names")
    config = <<-TOML
      title = "t"
      base_url = "http://x.test/sub"
      [auto_includes]
      enabled = true
      dirs = ["css"]
      TOML
    build_site(
      config,
      content_files: {"index.md" => "+++\ntitle = \"h\"\n+++\n"},
      template_files: {"page.html" => "{{ auto_includes_css }}", "section.html" => "{{ auto_includes_css }}"},
      static_files: {"css/a#b.css" => "a{}", "css/q?x.css" => "a{}", "css/100%.css" => "a{}", "css/my style.css" => "a{}", "css/plain.css" => "a{}"},
    ) do
      html = File.read("public/index.html")
      html.should contain(%(href="http://x.test/sub/css/a%23b.css))
      html.should contain("/sub/css/q%3Fx.css")
      html.should contain("/sub/css/100%25.css")
      html.should contain("/sub/css/my%20style.css")
      html.should contain("/sub/css/plain.css")
    end
  end
end
