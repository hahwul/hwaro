+++
title = "Github Pages"
toc = true
+++

## CLI

> Coming soon

## GitHub Actions

### Using Hwaro Action (Recommended)

The easiest way to deploy to GitHub Pages is using the official Hwaro action:

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

### Action Inputs

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

### Build Flags

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

### Manual Workflow (Alternative)

If you prefer not to use the action:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Crystal
        uses: crystal-lang/install-crystal@v1
      
      - name: Build Hwaro
        run: |
          git clone https://github.com/hahwul/hwaro
          cd hwaro && shards build --release
          sudo cp bin/hwaro /usr/local/bin/
      
      - name: Build Site
        run: hwaro build --minify
      
      - name: Deploy
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./public
```

### Permissions

Make sure your repository has the correct permissions for GitHub Actions:

1. Go to **Settings** > **Actions** > **General**
2. Under **Workflow permissions**, select **Read and write permissions**
3. Save the changes

### Custom Domain

If you're using a custom domain for your GitHub Pages site, place a `CNAME` file in your `static/` directory:

```
static/CNAME
```

Content:

```
example.com
```

Hwaro will copy this file to the root of your built site.

### Deploying to a Different Repository

To deploy to a different repository, use a Personal Access Token (PAT):

```yaml
- name: Build and Deploy to Another Repo
  uses: hahwul/hwaro@main
  with:
    token: ${{ secrets.PERSONAL_ACCESS_TOKEN }}
    repository: "owner/other-repo"
```
