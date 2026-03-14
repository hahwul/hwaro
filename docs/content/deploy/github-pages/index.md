+++
title = "GitHub Pages"
description = "Deploy your Hwaro site to GitHub Pages"
weight = 2
+++

Deploy your Hwaro site to GitHub Pages for free hosting.

## Prerequisites

- GitHub repository
- Hwaro site ready to build

## Method 1: GitHub Actions (Recommended)

Use the official [`hahwul/hwaro`](https://github.com/hahwul/hwaro) action to build and deploy without installing Hwaro manually.

### Create Workflow

You can auto-generate the workflow file using:

```bash
hwaro tool ci github-actions
```

Or create `.github/workflows/deploy.yml` manually:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    if: github.ref != 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build Only
        uses: hahwul/hwaro@main
        with:
          build_only: true

  deploy:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build and Deploy
        uses: hahwul/hwaro@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

### Action Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `build_dir` | Directory containing the Hwaro site | `.` (repository root) |
| `build_only` | Only build without deploying | `false` |
| `token` | GitHub token for deployment | — |

If your Hwaro site is in a subdirectory (e.g., `docs/`), set `build_dir`:

```yaml
- name: Build and Deploy
  uses: hahwul/hwaro@main
  with:
    build_dir: "docs"
    token: ${{ secrets.GITHUB_TOKEN }}
```

### Configure GitHub Pages

1. Go to repository **Settings** → **Pages**
2. Under "Build and deployment", select **Deploy from a branch**
3. Choose `gh-pages` branch, `/ (root)` folder
4. Push to `main` branch to trigger deployment

### Set Base URL

Update `config.toml`:

```toml
# For user/org site (username.github.io)
base_url = "https://username.github.io"

# For project site (username.github.io/repo)
base_url = "https://username.github.io/repo"
```

## Method 2: Deploy from Branch

### Build Locally

```bash
hwaro build
```

### Push to gh-pages Branch

```bash
# Create orphan branch
git checkout --orphan gh-pages

# Remove all files
git rm -rf .

# Copy built site
cp -r public/* .

# Commit and push
git add .
git commit -m "Deploy site"
git push origin gh-pages --force

# Return to main branch
git checkout main
```

### Configure GitHub Pages

1. Go to repository **Settings** → **Pages**
2. Under "Build and deployment", select **Deploy from a branch**
3. Choose `gh-pages` branch, `/ (root)` folder
4. Click **Save**

## Custom Domain

### Configure DNS

Add a CNAME record pointing to `username.github.io`:

| Type | Name | Value |
|------|------|-------|
| CNAME | www | username.github.io |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

### Add CNAME File

Create `static/CNAME`:

```
www.yourdomain.com
```

### Update Config

```toml
base_url = "https://www.yourdomain.com"
```

### Enable HTTPS

1. Go to repository **Settings** → **Pages**
2. Check **Enforce HTTPS**

## Troubleshooting

### 404 Errors

- Check `base_url` matches your GitHub Pages URL
- Ensure CNAME file is in `static/` directory
- Wait a few minutes for deployment to complete

### Assets Not Loading

- Verify `base_url` has no trailing slash
- Check asset paths use `{{ base_url }}` prefix

### Build Failures

- Review Actions logs for error messages
- Check that `build_dir` points to the correct directory

## Example Repository Structure

```
my-site/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── content/
├── templates/
├── static/
│   └── CNAME
├── config.toml
└── README.md
```
