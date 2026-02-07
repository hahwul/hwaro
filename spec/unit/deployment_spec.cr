require "../spec_helper"

describe Hwaro::Models::DeploymentTarget do
  describe "#initialize" do
    it "has default values" do
      target = Hwaro::Models::DeploymentTarget.new
      target.name.should eq("")
      target.url.should eq("")
      target.include.should be_nil
      target.exclude.should be_nil
      target.strip_index_html.should be_false
      target.command.should be_nil
    end
  end

  describe "property setters" do
    it "can set name" do
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "production"
      target.name.should eq("production")
    end

    it "can set url" do
      target = Hwaro::Models::DeploymentTarget.new
      target.url = "s3://my-bucket"
      target.url.should eq("s3://my-bucket")
    end

    it "can set include pattern" do
      target = Hwaro::Models::DeploymentTarget.new
      target.include = "**/*.html"
      target.include.should eq("**/*.html")
    end

    it "can set exclude pattern" do
      target = Hwaro::Models::DeploymentTarget.new
      target.exclude = "*.draft.*"
      target.exclude.should eq("*.draft.*")
    end

    it "can set strip_index_html" do
      target = Hwaro::Models::DeploymentTarget.new
      target.strip_index_html = true
      target.strip_index_html.should be_true
    end

    it "can set command" do
      target = Hwaro::Models::DeploymentTarget.new
      target.command = "rsync -av {source}/ user@host:{url}"
      target.command.should eq("rsync -av {source}/ user@host:{url}")
    end

    it "can configure a complete file:// target" do
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "local"
      target.url = "file:///var/www/html"
      target.include = nil
      target.exclude = "*.draft.*"
      target.strip_index_html = false

      target.name.should eq("local")
      target.url.should eq("file:///var/www/html")
      target.exclude.should eq("*.draft.*")
    end

    it "can configure a target with custom command" do
      target = Hwaro::Models::DeploymentTarget.new
      target.name = "s3-prod"
      target.url = "s3://my-bucket/site"
      target.command = "aws s3 sync {source}/ {url} --delete"

      target.name.should eq("s3-prod")
      target.url.should eq("s3://my-bucket/site")
      target.command.should eq("aws s3 sync {source}/ {url} --delete")
    end
  end
end

describe Hwaro::Models::DeploymentMatcher do
  describe "#initialize" do
    it "has default values" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.pattern.should eq("")
      matcher.cache_control.should be_nil
      matcher.content_type.should be_nil
      matcher.gzip.should be_false
      matcher.force.should be_false
    end
  end

  describe "property setters" do
    it "can set pattern" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.pattern = "**/*.html"
      matcher.pattern.should eq("**/*.html")
    end

    it "can set cache_control" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.cache_control = "max-age=3600, public"
      matcher.cache_control.should eq("max-age=3600, public")
    end

    it "can set content_type" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.content_type = "text/html; charset=utf-8"
      matcher.content_type.should eq("text/html; charset=utf-8")
    end

    it "can set gzip" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.gzip = true
      matcher.gzip.should be_true
    end

    it "can set force" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.force = true
      matcher.force.should be_true
    end

    it "can configure a complete matcher for HTML files" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.pattern = "**/*.html"
      matcher.cache_control = "max-age=0, no-cache"
      matcher.content_type = "text/html; charset=utf-8"
      matcher.gzip = true
      matcher.force = false

      matcher.pattern.should eq("**/*.html")
      matcher.cache_control.should eq("max-age=0, no-cache")
      matcher.content_type.should eq("text/html; charset=utf-8")
      matcher.gzip.should be_true
      matcher.force.should be_false
    end

    it "can configure a matcher for static assets with long cache" do
      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.pattern = "**/*.{css,js,png,jpg,svg}"
      matcher.cache_control = "max-age=31536000, immutable"
      matcher.gzip = true

      matcher.pattern.should eq("**/*.{css,js,png,jpg,svg}")
      matcher.cache_control.should eq("max-age=31536000, immutable")
      matcher.gzip.should be_true
      matcher.content_type.should be_nil
      matcher.force.should be_false
    end
  end
end

describe Hwaro::Models::DeploymentConfig do
  describe "#initialize" do
    it "has default values" do
      config = Hwaro::Models::DeploymentConfig.new
      config.target.should be_nil
      config.confirm.should be_false
      config.dry_run.should be_false
      config.force.should be_false
      config.max_deletes.should eq(256)
      config.workers.should eq(10)
      config.source_dir.should eq("public")
      config.targets.should eq([] of Hwaro::Models::DeploymentTarget)
      config.matchers.should eq([] of Hwaro::Models::DeploymentMatcher)
    end
  end

  describe "property setters" do
    it "can set target" do
      config = Hwaro::Models::DeploymentConfig.new
      config.target = "production"
      config.target.should eq("production")
    end

    it "can set target to nil" do
      config = Hwaro::Models::DeploymentConfig.new
      config.target = nil
      config.target.should be_nil
    end

    it "can set confirm" do
      config = Hwaro::Models::DeploymentConfig.new
      config.confirm = true
      config.confirm.should be_true
    end

    it "can set dry_run" do
      config = Hwaro::Models::DeploymentConfig.new
      config.dry_run = true
      config.dry_run.should be_true
    end

    it "can set force" do
      config = Hwaro::Models::DeploymentConfig.new
      config.force = true
      config.force.should be_true
    end

    it "can set max_deletes" do
      config = Hwaro::Models::DeploymentConfig.new
      config.max_deletes = 500
      config.max_deletes.should eq(500)
    end

    it "can set max_deletes to -1 for unlimited" do
      config = Hwaro::Models::DeploymentConfig.new
      config.max_deletes = -1
      config.max_deletes.should eq(-1)
    end

    it "can set workers" do
      config = Hwaro::Models::DeploymentConfig.new
      config.workers = 4
      config.workers.should eq(4)
    end

    it "can set source_dir" do
      config = Hwaro::Models::DeploymentConfig.new
      config.source_dir = "dist"
      config.source_dir.should eq("dist")
    end

    it "can add targets" do
      config = Hwaro::Models::DeploymentConfig.new

      target = Hwaro::Models::DeploymentTarget.new
      target.name = "staging"
      target.url = "/var/www/staging"

      config.targets << target
      config.targets.size.should eq(1)
      config.targets.first.name.should eq("staging")
    end

    it "can add multiple targets" do
      config = Hwaro::Models::DeploymentConfig.new

      staging = Hwaro::Models::DeploymentTarget.new
      staging.name = "staging"
      staging.url = "/var/www/staging"

      production = Hwaro::Models::DeploymentTarget.new
      production.name = "production"
      production.url = "s3://prod-bucket"

      config.targets << staging
      config.targets << production

      config.targets.size.should eq(2)
      config.targets[0].name.should eq("staging")
      config.targets[1].name.should eq("production")
    end

    it "can add matchers" do
      config = Hwaro::Models::DeploymentConfig.new

      matcher = Hwaro::Models::DeploymentMatcher.new
      matcher.pattern = "**/*.html"
      matcher.cache_control = "max-age=0"

      config.matchers << matcher
      config.matchers.size.should eq(1)
      config.matchers.first.pattern.should eq("**/*.html")
    end
  end

  describe "#target_named" do
    it "returns target by name" do
      config = Hwaro::Models::DeploymentConfig.new

      target1 = Hwaro::Models::DeploymentTarget.new
      target1.name = "staging"
      target1.url = "/var/www/staging"

      target2 = Hwaro::Models::DeploymentTarget.new
      target2.name = "production"
      target2.url = "s3://prod-bucket"

      config.targets << target1
      config.targets << target2

      found = config.target_named("production")
      found.should_not be_nil
      found.not_nil!.name.should eq("production")
      found.not_nil!.url.should eq("s3://prod-bucket")
    end

    it "returns nil for non-existent target name" do
      config = Hwaro::Models::DeploymentConfig.new

      target = Hwaro::Models::DeploymentTarget.new
      target.name = "staging"
      target.url = "/var/www/staging"

      config.targets << target

      found = config.target_named("production")
      found.should be_nil
    end

    it "returns nil when no targets are configured" do
      config = Hwaro::Models::DeploymentConfig.new
      found = config.target_named("anything")
      found.should be_nil
    end

    it "returns the first match when duplicate names exist" do
      config = Hwaro::Models::DeploymentConfig.new

      target1 = Hwaro::Models::DeploymentTarget.new
      target1.name = "dupe"
      target1.url = "first"

      target2 = Hwaro::Models::DeploymentTarget.new
      target2.name = "dupe"
      target2.url = "second"

      config.targets << target1
      config.targets << target2

      found = config.target_named("dupe")
      found.should_not be_nil
      found.not_nil!.url.should eq("first")
    end

    it "performs case-sensitive name matching" do
      config = Hwaro::Models::DeploymentConfig.new

      target = Hwaro::Models::DeploymentTarget.new
      target.name = "Production"
      target.url = "s3://bucket"

      config.targets << target

      config.target_named("Production").should_not be_nil
      config.target_named("production").should be_nil
      config.target_named("PRODUCTION").should be_nil
    end
  end

  describe "full configuration scenario" do
    it "can represent a complete deployment configuration" do
      config = Hwaro::Models::DeploymentConfig.new
      config.target = "production"
      config.confirm = true
      config.dry_run = false
      config.force = false
      config.max_deletes = 100
      config.workers = 8
      config.source_dir = "public"

      # Add staging target with local directory
      staging = Hwaro::Models::DeploymentTarget.new
      staging.name = "staging"
      staging.url = "file:///var/www/staging"
      staging.exclude = "*.draft.*"
      config.targets << staging

      # Add production target with custom command
      production = Hwaro::Models::DeploymentTarget.new
      production.name = "production"
      production.url = "s3://my-site-bucket"
      production.command = "aws s3 sync {source}/ {url} --delete"
      config.targets << production

      # Add matchers for cache control
      html_matcher = Hwaro::Models::DeploymentMatcher.new
      html_matcher.pattern = "**/*.html"
      html_matcher.cache_control = "max-age=0, no-cache"
      html_matcher.gzip = true
      config.matchers << html_matcher

      asset_matcher = Hwaro::Models::DeploymentMatcher.new
      asset_matcher.pattern = "**/*.{css,js}"
      asset_matcher.cache_control = "max-age=31536000, immutable"
      asset_matcher.gzip = true
      config.matchers << asset_matcher

      # Verify the complete configuration
      config.target.should eq("production")
      config.confirm.should be_true
      config.max_deletes.should eq(100)
      config.workers.should eq(8)
      config.targets.size.should eq(2)
      config.matchers.size.should eq(2)

      config.target_named("staging").not_nil!.url.should eq("file:///var/www/staging")
      config.target_named("production").not_nil!.command.should eq("aws s3 sync {source}/ {url} --delete")
    end
  end
end
