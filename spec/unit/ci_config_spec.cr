require "../spec_helper"
require "../../src/services/ci_config"

describe Hwaro::Services::CIConfig do
  describe "#output_path" do
    it "returns .github/workflows/deploy.yml for github-actions" do
      generator = Hwaro::Services::CIConfig.new
      generator.output_path("github-actions").should eq(".github/workflows/deploy.yml")
    end
  end

  describe "#generate" do
    describe "github-actions" do
      it "generates a valid YAML workflow" do
        generator = Hwaro::Services::CIConfig.new
        result = generator.generate("github-actions")

        result.should contain("name: Hwaro CI/CD")
        result.should contain("on:")
        result.should contain("workflow_dispatch:")
      end

      it "triggers on push to main and pull requests" do
        generator = Hwaro::Services::CIConfig.new
        result = generator.generate("github-actions")

        result.should contain("push:")
        result.should contain("branches: [main]")
        result.should contain("pull_request:")
      end

      it "includes build job for pull requests" do
        generator = Hwaro::Services::CIConfig.new
        result = generator.generate("github-actions")

        result.should contain("build:")
        result.should contain("runs-on: ubuntu-latest")
        result.should contain("uses: actions/checkout@v6")
        result.should contain("uses: hahwul/hwaro@main")
        result.should contain("build_only: true")
        result.should contain("github.event_name == 'pull_request'")
      end

      it "includes deploy job for push to main" do
        generator = Hwaro::Services::CIConfig.new
        result = generator.generate("github-actions")

        result.should contain("deploy:")
        result.should contain("Build and Deploy")
        result.should contain("token: ${{ secrets.GITHUB_TOKEN }}")
        result.should contain("github.event_name == 'push'")
        result.should contain("github.ref == 'refs/heads/main'")
      end

      it "includes permissions" do
        generator = Hwaro::Services::CIConfig.new
        result = generator.generate("github-actions")

        result.should contain("permissions:")
        result.should contain("contents: write")
      end
    end

    it "raises for unsupported provider" do
      generator = Hwaro::Services::CIConfig.new
      expect_raises(Exception, /Unsupported CI provider/) do
        generator.generate("gitlab-ci")
      end
    end
  end
end
