require "./support/build_helper"

private SASS_CONFIG = <<-TOML
title = "Sass Test"
base_url = "https://example.com"

[sass]
enabled = true
minify = false
TOML

private INDEX_MD      = "# Hello\n"
private PAGE_TEMPLATE = "<html><body>{{ content }}</body></html>"

describe "Sass build integration" do
  it "compiles static scss entries to sibling css and drops raw sources" do
    build_site(
      SASS_CONFIG,
      content_files: {"index.md" => INDEX_MD},
      template_files: {"index.html" => PAGE_TEMPLATE, "page.html" => PAGE_TEMPLATE},
      static_files: {
        "css/_vars.scss" => "$primary: #123456;",
        "css/style.scss" => "@use \"vars\";\n.app { color: vars.$primary; .nested { margin: 0; } }",
        "css/plain.css"  => ".plain { color: red; }",
      },
    ) do
      css = File.read("public/css/style.css")
      css.should contain(".app {\n  color: #123456;")
      css.should contain(".app .nested {")

      File.exists?("public/css/style.scss").should be_false
      File.exists?("public/css/_vars.scss").should be_false
      File.exists?("public/css/plain.css").should be_true
    end
  end

  it "minifies compiled output when [sass] minify is on" do
    config = SASS_CONFIG.sub("minify = false", "minify = true")
    build_site(
      config,
      content_files: {"index.md" => INDEX_MD},
      template_files: {"index.html" => PAGE_TEMPLATE, "page.html" => PAGE_TEMPLATE},
      static_files: {"css/style.scss" => "$c: red;\n.a { color: $c; }"},
    ) do
      css = File.read("public/css/style.css")
      css.should contain(".a{color:red}")
    end
  end

  it "copies raw scss verbatim when [sass] is disabled (back-compat)" do
    config = <<-TOML
    title = "No Sass"
    base_url = "https://example.com"
    TOML
    build_site(
      config,
      content_files: {"index.md" => INDEX_MD},
      template_files: {"index.html" => PAGE_TEMPLATE, "page.html" => PAGE_TEMPLATE},
      static_files: {"css/style.scss" => "$c: red;\n.a { color: $c; }"},
    ) do
      File.exists?("public/css/style.css").should be_false
      File.read("public/css/style.scss").should contain("$c: red;")
    end
  end

  it "compiles scss entries referenced by asset bundles" do
    config = <<-TOML
    title = "Bundle"
    base_url = "https://example.com"

    [sass]
    enabled = true

    [assets]
    enabled = true
    minify = false
    fingerprint = false

    [[assets.bundles]]
    name = "main.css"
    files = ["css/style.scss", "css/extra.css"]
    TOML
    build_site(
      config,
      content_files: {"index.md" => INDEX_MD},
      template_files: {"index.html" => PAGE_TEMPLATE, "page.html" => PAGE_TEMPLATE},
      static_files: {
        "css/style.scss" => "$c: blue;\n.a { color: $c; }",
        "css/extra.css"  => ".b { color: green; }",
      },
    ) do
      bundle = File.read("public/assets/main.css")
      bundle.should contain("color: blue;")
      bundle.should contain(".b { color: green; }")
      bundle.should_not contain("$c")
    end
  end

  it "fails the build with a located content error on invalid scss" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        SASS_CONFIG,
        content_files: {"index.md" => INDEX_MD},
        template_files: {"index.html" => PAGE_TEMPLATE, "page.html" => PAGE_TEMPLATE},
        static_files: {"css/bad.scss" => ".a {\n  color: $missing;\n}"},
      ) { }
    end
    ex.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
    ex.message.not_nil!.should contain("bad.scss:2:")
    ex.message.not_nil!.should contain("undefined variable")
  end
end
