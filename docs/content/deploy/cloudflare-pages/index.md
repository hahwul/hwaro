+++
title = "Cloudflare Pages"
description = "Deploy your Hwaro site to Cloudflare Pages"
weight = 7
+++

Deploy your Hwaro site to Cloudflare Pages for fast global delivery.

## Quick Start

### Generate Config

```bash
hwaro tool platform cloudflare
```

This creates a `wrangler.toml` with project settings and site bucket configuration.

### Deploy via Dashboard

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) > **Workers & Pages**
2. Click **Create application** > **Pages** > **Connect to Git**
3. Select your repository
4. Set build configuration:
   - **Build command**: `hwaro build`
   - **Build output directory**: `public`
5. Click **Save and Deploy**

### Deploy via Wrangler CLI

```bash
# Install Wrangler
npm install -g wrangler

# Build the site
hwaro build

# Deploy
wrangler pages deploy public --project-name my-site
```

## Manual Configuration

If you prefer to configure manually, set these in the Cloudflare Pages dashboard:

| Setting | Value |
|---------|-------|
| Build command | `hwaro build` |
| Build output directory | `public` |

Or create `wrangler.toml`:

```toml
name = "my-site"
compatibility_date = "2024-01-01" # Use current date when deploying

[site]
  bucket = "./public"
```

## Redirects

Cloudflare Pages uses a `_redirects` file in the output directory. Create `static/_redirects` with redirect rules for your page aliases:

```
/old-url/ /posts/new-post/ 301
/legacy/post/ /posts/new-post/ 301
```

Aliases are defined in page frontmatter:

```markdown
---
title: New Post
aliases:
  - /old-url/
  - /legacy/post/
---
```

When using `hwaro tool platform cloudflare`, the generated `wrangler.toml` includes comments listing these redirects so you can copy them into `static/_redirects`.

## Custom Domain

1. Go to **Workers & Pages** > your project > **Custom domains**
2. Click **Set up a custom domain**
3. Follow DNS configuration instructions
4. Update `base_url` in `config.toml`:

```toml
base_url = "https://www.yourdomain.com"
```

## Preview Deployments

Cloudflare Pages automatically creates preview deployments for every branch push. Preview URLs follow the pattern: `<branch>.<project>.pages.dev`.

## See Also

- [Tools — Platform Config Generator](/start/tools/#platform--platform-config-generator) — Detailed generator options
- [CLI Reference](/start/cli/#tool) — All tool commands
- Other platforms: [Netlify](/deploy/netlify/) | [Vercel](/deploy/vercel/) | [GitHub Pages](/deploy/github-pages/)
