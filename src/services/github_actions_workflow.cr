module Hwaro
  module Services
    # The GitHub Actions deploy workflow YAML. Shared by `hwaro tool ci`
    # (CIConfig) and `hwaro tool platform github-pages` (PlatformConfig) so the
    # two generators stay byte-for-byte in lockstep — both write the same
    # `.github/workflows/deploy.yml`.
    module GithubActionsWorkflow
      def self.content : String
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
        lines << "    if: (github.event_name == 'push' || github.event_name == 'workflow_dispatch') && github.ref == 'refs/heads/main'"
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
