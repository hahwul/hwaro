+++
title = "Deploy"
description = "Build and deploy your site to production"
weight = 5
sort_by = "weight"
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

Everything in `static/` is copied into `public/` and deployed — including hidden dot-paths such as `.well-known/security.txt` and `.domains` — identically for cold and `--cache`/incremental builds. Common OS/editor/VCS cruft (`.DS_Store`, `.git/`, …) is filtered out automatically; see [Static Files](/start/config/#static-files) to tune it.

## General Steps

1. Build the site: `hwaro build`
2. Upload `public/` directory to your host (or use `hwaro deploy`)
3. Configure your domain

## Built-in Deploy Command

Hwaro includes `hwaro deploy` for deploying to configured targets:

```bash
hwaro deploy              # Deploy to the first configured target
hwaro deploy s3           # Deploy to a specific target by name
hwaro deploy s3 backup    # Deploy to multiple targets
hwaro deploy --dry-run    # Preview changes
```

See [Deploy Configuration](/deploy/config/) for full target setup, matchers, and options.

## Platform Guides

See the platform-specific guides below for step-by-step deployment instructions.
