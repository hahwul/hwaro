+++
title = "Deploy"
description = "Build and deploy your site to production"
+++

Deploy your Hwaro site to any static hosting provider.

## Built-in Deploy Command

Hwaro includes a built-in `hwaro deploy` command for deploying to configured targets:

```bash
# Deploy to default target
hwaro deploy

# Deploy to a specific target
hwaro deploy prod

# Preview changes without deploying
hwaro deploy --dry-run
```

Configure deployment targets in `config.toml`:

```toml
[deployment]
source_dir = "public"

[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
command = "aws s3 sync {source}/ {url} --delete"
```

See [CLI Reference](/start/cli/#deploy) for all deploy options and [Configuration](/start/config/#deployment) for target setup.

## Build for Production

```bash
hwaro build
```

This generates static files in `public/`.

### Optional: Minification

You can optionally minify output files:

```bash
hwaro build --minify
```

This performs conservative optimization:
- **HTML**: Removes comments and trailing whitespace
- **JSON/XML**: Compacts whitespace for smaller files

All code blocks and content structure are preserved. See [CLI Reference](/start/cli/#build) for details.

## Hosting Options

Static sites can be deployed anywhere:

- [GitHub Pages](/deploy/github-pages/) — Free hosting from GitHub
- [Docker](/deploy/docker/) — Containerized deployment
- [GitLab CI](/deploy/gitlab-ci/) — GitLab Pages via CI/CD
- **Netlify** — Drag and drop or Git integration
- **Vercel** — Zero-config deployments
- **Cloudflare Pages** — Fast global CDN
- **AWS S3 + CloudFront** — Scalable hosting
- **Any web server** — Nginx, Apache, etc.

## General Steps

1. Build the site: `hwaro build`
2. Upload `public/` directory to your host (or use `hwaro deploy`)
3. Configure your domain
