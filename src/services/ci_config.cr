require "../utils/logger"
require "./github_actions_workflow"

module Hwaro
  module Services
    class CIConfig
      SUPPORTED_PROVIDERS = ["github-actions"]

      def generate(provider : String) : String
        case provider
        when "github-actions"
          generate_github_actions
        else
          raise "Unsupported CI provider: #{provider}. Supported: #{SUPPORTED_PROVIDERS.join(", ")}"
        end
      end

      def output_path(provider : String) : String
        case provider
        when "github-actions" then ".github/workflows/deploy.yml"
        else                       raise "Unsupported CI provider: #{provider}"
        end
      end

      private def generate_github_actions : String
        GithubActionsWorkflow.content
      end
    end
  end
end
