require "../utils/logger"
require "./github_actions_workflow"

module Hwaro
  module Services
    class CIConfig
      SUPPORTED_PROVIDERS = ["github-actions"]

      def generate(provider : String) : String
        raise "Unsupported CI provider: #{provider}. Supported: #{SUPPORTED_PROVIDERS.join(", ")}" unless provider == "github-actions"
        GithubActionsWorkflow.content
      end

      def output_path(provider : String) : String
        raise "Unsupported CI provider: #{provider}" unless provider == "github-actions"
        ".github/workflows/deploy.yml"
      end
    end
  end
end
