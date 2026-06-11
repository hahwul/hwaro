require "./support/build_helper"

# =============================================================================
# Template errors must point at the source file (file:line:col + excerpt),
# not an anonymous `<string>` template. Compiled templates carry their
# filename via Builder#compile_template / @template_paths.
# =============================================================================

describe "Template error location reporting" do
  it "reports file:line:col and a source excerpt for runtime errors" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
        template_files: {
          "page.html" => "<html>\n<body>\n{{ page.title.nonexistent_attr }}\n</body>\n</html>",
        },
      ) { }
    end

    err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    message = err.message.not_nil!
    message.should contain("templates/page.html:3:")
    # Source excerpt with caret marker
    message.should contain("{{ page.title.nonexistent_attr }}")
    message.should contain("^")
  end

  it "reports file:line:col for parse-time syntax errors (unclosed tag)" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
        template_files: {
          "page.html" => "<html>\n{% if page.title %}\n{{ content }}\n</html>",
        },
      ) { }
    end

    err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    message = err.message.not_nil!
    message.should contain("Unclosed tag")
    message.should contain("templates/page.html:2:1")
  end

  it "names the template file even for location-less parse errors" do
    # `{% endfi %}` trips an unknown-tag library lookup, which Crinja raises
    # as a RuntimeError without location or template attached. The compile
    # path attaches a stub template so the file is still named.
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
        template_files: {
          "page.html" => "<html>\n{% if page.title %}\n{{ content }}\n{% endfi %}\n</html>",
        },
      ) { }
    end

    err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    err.message.not_nil!.should contain("templates/page.html")
  end

  it "reports the included template's filename when the error is inside an include" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
        template_files: {
          "page.html"          => "<html>\n{% include \"partials/head.html\" %}\n{{ content }}\n</html>",
          "partials/head.html" => "<head>\n{{ missing_var.attr }}\n</head>",
        },
      ) { }
    end

    err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    # Included templates load through Crinja's FileSystemLoader, which
    # attaches their own filename to errors raised inside them.
    err.message.not_nil!.should contain("partials/head.html")
  end
end
