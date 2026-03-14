+++
title = "Netlify"
description = "Deploy your Hwaro site to Netlify"
weight = 5
+++

Deploy your Hwaro site to Netlify with automatic builds and global CDN.

## Quick Start

### Generate Config

```bash
hwaro tool platform netlify
```

This creates a `netlify.toml` with build settings, redirects from aliases, and cache headers.

### Deploy via Git

1. Push your repository to GitHub, GitLab, or Bitbucket
2. Go to [Netlify](https://app.netlify.com) and click **Add new site** > **Import an existing project**
3. Connect your repository
4. Netlify will auto-detect `netlify.toml` settings
5. Click **Deploy site**

## Manual Configuration

If you prefer to configure manually instead of using the generator, create `netlify.toml`:

```toml
[build]
  command = "hwaro build"
  publish = "public"

[build.environment]
  # Set environment variables as needed
```

## Redirects

Page aliases defined in frontmatter are automatically included as 301 redirects when using `hwaro tool platform netlify`:

```markdown
---
title: New Post
aliases:
  - /old-url/
  - /legacy/post/
---
```

Generates:

```toml
[[redirects]]
  from = "/old-url/"
  to = "/posts/new-post/"
  status = 301

[[redirects]]
  from = "/legacy/post/"
  to = "/posts/new-post/"
  status = 301
```

## Custom Domain

1. Go to **Site settings** > **Domain management**
2. Click **Add custom domain**
3. Follow the DNS configuration instructions
4. Update `base_url` in `config.toml`:

```toml
base_url = "https://www.yourdomain.com"
```

## Deploy Previews

Netlify automatically creates deploy previews for pull requests. Preview builds use a temporary URL, so override the base URL using a deploy context:

```toml
[context.deploy-preview]
  command = "hwaro build --base-url $DEPLOY_PRIME_URL"
```

`$DEPLOY_PRIME_URL` is a Netlify-provided environment variable containing the unique preview URL (e.g., `https://deploy-preview-42--your-site.netlify.app`).

## See Also

- [Platform Config Generator](/start/tools/platform/) — Detailed generator options
- [CLI Reference](/start/cli/#tool) — All tool commands
- Other platforms: [Vercel](/deploy/vercel/) | [Cloudflare Pages](/deploy/cloudflare-pages/) | [GitHub Pages](/deploy/github-pages/)
