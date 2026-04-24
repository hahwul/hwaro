require "./support/build_helper"

# =============================================================================
# Data file loading functional tests
#
# Verifies YAML, TOML, and mixed-format data files are loaded correctly
# and accessible via site.data in templates.
# =============================================================================

describe "Data Files: YAML data loading" do
  it "loads YAML data files and exposes via site.data" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "{% for item in site.data.nav %}{{ item.name }},{% endfor %}",
      },
      data_files: {
        "nav.yml" => "- name: Home\n  url: /\n- name: Blog\n  url: /blog/",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("Home,")
      html.should contain("Blog,")
    end
  end

  it "loads .yaml extension data files" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "THEME={{ site.data.settings.theme }}|LANG={{ site.data.settings.language }}",
      },
      data_files: {
        "settings.yaml" => "theme: dark\nlanguage: en",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("THEME=dark")
      html.should contain("LANG=en")
    end
  end
end

describe "Data Files: TOML data loading" do
  it "loads TOML data files and exposes via site.data" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "NAME={{ site.data.site_info.name }}|VERSION={{ site.data.site_info.version }}",
      },
      data_files: {
        "site_info.toml" => "name = \"My Site\"\nversion = \"1.0\"",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("NAME=My Site")
      html.should contain("VERSION=1.0")
    end
  end
end

describe "Data Files: Mixed format data files" do
  it "loads JSON, YAML, and TOML data files simultaneously" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "JSON={% for i in site.data.items %}{{ i.name }},{% endfor %}|YAML={{ site.data.config.theme }}|TOML={{ site.data.meta.author }}",
      },
      data_files: {
        "items.json" => "[{\"name\": \"Alpha\"}, {\"name\": \"Beta\"}]",
        "config.yml" => "theme: minimal\ncolor: blue",
        "meta.toml"  => "author = \"hahwul\"\nlicense = \"MIT\"",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("Alpha,")
      html.should contain("Beta,")
      html.should contain("YAML=minimal")
      html.should contain("TOML=hahwul")
    end
  end
end

describe "Data Files: Nested YAML data" do
  it "accesses nested YAML data structures in templates" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "{% for social in site.data.social %}{{ social.platform }}:{{ social.url }},{% endfor %}",
      },
      data_files: {
        "social.yml" => "- platform: twitter\n  url: https://twitter.com/example\n- platform: github\n  url: https://github.com/example",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("twitter:https://twitter.com/example,")
      html.should contain("github:https://github.com/example,")
    end
  end
end

describe "Data Files: Subdirectory data loading" do
  it "exposes files under data/<dir>/ as an iterable map and per-file keys" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "{% for name, u in site.data.users %}{{ name }}:{{ u.age }},{% endfor %}|alice_age={{ site.data.users.alice.age }}",
      },
      data_files: {
        "users/alice.yml" => "age: 30",
        "users/bob.yml"   => "age: 25",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("alice:30,")
      html.should contain("bob:25,")
      html.should contain("alice_age=30")
    end
  end

  it "supports deeply nested subdirectories" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "LEVEL={{ site.data.users.admins.root.level }}",
      },
      data_files: {
        "users/admins/root.yml" => "level: 99",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("LEVEL=99")
    end
  end

  it "loads subdirectory files across formats" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "J={{ site.data.api.v1.version }}|T={{ site.data.api.v2.version }}",
      },
      data_files: {
        "api/v1.json" => %({"version": "1.0"}),
        "api/v2.toml" => %(version = "2.0"),
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("J=1.0")
      html.should contain("T=2.0")
    end
  end

  it "keeps root-level and subdirectory data independent" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {
        "page.html" => "THEME={{ site.data.settings.theme }}|USER={{ site.data.users.alice.age }}",
      },
      data_files: {
        "settings.yml"    => "theme: dark",
        "users/alice.yml" => "age: 30",
      },
    ) do
      html = File.read("public/index.html")
      html.should contain("THEME=dark")
      html.should contain("USER=30")
    end
  end
end

describe "Data Files: No data directory" do
  it "builds successfully without data directory" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/index.html").should be_true
    end
  end
end
