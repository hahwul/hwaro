+++
title = "Overview"
+++

Deploy your Hwaro site to any static hosting provider.

## Build for Production

```bash
hwaro build --minify
```

This creates optimized files in `public/`.

## Deployment Options

### Static Hosts

| Provider | Command |
|----------|---------|
| Netlify | Connect repo, build: `hwaro build --minify` |
| Vercel | Connect repo, build: `hwaro build --minify` |
| GitHub Pages | Use GitHub Actions workflow |
| Cloudflare Pages | Connect repo, build: `hwaro build --minify` |

### Manual Deploy

Upload `public/` folder to any web server:

```bash
# rsync to server
rsync -avz public/ user@server:/var/www/html/

# AWS S3
aws s3 sync public/ s3://your-bucket/ --delete

# FTP
lftp -c "mirror -R public/ /public_html"
```

## GitHub Actions

`.github/workflows/deploy.yml`:

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

## Post-Build Hooks

Automate deployment with build hooks:

```toml
[build]
hooks.post = ["./scripts/deploy.sh"]
```

Example `scripts/deploy.sh`:

```bash
#!/bin/bash
rsync -avz --delete public/ user@server:/var/www/html/
```

## Environment Variables

For CI/CD pipelines:

```bash
# Set base_url for production
export HWARO_BASE_URL="https://example.com"
hwaro build --minify
```
