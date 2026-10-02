module Hwaro
  module Services
    # The GitHub Actions deploy workflow YAML. Shared by `hwaro tool ci`
    # (CIConfig) and `hwaro tool platform github-pages` (PlatformConfig) so the
    # two generators stay byte-for-byte in lockstep — both write the same
    # `.github/workflows/deploy.yml`.
    module GithubActionsWorkflow
      def self.content : String
        <<-YAML
          ---
          name: Hwaro CI/CD

          on:
            push:
              branches: [main]
            pull_request:
              branches: [main]
            workflow_dispatch:

          permissions:
            contents: write

          jobs:
            build:
              runs-on: ubuntu-latest
              if: github.event_name == 'pull_request'
              steps:
                - name: Checkout
                  uses: actions/checkout@v6

                - name: Build Only
                  uses: hahwul/hwaro@main
                  with:
                    build_only: true

            deploy:
              runs-on: ubuntu-latest
              if: (github.event_name == 'push' || github.event_name == 'workflow_dispatch') && github.ref == 'refs/heads/main'
              steps:
                - name: Checkout
                  uses: actions/checkout@v6

                - name: Build and Deploy
                  uses: hahwul/hwaro@main
                  with:
                    token: ${{ secrets.GITHUB_TOKEN }}

          YAML
      end
    end
  end
end
