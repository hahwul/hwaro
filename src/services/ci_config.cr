require "../utils/logger"

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
        lines = [] of String
        lines << "---"
        lines << "name: Hwaro CI/CD"
        lines << ""
        lines << "on:"
        lines << "  push:"
        lines << "    branches: [main]"
        lines << "  pull_request:"
        lines << "    branches: [main]"
        lines << "  workflow_dispatch:"
        lines << ""
        lines << "permissions:"
        lines << "  contents: write"
        lines << ""
        lines << "jobs:"
        lines << "  build:"
        lines << "    runs-on: ubuntu-latest"
        lines << "    if: github.event_name == 'pull_request'"
        lines << "    steps:"
        lines << "      - name: Checkout"
        lines << "        uses: actions/checkout@v6"
        lines << ""
        lines << "      - name: Build Only"
        lines << "        uses: hahwul/hwaro@main"
        lines << "        with:"
        lines << "          build_only: true"
        lines << ""
        lines << "  deploy:"
        lines << "    runs-on: ubuntu-latest"
        lines << "    if: github.event_name == 'push' && github.ref == 'refs/heads/main'"
        lines << "    steps:"
        lines << "      - name: Checkout"
        lines << "        uses: actions/checkout@v6"
        lines << ""
        lines << "      - name: Build and Deploy"
        lines << "        uses: hahwul/hwaro@main"
        lines << "        with:"
        lines << "          token: ${{ secrets.GITHUB_TOKEN }}"
        lines << ""

        lines.join("\n")
      end
    end
  end
end
