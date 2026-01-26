+++
title = "Overview"
toc = true
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
