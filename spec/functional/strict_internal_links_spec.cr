require "./support/build_helper"

# =============================================================================
# Strict broken internal links functional tests
#
# `[links] broken_internal = "error"` must fail the build with ONE
# aggregated classified error listing every unresolved @/ link, while the
# default "warn" mode keeps today's log-and-continue behavior.
# =============================================================================

private STRICT_LINKS_CONFIG = <<-TOML
  title = "Test Site"
  base_url = "http://localhost"

  [links]
  broken_internal = "error"
  TOML

describe "Strict internal links: error mode" do
  it "fails the build with one aggregated error listing every offender" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        STRICT_LINKS_CONFIG,
        content_files: {
          "page.md"  => "---\ntitle: Page\n---\nSee [missing](@/nonexistent.md)",
          "other.md" => "---\ntitle: Other\n---\nAn [empty](@/) link",
        },
        template_files: {"page.html" => "{{ content }}"},
        parallel: true,
      ) { }
    end

    ex.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
    message = ex.message.not_nil!
    message.should contain("2 broken internal links")
    message.should contain("page.md → @/nonexistent.md (page not found)")
    message.should contain("other.md → @/ (empty link)")
    ex.hint.not_nil!.should contain(%([links] broken_internal = "warn"))
  end

  it "lists a repeated broken link once" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        STRICT_LINKS_CONFIG,
        content_files: {
          "page.md" => "---\ntitle: Page\n---\n[one](@/nonexistent.md) and [two](@/nonexistent.md)",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end

    message = ex.message.not_nil!
    message.should contain("1 broken internal link")
    message.scan("page.md → @/nonexistent.md (page not found)").size.should eq(1)
  end

  it "catches a broken link that only ships via a render:false page's summary" do
    # The headless page never enters the render fan-out, but its
    # <!-- more --> summary is embedded by listings — the strict pass must
    # see the summary render too.
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        STRICT_LINKS_CONFIG,
        content_files: {
          "posts/data.md" => "---\ntitle: Data\nrender: false\n---\nIntro [x](@/gone.md)\n<!-- more -->\nrest",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end
    ex.message.not_nil!.should contain("posts/data.md → @/gone.md (page not found)")
  end

  it "reports a broken summary link once for pages that also render" do
    ex = expect_raises(Hwaro::HwaroError) do
      build_site(
        STRICT_LINKS_CONFIG,
        content_files: {
          "page.md" => "---\ntitle: Page\n---\nIntro [x](@/gone.md)\n<!-- more -->\nbody",
        },
        template_files: {"page.html" => "{{ content }}"},
      ) { }
    end

    message = ex.message.not_nil!
    message.should contain("1 broken internal link")
    message.scan("page.md → @/gone.md (page not found)").size.should eq(1)
  end

  # The fast-start deferred fan-out is the one render pass that runs outside
  # the Render phase — it must surface strict-mode offenders too, or a
  # broken link in a non-priority page silently ships during `serve
  # --fast-start`. The server's deferred fiber rescues the raise and routes
  # it into the error overlay.
  it "raises from render_deferred when a deferred page has a broken link" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", STRICT_LINKS_CONFIG)
        FileUtils.mkdir_p("content")
        File.write("content/_index.md", "---\ntitle: Home\n---\nhome")
        File.write("content/recent.md", "---\ntitle: Recent\ndate: 2026-06-01\n---\nclean body")
        File.write("content/old-broken.md", "---\ntitle: Old\ndate: 2020-01-01\n---\nSee [missing](@/nope.md)")
        File.write("content/old-clean.md", "---\ntitle: Old Two\ndate: 2020-01-02\n---\nfine")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/index.html", "{{ content }}")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(
          output_dir: "public",
          parallel: false,
          fast_start: true,
          fast_start_count: 1,
        )

        # The priority pass (home + most recent post) is clean, so the
        # initial build succeeds and the broken page lands in the
        # deferred bucket.
        builder.run(options).should be_true
        builder.has_deferred_pages?.should be_true

        ex = expect_raises(Hwaro::HwaroError) do
          builder.render_deferred(options)
        end
        ex.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
        ex.message.not_nil!.should contain("old-broken.md → @/nope.md (page not found)")
      end
    end
  end

  it "does not flag resolvable links" do
    build_site(
      STRICT_LINKS_CONFIG,
      content_files: {
        "about.md" => "---\ntitle: About\n---\nAbout page",
        "page.md"  => "---\ntitle: Page\n---\nSee [About](@/about.md)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      html.should contain("href=\"/about/\"")
    end
  end
end

describe "Strict internal links: warn mode (default)" do
  it "builds successfully and leaves the unresolved markup unchanged" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "page.md" => "---\ntitle: Page\n---\nSee [missing](@/nonexistent.md)",
      },
      template_files: {"page.html" => "{{ content }}"},
    ) do
      html = File.read("public/page/index.html")
      html.should contain("@/nonexistent.md")
    end
  end
end
