require "../spec_helper"

describe Hwaro::Services::UnusedAssets do
  describe "#run" do
    it "returns empty result when no directories exist" do
      service = Hwaro::Services::UnusedAssets.new(
        content_dir: "/nonexistent/content",
        static_dir: "/nonexistent/static",
      )
      result = service.run
      result.total_assets.should eq(0)
      result.unused_count.should eq(0)
    end

    it "detects unused static assets" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        # Create assets
        File.write(File.join(static_dir, "used.png"), "png data")
        File.write(File.join(static_dir, "unused.png"), "png data")

        # Content references only used.png
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\n![Image](used.png)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(2)
        result.referenced_count.should eq(1)
        result.unused_count.should eq(1)
        result.unused_files.should contain(File.join(static_dir, "unused.png"))
      end
    end

    it "does not flag a referenced asset whose name contains a space" do
      # Regression: the reference regex only matches [\w\-.] filenames, so an
      # asset like `team photo.png` referenced in content was reported unused
      # and would be DELETED. The literal-substring safety net must catch it.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "team photo.png"), "png data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\n![Team](/team photo.png)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.unused_count.should eq(0)
        result.unused_files.should_not contain(File.join(static_dir, "team photo.png"))
      end
    end

    it "still flags an unused asset whose name is a suffix of a referenced one" do
      # The space/paren safety net must be boundary-aware: an unused
      # `header.png` must NOT be hidden just because a referenced
      # `page-header.png` literally contains the substring `header.png`.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "header.png"), "png data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\n![Banner](/page-header.png)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.unused_count.should eq(1)
        result.unused_files.should contain(File.join(static_dir, "header.png"))
      end
    end

    it "counts template references" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        templates_dir = File.join(dir, "templates")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(templates_dir)

        File.write(File.join(static_dir, "logo.svg"), "svg data")
        File.write(File.join(templates_dir, "base.html"), "<img src=\"logo.svg\">")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: templates_dir)
        result = service.run

        result.referenced_count.should eq(1)
        result.unused_count.should eq(0)
      end
    end

    it "detects co-located content assets" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        post_dir = File.join(content_dir, "my-post")
        FileUtils.mkdir_p(post_dir)

        File.write(File.join(post_dir, "index.md"), "---\ntitle: Post\n---\n\n![Image](photo.jpg)\n")
        File.write(File.join(post_dir, "photo.jpg"), "jpg data")
        File.write(File.join(post_dir, "unused.jpg"), "jpg data")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: File.join(dir, "static"), templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(2)
        result.unused_count.should eq(1)
        result.unused_files.any?(&.ends_with?("unused.jpg")).should be_true
      end
    end

    it "all assets referenced returns zero unused" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "image.png"), "png data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\n![Pic](image.png)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.unused_count.should eq(0)
        result.unused_files.should be_empty
      end
    end

    it "serializes to JSON" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "orphan.css"), "body {}")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run
        json = JSON.parse(result.to_json)

        json["total_assets"].as_i.should eq(1)
        json["unused_count"].as_i.should eq(1)
      end
    end

    it "ignores non-asset file extensions" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "data.json"), "{}")
        File.write(File.join(static_dir, "notes.txt"), "notes")
        File.write(File.join(static_dir, "real.png"), "png")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(1)
      end
    end

    it "handles nested static directories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        nested = File.join(static_dir, "images", "photos")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(nested)

        File.write(File.join(nested, "deep.jpg"), "jpg data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\n\n![](deep.jpg)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(1)
        result.referenced_count.should eq(1)
      end
    end

    it "handles filenames with multiple dots" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "app.min.js"), "js code")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\n\n<script src=\"app.min.js\"></script>\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.referenced_count.should eq(1)
        result.unused_count.should eq(0)
      end
    end

    it "handles recursive template directories" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        templates_dir = File.join(dir, "templates")
        partials = File.join(templates_dir, "partials")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(partials)

        File.write(File.join(static_dir, "icon.svg"), "svg")
        File.write(File.join(partials, "header.html"), "<img src=\"icon.svg\">")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: templates_dir)
        result = service.run

        result.referenced_count.should eq(1)
      end
    end

    it "delete_unused removes files" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(static_dir)

        path1 = File.join(static_dir, "old.png")
        path2 = File.join(static_dir, "stale.css")
        File.write(path1, "data")
        File.write(path2, "data")

        service = Hwaro::Services::UnusedAssets.new(content_dir: File.join(dir, "content"), static_dir: static_dir)
        service.delete_unused([path1, path2])

        File.exists?(path1).should be_false
        File.exists?(path2).should be_false
      end
    end

    it "delete_unused skips already-deleted files" do
      Dir.mktmpdir do |dir|
        service = Hwaro::Services::UnusedAssets.new(content_dir: File.join(dir, "content"), static_dir: File.join(dir, "static"))
        # Should not raise
        service.delete_unused([File.join(dir, "nonexistent.png")])
      end
    end

    it "handles uppercase file extensions" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "PHOTO.JPG"), "jpg data")
        File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\n\n![](PHOTO.JPG)\n")

        service = Hwaro::Services::UnusedAssets.new(content_dir: content_dir, static_dir: static_dir, templates_dir: File.join(dir, "templates"))
        result = service.run

        result.total_assets.should eq(1)
        result.referenced_count.should eq(1)
      end
    end

    # Regression for https://github.com/hahwul/hwaro/issues/488
    # Files declared in `[[assets.bundles]] files = [...]` are consumed
    # by the asset pipeline at build time, not referenced from
    # content/templates — so the previous scan flagged them as "Unused"
    # even though the build actively reads them.
    it "treats files declared in [[assets.bundles]] as referenced" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p(File.join("static", "css"))
          FileUtils.mkdir_p("templates")

          File.write(File.join("static", "css", "reset.css"), "*{margin:0}")
          File.write(File.join("static", "css", "style.css"), "body{color:#333}")

          File.write("config.toml", <<-TOML)
            title = "T"
            base_url = "http://x"

            [assets]
            enabled = true

            [[assets.bundles]]
            name = "main.css"
            files = ["css/reset.css", "css/style.css"]
            TOML

          service = Hwaro::Services::UnusedAssets.new(
            content_dir: "content",
            static_dir: "static",
            templates_dir: "templates",
          )
          result = service.run
          result.total_assets.should eq(2)
          result.unused_files.should be_empty
        end
      end
    end

    # Regression for https://github.com/hahwul/hwaro/issues/488
    # Files inside `[auto_includes] dirs = [...]` are also consumed by
    # the build (the auto-include tags glob those directories at render
    # time), so they shouldn't be flagged either.
    it "treats files under [auto_includes] dirs as referenced" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p(File.join("static", "assets", "css"))
          FileUtils.mkdir_p("templates")

          File.write(File.join("static", "assets", "css", "01-reset.css"), "*{}")
          File.write(File.join("static", "assets", "css", "02-typography.css"), "p{}")

          File.write("config.toml", <<-TOML)
            title = "T"
            base_url = "http://x"

            [auto_includes]
            enabled = true
            dirs = ["assets/css"]
            TOML

          service = Hwaro::Services::UnusedAssets.new(
            content_dir: "content",
            static_dir: "static",
            templates_dir: "templates",
          )
          result = service.run
          result.total_assets.should eq(2)
          result.unused_files.should be_empty
        end
      end
    end

    it "percent-encoded references are not flagged as unused (regression)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("static")
          FileUtils.mkdir_p("templates")

          File.write(File.join("static", "team photo.png"), "png data")
          File.write(File.join("content", "post.md"), "---\ntitle: Post\n---\n\n![Team](/team%20photo.png)\n")

          service = Hwaro::Services::UnusedAssets.new(
            content_dir: "content",
            static_dir: "static",
            templates_dir: "templates"
          )
          result = service.run
          result.unused_count.should eq(0)
        end
      end
    end

    it "config.toml raw references are not flagged as unused (regression)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("static")
          FileUtils.mkdir_p("templates")

          File.write(File.join("static", "og-main.png"), "png data")
          File.write("config.toml", <<-TOML)
            title = "T"
            [og]
            default_image = "static/og-main.png"
            TOML

          service = Hwaro::Services::UnusedAssets.new(
            content_dir: "content",
            static_dir: "static",
            templates_dir: "templates"
          )
          result = service.run
          result.unused_count.should eq(0)
        end
      end
    end

    it "CWD independence resolves config.toml and templates relative to content parent (regression)" do
      Dir.mktmpdir do |project_dir|
        content_dir = File.join(project_dir, "content")
        static_dir = File.join(project_dir, "static")
        templates_dir = File.join(project_dir, "templates")

        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)
        FileUtils.mkdir_p(templates_dir)

        File.write(File.join(project_dir, "config.toml"), <<-TOML)
          title = "Project Title"
          [og]
          default_image = "static/og-image.png"
          TOML

        File.write(File.join(static_dir, "og-image.png"), "png data")

        service = Hwaro::Services::UnusedAssets.new(
          content_dir: content_dir,
          static_dir: static_dir
        )
        result = service.run
        result.unused_count.should eq(0)
      end
    end

    # Regression: `html`/`htm` were missing from STATIC_SCAN_EXTENSIONS, so a
    # hand-written page under static/ — which the build copies into the output
    # verbatim, `<img src>` and all — was never read. Every image it referenced
    # was reported unused and `--delete` removed it (real data loss).
    it "treats an asset referenced only from a static HTML page as referenced" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          FileUtils.mkdir_p(File.join("static", "img"))
          FileUtils.mkdir_p(File.join("static", "legacy"))

          File.write(File.join("static", "img", "legacy.png"), "png data")
          File.write(
            File.join("static", "legacy", "index.html"),
            "<html><body><img src=\"/img/legacy.png\"></body></html>\n"
          )

          service = Hwaro::Services::UnusedAssets.new(
            content_dir: "content",
            static_dir: "static",
            templates_dir: "templates",
          )
          result = service.run

          result.total_assets.should eq(1)
          result.referenced_count.should eq(1)
          result.unused_count.should eq(0)
        end
      end
    end

    # Regression: `data/` and `i18n/` are build inputs — templates render
    # `site.data.*` and translation strings — but neither directory was
    # globbed, so an asset whose only reference lived there was reported
    # unused and deleted.
    it "treats assets referenced only from data/ or i18n/ as referenced" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          FileUtils.mkdir_p("static")
          FileUtils.mkdir_p("data")
          FileUtils.mkdir_p("i18n")

          File.write(File.join("static", "sponsor.png"), "png data")
          File.write(File.join("static", "flag-en.svg"), "<svg/>")
          File.write(File.join("data", "sponsors.yml"), "- name: Acme\n  logo: /sponsor.png\n")
          File.write(File.join("i18n", "en.toml"), "flag = \"/flag-en.svg\"\n")

          service = Hwaro::Services::UnusedAssets.new(
            content_dir: "content",
            static_dir: "static",
            templates_dir: "templates",
          )
          result = service.run

          result.total_assets.should eq(2)
          result.unused_count.should eq(0)
        end
      end
    end

    # Regression: the asset walk called `File.directory?` on every globbed
    # path, and that RAISES `File::Error` (ELOOP) on a symlink cycle — nothing
    # caught it, so `hwaro tool unused-assets` died with a raw "Unable to get
    # file info" on a tree `hwaro build` already walks fine.
    it "survives symlink cycles and dangling links while walking assets" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        static_dir = File.join(dir, "static")
        FileUtils.mkdir_p(content_dir)
        FileUtils.mkdir_p(static_dir)

        File.write(File.join(static_dir, "orphan.png"), "png data")
        File.symlink("loop.png", File.join(static_dir, "loop.png"))
        File.symlink("gone.png", File.join(static_dir, "dangling.png"))
        File.write(File.join(content_dir, "post.md"), "---\ntitle: Post\n---\n\nBody\n")
        File.symlink("loop.md", File.join(content_dir, "loop.md"))

        result = nil
        output = with_captured_log do
          result = Hwaro::Services::UnusedAssets.new(
            content_dir: content_dir,
            static_dir: static_dir,
            templates_dir: File.join(dir, "templates"),
          ).run
        end

        r = result.not_nil!
        # Only the real file is an asset; the links are skipped, not counted
        # and — critically — never handed to `--delete`.
        r.total_assets.should eq(1)
        r.unused_files.should eq([File.join(static_dir, "orphan.png")])
        output.should contain("loop.png")
      end
    end

    # The same `File.directory?` call sat inside `add_config_references`, whose
    # blanket rescue turned the ELOOP into "no config references at all" — so a
    # single bad link in an auto-include directory made every bundled and
    # auto-included file look unused, and `--delete` removed files the build
    # reads on the next run.
    it "keeps config-declared references when an auto-include dir holds a cycle" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p(File.join("static", "assets", "css"))
          FileUtils.mkdir_p("templates")

          File.write(File.join("static", "assets", "css", "01-reset.css"), "*{}")
          File.write(File.join("static", "assets", "css", "02-typography.css"), "p{}")
          File.symlink("loop.css", File.join("static", "assets", "css", "loop.css"))

          File.write("config.toml", <<-TOML)
            title = "T"
            base_url = "http://x"

            [auto_includes]
            enabled = true
            dirs = ["assets/css"]
            TOML

          result = nil
          with_captured_log do
            result = Hwaro::Services::UnusedAssets.new(
              content_dir: "content",
              static_dir: "static",
              templates_dir: "templates",
            ).run
          end

          r = result.not_nil!
          r.total_assets.should eq(2)
          r.unused_files.should be_empty
        end
      end
    end

    # Regression: project-root resolution mixed two trees. With a config.toml
    # in the CWD, @project_root was pinned to "." even when --content-dir
    # pointed at a DIFFERENT project — so the default static/ (never
    # re-rooted at all) plus data/, i18n/ and config.toml were read from the
    # CWD project while content came from the other one, and
    # `--delete --force` removed in-use files.
    it "scans the static/, data/ and config.toml of the project the content dir belongs to" do
      Dir.mktmpdir do |other|
        Dir.mktmpdir do |cwd|
          Dir.cd(cwd) do
            # The CWD is itself a hwaro project with its own static tree...
            FileUtils.mkdir_p("static")
            File.write("config.toml", "title = \"CWD project\"\n")
            File.write(File.join("static", "decoy.png"), "png")

            # ...but --content-dir points into another project that carries
            # its own config.toml, static/ and data/.
            FileUtils.mkdir_p(File.join(other, "content"))
            FileUtils.mkdir_p(File.join(other, "static"))
            FileUtils.mkdir_p(File.join(other, "data"))
            File.write(File.join(other, "config.toml"), <<-TOML)
              title = "Other"
              [og]
              default_image = "static/og.png"
              TOML
            File.write(File.join(other, "content", "post.md"), "---\ntitle: P\n---\nBody\n")
            File.write(File.join(other, "static", "og.png"), "png")
            File.write(File.join(other, "static", "sponsor.png"), "png")
            File.write(File.join(other, "data", "site.yml"), "logo: /sponsor.png\n")
            File.write(File.join(other, "static", "orphan.png"), "png")

            result = Hwaro::Services::UnusedAssets.new(
              content_dir: File.join(other, "content"),
            ).run

            # THAT project's static tree is the one scanned (3 assets, not
            # the CWD's decoy.png), its config.toml and data/ count as
            # reference sources, and only its genuine orphan is reported.
            result.total_assets.should eq(3)
            result.unused_files.should eq([File.join(other, "static", "orphan.png")])
          end
        end
      end
    end

    it "keeps resolving everything relative to an in-project CWD (defaults unchanged)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("static")
          FileUtils.mkdir_p("templates")
          File.write("config.toml", "title = \"T\"\n")
          File.write(File.join("content", "post.md"), "---\ntitle: P\n---\n![x](/used.png)\n")
          File.write(File.join("static", "used.png"), "png")
          File.write(File.join("static", "orphan.png"), "png")

          result = Hwaro::Services::UnusedAssets.new.run

          # Paths keep their historical relative form ("static/…").
          result.total_assets.should eq(2)
          result.unused_files.should eq([File.join("static", "orphan.png")])
        end
      end
    end

    # Regression: the safety-net `Regex.new` built from an asset basename
    # raised ArgumentError for a non-UTF-8 filename (possible on Linux
    # filesystems), aborting the whole command.
    describe "non-UTF-8 asset basenames" do
      it "boundary_referenced? refuses an invalid basename instead of raising" do
        bad = String.new(Bytes[0xFF]) + ".png"
        Hwaro::Services::UnusedAssets.boundary_referenced?("some corpus", bad).should be_false
      end

      it "boundary_referenced? keeps the space/paren safety net intact" do
        Hwaro::Services::UnusedAssets.boundary_referenced?("![t](/team photo.png)", "team photo.png").should be_true
        Hwaro::Services::UnusedAssets.boundary_referenced?("![b](/page-header.png)", "header.png").should be_false
      end

      it "skips (with a warning) an asset whose file name is not valid UTF-8" do
        Dir.mktmpdir do |dir|
          content_dir = File.join(dir, "content")
          static_dir = File.join(dir, "static")
          FileUtils.mkdir_p(content_dir)
          FileUtils.mkdir_p(static_dir)
          File.write(File.join(content_dir, "post.md"), "---\ntitle: P\n---\nBody\n")
          File.write(File.join(static_dir, "orphan.png"), "png")

          bad_name = String.new(Bytes[0xC3]) + ".png" # truncated UTF-8 sequence
          created = begin
            File.write(File.join(static_dir, bad_name), "png")
            true
          rescue File::Error
            # APFS refuses to create non-UTF-8 names at all; the in-loop
            # guard is unreachable on this filesystem and is covered by the
            # boundary_referenced? specs above.
            false
          end

          result = nil
          output = with_captured_log do
            result = Hwaro::Services::UnusedAssets.new(
              content_dir: content_dir,
              static_dir: static_dir,
              templates_dir: File.join(dir, "templates"),
            ).run
          end

          r = result.not_nil!
          # The bad name is never flagged (and so never handed to --delete);
          # the genuine orphan still is.
          r.unused_files.should eq([File.join(static_dir, "orphan.png")])
          output.should contain("not valid UTF-8") if created
        end
      end
    end
  end
end
