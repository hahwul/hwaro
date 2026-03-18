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

# GitHub Pages via deploy script
[[deployment.targets]]
name = "github-pages"
command = "scripts/deploy-ghpages.sh {source}"
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

## General Steps

1. Build the site: `hwaro build`
2. Upload `public/` directory to your host (or use `hwaro deploy`)
3. Configure your domain
