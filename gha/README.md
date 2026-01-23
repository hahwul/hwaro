# Hwaro Deploy Action

GitHub Action for building and deploying [Hwaro](https://github.com/hahwul/hwaro) static sites to GitHub Pages.

## Usage

### Basic Usage

```yaml
name: Deploy Hwaro Site

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build and Deploy
        uses: hahwul/hwaro@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

### Build Only (for Pull Requests)

```yaml
name: Hwaro CI

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    if: github.ref != 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build Only
        uses: hahwul/hwaro@main
        with:
          build_only: true

  deploy:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build and Deploy
        uses: hahwul/hwaro@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

### With Custom Options

```yaml
- name: Build and Deploy
  uses: hahwul/hwaro@main
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    pages_branch: gh-pages
    build_dir: docs
    output_dir: public
    build_flags: "--drafts --minify"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `token` | GitHub token for deployment | No | `${{ github.token }}` |
| `pages_branch` | Target branch for GitHub Pages | No | `gh-pages` |
| `build_dir` | Directory containing Hwaro site source | No | `.` |
| `output_dir` | Output directory for built site | No | `public` |
| `build_flags` | Additional flags for `hwaro build` | No | `""` |
| `build_only` | Build without deploying | No | `false` |
| `repository` | Target repository (owner/repo) | No | Current repository |
| `github_hostname` | GitHub hostname (for Enterprise) | No | `github.com` |

## Build Flags

You can pass any valid `hwaro build` flags:

- `--drafts` - Include draft content
- `--minify` - Minify HTML output
- `--no-parallel` - Disable parallel processing
- `--cache` - Enable build caching
- `-o DIR` - Custom output directory

Example:
```yaml
build_flags: "--drafts --minify --cache"
```

## Permissions

Make sure your repository has the correct permissions for GitHub Actions:

1. Go to **Settings** > **Actions** > **General**
2. Under **Workflow permissions**, select **Read and write permissions**
3. Save the changes

## Custom Domain

If you're using a custom domain for your GitHub Pages site, place a `CNAME` file in your `static/` directory with your domain name:

```
static/CNAME
```

Content:
```
example.com
```

Hwaro will copy this file to the root of your built site.

## Deploying to a Different Repository

To deploy to a different repository, you need to use a Personal Access Token (PAT) with appropriate permissions:

```yaml
- name: Build and Deploy to Another Repo
  uses: hahwul/hwaro@main
  with:
    token: ${{ secrets.PERSONAL_ACCESS_TOKEN }}
    repository: "owner/other-repo"
```

## License

MIT License - See [LICENSE](../LICENSE) for details.