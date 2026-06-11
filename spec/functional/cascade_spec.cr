require "./support/build_helper"

# =============================================================================
# Section [cascade] front matter inheritance
#
# A section _index.md may declare a [cascade] table whose values become
# defaults for all descendant pages and sections. Deeper cascades override
# shallower ones; a page's own front matter always wins; the declaring
# section itself is not affected.
# =============================================================================

private def run_cached_build
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(output_dir: "public", parallel: false, cache: true, highlight: false, verbose: false, profile: false)
end

describe "Cascade: basic inheritance" do
  it "applies template, tags, and extra to descendant pages" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => <<-MD,
          +++
          title = "Blog"

          [cascade]
          template = "special"
          tags = ["from-cascade"]

          [cascade.extra]
          banner = "blog-banner.png"
          +++
          MD
        "blog/post.md" => "+++\ntitle = \"Post\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "<p>tpl=page</p>",
        "special.html" => "<p>tpl=special tags={{ page.tags | join(\",\") }} banner={{ page.extra.banner }}</p>",
        "section.html" => "<p>section</p>",
      },
    ) do
      html = File.read("public/blog/post/index.html")
      html.should contain("tpl=special")
      html.should contain("tags=from-cascade")
      html.should contain("banner=blog-banner.png")
    end
  end

  it "lets the page's own front matter win over cascaded values" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => <<-MD,
          +++
          title = "Blog"

          [cascade]
          template = "special"
          tags = ["from-cascade"]

          [cascade.extra]
          banner = "blog-banner.png"
          +++
          MD
        "blog/post.md" => <<-MD,
          +++
          title = "Post"
          template = "page"
          tags = ["own-tag"]

          [extra]
          banner = "custom.png"
          +++
          body
          MD
      },
      template_files: {
        "page.html"    => "<p>tpl=page tags={{ page.tags | join(\",\") }} banner={{ page.extra.banner }}</p>",
        "special.html" => "<p>tpl=special</p>",
        "section.html" => "<p>section</p>",
      },
    ) do
      html = File.read("public/blog/post/index.html")
      html.should contain("tpl=page")
      html.should contain("tags=own-tag")
      html.should contain("banner=custom.png")
    end
  end

  it "merges extra shallowly: page keys win, cascaded keys fill gaps" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => <<-MD,
          +++
          title = "Blog"

          [cascade.extra]
          banner = "cascade.png"
          footer = "cascade-footer"
          +++
          MD
        "blog/post.md" => <<-MD,
          +++
          title = "Post"

          [extra]
          banner = "own.png"
          +++
          body
          MD
      },
      template_files: {
        "page.html"    => "<p>banner={{ page.extra.banner }} footer={{ page.extra.footer }}</p>",
        "section.html" => "<p>section</p>",
      },
    ) do
      html = File.read("public/blog/post/index.html")
      html.should contain("banner=own.png")
      html.should contain("footer=cascade-footer")
    end
  end
end

describe "Cascade: nesting and scope" do
  it "lets deeper cascades override shallower ones" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md"       => "+++\ntitle = \"Blog\"\n\n[cascade.extra]\nbanner = \"blog.png\"\n+++",
        "blog/inner/_index.md" => "+++\ntitle = \"Inner\"\n\n[cascade.extra]\nbanner = \"inner.png\"\n+++",
        "blog/post.md"         => "+++\ntitle = \"Post\"\n+++\nbody",
        "blog/inner/deep.md"   => "+++\ntitle = \"Deep\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "<p>banner={{ page.extra.banner }}</p>",
        "section.html" => "<p>section</p>",
      },
    ) do
      File.read("public/blog/post/index.html").should contain("banner=blog.png")
      File.read("public/blog/inner/deep/index.html").should contain("banner=inner.png")
    end
  end

  it "does not apply a section's cascade to the section itself, but does to subsections" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md"       => "+++\ntitle = \"Blog\"\n\n[cascade.extra]\nbanner = \"blog.png\"\n+++",
        "blog/inner/_index.md" => "+++\ntitle = \"Inner\"\n+++",
      },
      template_files: {
        "page.html"    => "<p>page</p>",
        "section.html" => "<p>banner={{ page.extra.banner | default(\"none\") }}</p>",
      },
    ) do
      File.read("public/blog/index.html").should contain("banner=none")
      File.read("public/blog/inner/index.html").should contain("banner=blog.png")
    end
  end

  it "isolates cascades between language trees" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"
      default_language = "en"

      [languages.ko]
      title = "테스트"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md"    => "+++\ntitle = \"Blog\"\n\n[cascade.extra]\nbanner = \"en.png\"\n+++",
        "blog/_index.ko.md" => "+++\ntitle = \"블로그\"\n\n[cascade.extra]\nbanner = \"ko.png\"\n+++",
        "blog/post.md"      => "+++\ntitle = \"Post\"\n+++\nbody",
        "blog/post.ko.md"   => "+++\ntitle = \"포스트\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "<p>banner={{ page.extra.banner | default(\"none\") }}</p>",
        "section.html" => "<p>section</p>",
      },
    ) do
      File.read("public/blog/post/index.html").should contain("banner=en.png")
      File.read("public/ko/blog/post/index.html").should contain("banner=ko.png")
    end
  end
end

describe "Cascade: filtering and aggregation" do
  it "cascaded draft excludes descendant pages from the build" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "wip/_index.md" => "+++\ntitle = \"WIP\"\n\n[cascade]\ndraft = true\n+++",
        "wip/secret.md" => "+++\ntitle = \"Secret\"\n+++\nnot yet",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<p>section</p>",
      },
    ) do
      File.exists?("public/wip/secret/index.html").should be_false
    end
  end

  it "includes cascaded-draft pages when drafts are enabled" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "wip/_index.md" => "+++\ntitle = \"WIP\"\n\n[cascade]\ndraft = true\n+++",
        "wip/secret.md" => "+++\ntitle = \"Secret\"\n+++\nnot yet",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<p>section</p>",
      },
      drafts: true,
    ) do
      File.exists?("public/wip/secret/index.html").should be_true
    end
  end

  it "aggregates cascaded tags into taxonomy term pages" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [[taxonomies]]
      name = "tags"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n\n[cascade]\ntags = [\"shared\"]\n+++",
        "blog/post.md"   => "+++\ntitle = \"Post\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<p>section</p>",
      },
    ) do
      File.exists?("public/tags/shared/index.html").should be_true
    end
  end

  it "ignores non-cascadable keys instead of applying them" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n\n[cascade]\nslug = \"clobbered\"\n+++",
        "blog/post.md"   => "+++\ntitle = \"Post\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<p>section</p>",
      },
    ) do
      # URL must be derived from the filename, not the cascaded slug
      File.exists?("public/blog/post/index.html").should be_true
      File.exists?("public/blog/clobbered/index.html").should be_false
    end
  end
end

describe "Cascade: cache invalidation" do
  it "rebuilds descendant pages when a parent cascade changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content/blog")
        FileUtils.mkdir_p("templates")
        File.write("content/blog/_index.md", "+++\ntitle = \"Blog\"\n\n[cascade.extra]\nbanner = \"v1.png\"\n+++")
        File.write("content/blog/post.md", "+++\ntitle = \"Post\"\n+++\nbody")
        File.write("templates/page.html", "<p>banner={{ page.extra.banner }}</p>")
        File.write("templates/section.html", "<p>section</p>")

        run_cached_build
        File.read("public/blog/post/index.html").should contain("banner=v1.png")

        # Edit only the parent _index.md cascade; post.md is untouched
        File.write("content/blog/_index.md", "+++\ntitle = \"Blog\"\n\n[cascade.extra]\nbanner = \"v2.png\"\n+++")

        run_cached_build
        File.read("public/blog/post/index.html").should contain("banner=v2.png")
      end
    end
  end
end

describe "Cascade: review regressions" do
  it "keeps a page's own top-level authors over [cascade.taxonomies] authors" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [[taxonomies]]
      name = "authors"
      TOML

    build_site(
      config,
      content_files: {
        "blog/_index.md" => "+++\ntitle = \"Blog\"\n\n[cascade.taxonomies]\nauthors = [\"bob\"]\n+++",
        "blog/mine.md"   => "+++\ntitle = \"Mine\"\nauthors = [\"alice\"]\n+++\nbody",
        "blog/other.md"  => "+++\ntitle = \"Other\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "{{ content }}",
        "section.html" => "<p>section</p>",
      },
    ) do
      # alice's page keeps its own author; only the author-less page gets bob
      File.exists?("public/authors/alice/index.html").should be_true
      File.exists?("public/authors/bob/index.html").should be_true
      bob_page = File.read("public/authors/bob/index.html")
      bob_page.should contain("Other")
      bob_page.should_not contain("Mine")
    end
  end

  it "applies a draft section's cascade to its non-draft descendants (cold build)" do
    build_site(
      BASIC_CONFIG,
      content_files: {
        "hidden/_index.md" => "+++\ntitle = \"Hidden\"\ndraft = true\n\n[cascade.extra]\nbanner = \"from-draft-section.png\"\n+++",
        "hidden/post.md"   => "+++\ntitle = \"Post\"\n+++\nbody",
      },
      template_files: {
        "page.html"    => "<p>banner={{ page.extra.banner | default(\"none\") }}</p>",
        "section.html" => "<p>section</p>",
      },
    ) do
      File.exists?("public/hidden/index.html").should be_false
      File.read("public/hidden/post/index.html").should contain("banner=from-draft-section.png")
    end
  end

  it "retains a draft section's cascade across incremental rebuilds" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content/hidden")
        FileUtils.mkdir_p("templates")
        File.write("content/hidden/_index.md", "+++\ntitle = \"Hidden\"\ndraft = true\n\n[cascade.extra]\nbanner = \"from-draft-section.png\"\n+++")
        File.write("content/hidden/post.md", "+++\ntitle = \"Post\"\n+++\nbody")
        File.write("templates/page.html", "<p>banner={{ page.extra.banner | default(\"none\") }} {{ content }}</p>")
        File.write("templates/section.html", "<p>section</p>")

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        builder.run(output_dir: "public", parallel: false, cache: false, highlight: false, verbose: false, profile: false)
        File.read("public/hidden/post/index.html").should contain("banner=from-draft-section.png")

        # Incremental re-parse must re-apply the draft section's cascade —
        # site.sections no longer holds the filtered-out _index.
        File.write("content/hidden/post.md", "+++\ntitle = \"Post\"\n+++\nUPDATED body")
        builder.run_incremental(["content/hidden/post.md"], options)

        html = File.read("public/hidden/post/index.html")
        html.should contain("UPDATED body")
        html.should contain("banner=from-draft-section.png")
      end
    end
  end

  it "escalates to a full rebuild when an excluded section's _index is edited" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content/hidden")
        FileUtils.mkdir_p("templates")
        File.write("content/hidden/_index.md", "+++\ntitle = \"Hidden\"\ndraft = true\n\n[cascade.extra]\nbanner = \"v1.png\"\n+++")
        File.write("content/hidden/post.md", "+++\ntitle = \"Post\"\n+++\nbody")
        File.write("templates/page.html", "<p>banner={{ page.extra.banner | default(\"none\") }}</p>")
        File.write("templates/section.html", "<p>section</p>")

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        builder.run(output_dir: "public", parallel: false, cache: false, highlight: false, verbose: false, profile: false)

        # The draft _index isn't in the site model; editing its cascade must
        # trigger a full rebuild so descendants pick up the new value.
        File.write("content/hidden/_index.md", "+++\ntitle = \"Hidden\"\ndraft = true\n\n[cascade.extra]\nbanner = \"v2.png\"\n+++")
        builder.run_incremental(["content/hidden/_index.md"], options)

        File.read("public/hidden/post/index.html").should contain("banner=v2.png")
      end
    end
  end
end
