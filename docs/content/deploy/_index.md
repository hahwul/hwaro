+++
title = "Deploy"
description = "Build and deploy your site to production"
+++

Deploy your Hwaro site to any static hosting provider.

## Build for Production

```bash
hwaro build
```

This generates static files in `public/`.

> **Note:** The `--minify` flag is available for reducing file sizes, but it's experimental and may cause issues with some JavaScript or complex HTML structures. Use with caution.

## Hosting Options

Static sites can be deployed anywhere:

- [GitHub Pages](/deploy/github-pages/) — Free hosting from GitHub
- **Netlify** — Drag and drop or Git integration
- **Vercel** — Zero-config deployments
- **Cloudflare Pages** — Fast global CDN
- **AWS S3 + CloudFront** — Scalable hosting
- **Any web server** — Nginx, Apache, etc.

## General Steps

1. Build the site: `hwaro build`
2. Upload `public/` directory to your host
3. Configure your domain
