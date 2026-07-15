require "../spec_helper"
require "../../src/services/platform_config"

describe Hwaro::Services::PlatformConfig do
  describe "#output_filename" do
    it "returns netlify.toml for netlify" do
      config = Hwaro::Models::Config.new
      generator = Hwaro::Services::PlatformConfig.new(config)
      generator.output_filename("netlify").should eq("netlify.toml")
    end

    it "returns vercel.json for vercel" do
      config = Hwaro::Models::Config.new
      generator = Hwaro::Services::PlatformConfig.new(config)
      generator.output_filename("vercel").should eq("vercel.json")
    end

    it "returns wrangler.toml for cloudflare" do
      config = Hwaro::Models::Config.new
      generator = Hwaro::Services::PlatformConfig.new(config)
      generator.output_filename("cloudflare").should eq("wrangler.toml")
    end

    it "returns .forgejo workflow path for codeberg-pages" do
      config = Hwaro::Models::Config.new
      generator = Hwaro::Services::PlatformConfig.new(config)
      generator.output_filename("codeberg-pages").should eq(".forgejo/workflows/deploy.yml")
    end
  end

  describe "#generate" do
    describe "netlify" do
      it "generates valid netlify.toml with build settings" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("netlify")

        result.should contain("[build]")
        result.should contain("command = \"hwaro build\"")
        result.should contain("publish = \"public\"")
        result.should contain("[build.environment]")
      end

      it "includes cache headers" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("netlify")

        result.should contain("[[headers]]")
        result.should contain("Cache-Control")
      end

      # Regression for gh#528 (D): the example HWARO_VERSION pin had
      # hardcoded "0.5.0" and went stale across releases. Use the
      # current `Hwaro::VERSION` so users copy-pasting the comment
      # never see an out-of-date number.
      it "pins the example HWARO_VERSION to the current build" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("netlify")

        result.should contain("# HWARO_VERSION = \"#{Hwaro::VERSION}\"")
        result.should_not contain("# HWARO_VERSION = \"0.5.0\"")
      end
    end

    describe "vercel" do
      it "generates valid JSON with build settings" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("vercel")

        parsed = JSON.parse(result)
        parsed["buildCommand"].as_s.should eq("hwaro build")
        parsed["outputDirectory"].as_s.should eq("public")
      end

      it "includes cache headers" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("vercel")

        parsed = JSON.parse(result)
        parsed["headers"].as_a.should_not be_empty
      end
    end

    describe "cloudflare" do
      it "generates valid wrangler.toml with site bucket" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("cloudflare")

        result.should contain("[site]")
        result.should contain("bucket = \"./public\"")
        result.should contain("compatibility_date")
      end

      it "derives project name from site title" do
        config = Hwaro::Models::Config.new
        config.title = "My Cool Blog"
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("cloudflare")

        result.should contain("name = \"my-cool-blog\"")
      end

      # A symbol-only or empty title sanitizes to an empty string; without the
      # fallback wrangler emits `name = ""` which Cloudflare rejects.
      it "falls back to 'my-site' when the title sanitizes to empty" do
        config = Hwaro::Models::Config.new
        config.title = "!!!"
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("cloudflare")

        result.should contain("name = \"my-site\"")
        result.should_not contain("name = \"\"")
      end

      it "collapses symbol runs and strips leading/trailing dashes from the project name" do
        config = Hwaro::Models::Config.new
        config.title = "--Hi  There!!--"
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("cloudflare")

        result.should contain("name = \"hi-there\"")
      end

      # _redirects is space-delimited; an alias with whitespace or a quote would
      # split into the wrong number of fields and corrupt the file, so such
      # entries are skipped while well-formed ones are kept.
      it "skips redirect aliases containing whitespace or quotes" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/p.md", "---\ntitle: P\naliases:\n  - /old url/\n  - \"/qu\\\"ote/\"\n  - /clean/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("cloudflare")

            # Clean alias is emitted as a `# from to 301` comment line.
            result.should contain("# /clean/ /posts/p/ 301")
            result.should_not contain("/old url/")
            result.should_not contain("/qu\"ote/")
          end
        end
      end
    end

    describe "aliases" do
      it "includes redirects from YAML frontmatter aliases" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/new-post.md", "---\ntitle: New Post\naliases:\n  - /old-url/\n  - /another-old-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("[[redirects]]")
            result.should contain("from = \"/old-url/\"")
            result.should contain("from = \"/another-old-url/\"")
            result.should contain("to = \"/posts/new-post/\"")
            result.should contain("status = 301")
            result.should contain("force = true")
          end
        end
      end

      it "skips draft aliases" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/draft-post.md", "---\ntitle: Draft Post\ndraft: true\naliases:\n  - /old-draft-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should_not contain("/old-draft-url/")
          end
        end
      end

      it "calculates multilingual aliases correctly" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/hello.ko.md", "---\ntitle: Hello KO\naliases:\n  - /old-ko-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            config.languages["ko"] = Hwaro::Models::LanguageConfig.new("ko")
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("from = \"/old-ko-url/\"")
            result.should contain("to = \"/ko/posts/hello/\"")
          end
        end
      end

      it "includes redirects in vercel JSON format" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/new-post.md", "---\ntitle: New Post\naliases:\n  - /old-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("vercel")

            parsed = JSON.parse(result)
            parsed["redirects"].as_a.size.should eq(1)
            parsed["redirects"][0]["source"].as_s.should eq("/old-url/")
            parsed["redirects"][0]["destination"].as_s.should eq("/posts/new-post/")
            parsed["redirects"][0]["statusCode"].as_i.should eq(301)
          end
        end
      end

      it "includes redirects from TOML frontmatter" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/new-post.md", "+++\ntitle = \"New Post\"\naliases = [\"/old-url/\", \"/another/\"]\n+++\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("from = \"/old-url/\"")
            result.should contain("from = \"/another/\"")
          end
        end
      end

      it "uses slug for redirect target URL when specified" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/old-title.md", "---\ntitle: Better Title\nslug: better-title\naliases:\n  - /old-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("to = \"/posts/better-title/\"")
            result.should_not contain("to = \"/posts/old-title/\"")
          end
        end
      end

      it "uses custom_path for redirect target URL when specified" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/my-post.md", "---\ntitle: My Post\npath: custom/location\naliases:\n  - /old-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("to = \"/custom/location/\"")
          end
        end
      end

      it "applies permalink mapping for redirect target URL" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            File.write("content/posts/my-post.md", "---\ntitle: My Post\naliases:\n  - /old-url/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            config.permalinks["posts"] = "blog"
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("to = \"/blog/my-post/\"")
            result.should_not contain("to = \"/posts/my-post/\"")
          end
        end
      end

      # Regression: on a subpath deploy (base_url with a path component) the
      # build writes redirect HTML pointing at `/myrepo/...`, so the platform
      # config's alias redirects and asset cache rule must carry base_path too,
      # otherwise they diverge from the build and point at the domain root.
      it "carries base_path into redirect from/to and the cache header on subpath deploys" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content")
            File.write("content/moved.md", "---\ntitle: Moved\naliases:\n  - /old/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            config.base_url = "https://example.com/myrepo/"
            generator = Hwaro::Services::PlatformConfig.new(config)

            netlify = generator.generate("netlify")
            netlify.should contain("from = \"/myrepo/old/\"")
            netlify.should contain("to = \"/myrepo/moved/\"")
            netlify.should contain("for = \"/myrepo/assets/*\"")

            vercel = JSON.parse(generator.generate("vercel"))
            vercel["redirects"][0]["source"].as_s.should eq("/myrepo/old/")
            vercel["redirects"][0]["destination"].as_s.should eq("/myrepo/moved/")
            vercel["headers"][0]["source"].as_s.should eq("/myrepo/assets/(.*)")
          end
        end
      end

      # An alias is arbitrary user frontmatter; a quote or backslash must be
      # TOML-escaped or the emitted netlify.toml is unparseable, breaking the
      # user's deploy. Exercise both gsub branches (quote and backslash).
      it "escapes TOML-special characters in netlify redirect from/to so the block stays parseable" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/posts")
            # YAML double-quoted scalars inject a literal quote and backslash
            # into the alias values.
            File.write("content/posts/p.md", "---\ntitle: P\naliases:\n  - \"/we\\\"ird/\"\n  - \"/back\\\\slash/\"\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            # The quote is escaped as \" and the backslash as \\.
            result.should contain("from = \"/we\\\"ird/\"")
            result.should contain("from = \"/back\\\\slash/\"")

            # The emitted netlify.toml must parse as valid TOML, and the
            # escaped values must round-trip back to the original aliases.
            parsed = TOML.parse(result)
            froms = parsed["redirects"].as_a.map(&.["from"].as_s)
            froms.should contain("/we\"ird/")
            froms.should contain("/back\\slash/")
          end
        end
      end

      it "maps a nested alias to root for an empty-target permalink without doubling slashes" do
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            FileUtils.mkdir_p("content/pages/contact")
            File.write("content/pages/contact/form.md", "---\ntitle: Contact\naliases:\n  - /old-contact/\n---\nContent here\n")

            config = Hwaro::Models::Config.new
            config.permalinks["pages"] = ""
            generator = Hwaro::Services::PlatformConfig.new(config)
            result = generator.generate("netlify")

            result.should contain("to = \"/contact/form/\"")
            result.should_not contain("to = \"//contact/form/\"")
          end
        end
      end
    end

    describe "gitlab-ci" do
      it "generates a valid GitLab CI configuration with entrypoint override and correct default branch rule" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("gitlab-ci")

        result.should contain("image:")
        result.should contain("name: ghcr.io/hahwul/hwaro:latest")
        result.should contain("entrypoint: [\"\"]")
        result.should contain("rules:")
        result.should contain("- if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH")
      end
    end

    describe "codeberg-pages" do
      it "generates a Forgejo Actions workflow that builds and pushes to a pages branch" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("codeberg-pages")

        result.should contain("name: Hwaro Deploy")
        result.should contain("runs-on: docker")
        result.should contain("ghcr.io/hahwul/hwaro:latest")
        result.should contain("hwaro build")
        result.should contain("CODEBERG_TOKEN")
        result.should contain("codeberg.org/${{ github.repository }}.git")
      end

      it "exposes the pages branch as a configurable env var defaulting to 'pages'" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("codeberg-pages")

        result.should contain("PAGES_BRANCH: pages")
        result.should contain("git init -b \"$PAGES_BRANCH\"")
      end

      it "uses Codeberg's noreply email domain" do
        config = Hwaro::Models::Config.new
        generator = Hwaro::Services::PlatformConfig.new(config)
        result = generator.generate("codeberg-pages")

        result.should contain("@noreply.codeberg.org")
        result.should_not contain("users.noreply.codeberg.org")
      end
    end

    it "raises for unsupported platform" do
      config = Hwaro::Models::Config.new
      generator = Hwaro::Services::PlatformConfig.new(config)
      expect_raises(Exception, /Unsupported platform/) do
        generator.generate("firebase")
      end
    end
  end
end
