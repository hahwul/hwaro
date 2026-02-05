+++
title = "GitHub Pages"
weight = 2
+++

Deploy your Hwaro site to GitHub Pages for free hosting.

## Prerequisites

- GitHub repository
- Hwaro site ready to build

## Method 1: GitHub Actions (Recommended)

### Create Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Crystal
        uses: crystal-lang/install-crystal@v1
        with:
          crystal: latest
      
      - name: Install Hwaro
        run: |
          git clone https://github.com/hahwul/hwaro /tmp/hwaro
          cd /tmp/hwaro
          shards install
          shards build --release
          sudo mv bin/hwaro /usr/local/bin/
      
      - name: Build site
        run: hwaro build
      
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: public

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### Configure GitHub Pages

1. Go to repository **Settings** → **Pages**
2. Under "Build and deployment", select **GitHub Actions**
3. Push to `main` branch to trigger deployment

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

- Check Crystal version compatibility
- Review Actions logs for error messages
- Ensure `shards.yml` dependencies are correct

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
