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
        result.should contain("git init -b pages")
        result.should contain("CODEBERG_TOKEN")
        result.should contain("codeberg.org/${{ github.repository }}.git")
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
