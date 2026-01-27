+++
title = "Overview"
toc = true
+++

Deploy your Hwaro site to any static hosting provider.

If you haven’t built a site yet, start with: [Quickstart](/guide/quickstart/).

## Build for Production

```bash
hwaro build --minify
```

This creates optimized files in `public/`.

## hwaro deploy

You can configure deployment targets in `config.toml` and deploy with:

```bash
hwaro deploy <targets>
```

Example `config.toml`:

```toml
[deployment]
target = "prod"

[[deployment.targets]]
name = "prod"
url = "file://./out"

[[deployment.targets]]
name = "s3"
url = "s3://your-bucket"
command = "aws s3 sync {source}/ {url} --delete"
```

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
