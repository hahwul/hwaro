+++
title = "ci"
description = "Generate CI/CD workflow files"
weight = 6
+++

Generate CI/CD workflow files for automated build and deployment pipelines.

```bash
# Generate GitHub Actions workflow
hwaro tool ci github-actions

# Output to custom path
hwaro tool ci github-actions -o .github/workflows/custom.yml

# Print to stdout instead of writing file
hwaro tool ci github-actions --stdout
```

## Supported Providers

| Provider | Output File | Description |
|----------|-------------|-------------|
| github-actions | `.github/workflows/deploy.yml` | Build and deploy via GitHub Actions |

## Options

| Flag | Description |
|------|-------------|
| -o, --output PATH | Output file path (default: auto-detected) |
| --stdout | Print to stdout instead of writing file |
| -f, --force | Overwrite existing file without warning |
| -h, --help | Show help |

If the output file already exists, use `--force` to overwrite.

## Generated Workflow

The workflow includes:

- **Trigger**: Push to `main`, pull requests to `main`, and manual `workflow_dispatch`
- **Build job**: Runs on pull requests for CI validation using the official `hahwul/hwaro` action
- **Deploy job**: Runs on push to `main` to build and deploy to GitHub Pages
- **Permissions**: `contents: write` for GitHub Pages deployment

### Example Output

```yaml
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
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build and Deploy
        uses: hahwul/hwaro@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

## See Also

- [GitHub Pages](/deploy/github-pages/) — GitHub Pages deploy guide
- [CLI Reference](/start/cli/#tool) — All tool commands
