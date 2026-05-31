require "./support/build_helper"

# =============================================================================
# Highlight self-hosted asset validation
#
# `[highlight] use_cdn = false` makes the templates reference local highlight.js
# assets (/assets/js/highlight.min.js + the theme CSS). Hwaro never ships those
# files, so if the user hasn't placed them under static/ the references 404 and
# syntax highlighting silently breaks. The build should warn instead.
# =============================================================================

private def capture_build_logs(&) : String
  io = IO::Memory.new
  prev = Hwaro::Logger.io
  Hwaro::Logger.io = io
  begin
    yield
  ensure
    Hwaro::Logger.io = prev
  end
  io.to_s
end

private SELF_HOSTED_HIGHLIGHT_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"

  [highlight]
  enabled = true
  use_cdn = false
  theme = "github"
  TOML

describe "Highlight: self-hosted asset validation" do
  it "warns when use_cdn = false but the local highlight assets are missing" do
    logs = capture_build_logs do
      build_site(
        SELF_HOSTED_HIGHLIGHT_CONFIG,
        content_files: {"page.md" => "---\ntitle: P\n---\nBody"},
        template_files: {"page.html" => "{{ highlight_js }}{{ content }}"},
      ) { }
    end

    logs.should contain("use_cdn = false")
    logs.should contain("/assets/js/highlight.min.js")
    logs.should contain("/assets/css/highlight/github.min.css")
  end

  it "does not warn when the self-hosted highlight assets are present" do
    logs = capture_build_logs do
      build_site(
        SELF_HOSTED_HIGHLIGHT_CONFIG,
        content_files: {"page.md" => "---\ntitle: P\n---\nBody"},
        template_files: {"page.html" => "{{ content }}"},
        static_files: {
          "assets/js/highlight.min.js"          => "// hljs",
          "assets/css/highlight/github.min.css" => "/* theme */",
        },
      ) { }
    end

    logs.should_not contain("use_cdn = false")
  end

  it "does not warn when use_cdn = true, even with no local assets" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [highlight]
      enabled = true
      use_cdn = true
      theme = "github"
      TOML

    logs = capture_build_logs do
      build_site(
        config,
        content_files: {"page.md" => "---\ntitle: P\n---\nBody"},
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end

    logs.should_not contain("use_cdn = false")
  end
end
