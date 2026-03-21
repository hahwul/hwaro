+++
title = "Deploy"
description = "Build and deploy your site to production"
+++

Deploy your Hwaro site to any static hosting provider.

## Build for Production

```bash
hwaro build
```

This generates static files in `public/`. You can optionally minify output:

```bash
hwaro build --minify
```

This performs conservative optimization — HTML comments and trailing whitespace are removed, JSON/XML whitespace is compacted. All code blocks and content structure are preserved.

## General Steps

1. Build the site: `hwaro build`
2. Upload `public/` directory to your host (or use `hwaro deploy`)
3. Configure your domain

## Built-in Deploy Command

Hwaro includes `hwaro deploy` for deploying to configured targets:

```bash
hwaro deploy              # Deploy to default target
hwaro deploy --target s3  # Deploy to specific target
hwaro deploy --dry-run    # Preview changes
```

See [Deploy Configuration](/deploy/config/) for full target setup, matchers, and options.

## Platform Guides

See the platform-specific guides below for step-by-step deployment instructions.
