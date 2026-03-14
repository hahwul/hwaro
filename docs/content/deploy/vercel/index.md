+++
title = "Vercel"
description = "Deploy your Hwaro site to Vercel"
weight = 6
+++

Deploy your Hwaro site to Vercel with zero-config deployments.

## Quick Start

### Generate Config

```bash
hwaro tool platform vercel
```

This creates a `vercel.json` with build settings, redirects from aliases, and cache headers.

### Deploy via Git

1. Push your repository to GitHub, GitLab, or Bitbucket
2. Go to [Vercel](https://vercel.com) and click **Add New** > **Project**
3. Import your repository
4. Vercel will auto-detect `vercel.json` settings
5. Click **Deploy**

## Manual Configuration

If you prefer to configure manually, create `vercel.json`:

```json
{
  "buildCommand": "hwaro build",
  "outputDirectory": "public"
}
```

## Redirects

Page aliases defined in frontmatter are automatically included as 301 redirects when using `hwaro tool platform vercel`:

```markdown
---
title: New Post
aliases:
  - /old-url/
---
```

Generates:

```json
{
  "redirects": [
    {
      "source": "/old-url/",
      "destination": "/posts/new-post/",
      "statusCode": 301
    }
  ]
}
```

## Custom Domain

1. Go to **Settings** > **Domains**
2. Add your custom domain
3. Follow DNS configuration instructions
4. Update `base_url` in `config.toml`:

```toml
base_url = "https://www.yourdomain.com"
```

## Preview Deployments

Vercel automatically creates preview deployments for every push to non-production branches. No additional configuration is needed.

## See Also

- [Tools — Platform Config Generator](/start/tools/#platform--platform-config-generator) — Detailed generator options
- [CLI Reference](/start/cli/#tool) — All tool commands
- Other platforms: [Netlify](/deploy/netlify/) | [Cloudflare Pages](/deploy/cloudflare-pages/) | [GitHub Pages](/deploy/github-pages/)
