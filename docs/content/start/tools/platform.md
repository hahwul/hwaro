+++
title = "platform"
description = "Generate platform config and CI/CD workflow files"
weight = 5
+++

Generate platform configuration and CI/CD workflow files for popular providers. Reads your `config.toml` and content aliases to produce ready-to-use deploy configs.

```bash
# Hosting platforms
hwaro tool platform netlify
hwaro tool platform vercel
hwaro tool platform cloudflare

# CI/CD workflows
hwaro tool platform github-pages
hwaro tool platform gitlab-ci
hwaro tool platform codeberg-pages

# Output to custom path
hwaro tool platform netlify -o deploy/netlify.toml

# Print to stdout instead of writing file
hwaro tool platform vercel --stdout
```

> **Note:** `hwaro tool ci` is deprecated. Use `hwaro tool platform github-pages` instead.

## Supported Platforms

| Platform | Output File | Description |
|----------|-------------|-------------|
| netlify | `netlify.toml` | Build settings, redirects, headers |
| vercel | `vercel.json` | Build command, routing, cache headers |
| cloudflare | `wrangler.toml` | Workers/Pages site config |
| github-pages | `.github/workflows/deploy.yml` | GitHub Actions build + deploy workflow |
| gitlab-ci | `.gitlab-ci.yml` | GitLab CI/CD pipeline |
| codeberg-pages | `.forgejo/workflows/deploy.yml` | Codeberg Pages (Forgejo Actions) deploy workflow |

## Options

| Flag | Description |
|------|-------------|
| -o, --output PATH | Output file path (default: auto-detected) |
| --stdout | Print to stdout instead of writing file |
| -f, --force | Overwrite existing file without warning |
| -h, --help | Show help |

If the output file already exists, use `--force` to overwrite.

## Generated Config

Each config includes:

- **Build command**: `hwaro build`
- **Output directory**: `public/`
- **Redirects**: 301 redirects from page [`aliases`](/writing/pages/) defined in frontmatter (e.g., `aliases: ["/old-url/"]`)
- **Cache headers**: Long-lived caching for static assets

### Netlify Output

```toml
[build]
  command = "hwaro build"
  publish = "public"

[build.environment]
  # Add environment variables here

[[redirects]]
  from = "/old-url/"
  to = "/posts/new-post/"
  status = 301

[[headers]]
  for = "/assets/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"
```

### Vercel Output

```json
{
  "buildCommand": "hwaro build",
  "outputDirectory": "public",
  "redirects": [
    {
      "source": "/old-url/",
      "destination": "/posts/new-post/",
      "statusCode": 301
    }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    }
  ]
}
```

## See Also

- [GitHub Pages](/deploy/github-pages/) | [GitLab CI](/deploy/gitlab-ci/) | [Netlify](/deploy/netlify/) | [Vercel](/deploy/vercel/) | [Cloudflare Pages](/deploy/cloudflare-pages/) | [Codeberg Pages](/deploy/codeberg-pages/) — Platform deploy guides
- [CLI Reference](/start/cli/#tool) — All tool commands
