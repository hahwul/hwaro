+++
title = "Codeberg Pages"
description = "Deploy your Hwaro site to Codeberg Pages"
weight = 7
+++

Deploy your Hwaro site to [Codeberg Pages](https://codeberg.page/) — free static hosting backed by Codeberg's Forgejo instance.

## How Codeberg Pages Works

Codeberg serves static sites in two ways:

- A repository named **`pages`** under your account → published at `https://USERNAME.codeberg.page/`
- A branch named **`pages`** in any other repository → published at `https://USERNAME.codeberg.page/REPO/`

The deploy workflow is the same in both cases: push the contents of `public/` to a `pages` branch.

## Prerequisites

- Codeberg account
- Repository on Codeberg (either `pages` for a user site, or any repo for a project site)
- A Codeberg access token with `write:repository` scope (Settings → Applications → Generate new token)

## Method 1: Forgejo Actions (Recommended)

Codeberg supports [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/), which is GitHub Actions–compatible. Note that Forgejo Actions is opt-in per repository — enable it under **Settings → Actions** before the workflow will run.

### Generate the Workflow

```bash
hwaro tool platform codeberg-pages
```

This writes `.forgejo/workflows/deploy.yml`:

```yaml
---
name: Hwaro Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: docker
    container:
      image: ghcr.io/hahwul/hwaro:latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build site
        run: hwaro build

      - name: Deploy to Codeberg Pages
        env:
          CODEBERG_TOKEN: ${{ secrets.CODEBERG_TOKEN }}
        run: |
          cd public
          git init -b pages
          git config user.name  "${{ github.actor }}"
          git config user.email "${{ github.actor }}@users.noreply.codeberg.org"
          git add -A
          git commit -m "Deploy: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
          git push --force \
            "https://${{ github.actor }}:$CODEBERG_TOKEN@codeberg.org/${{ github.repository }}.git" \
            pages
```

### Add the Token Secret

1. Go to your repository **Settings → Actions → Secrets**
2. Add a new secret named `CODEBERG_TOKEN`
3. Paste your Codeberg access token (with `write:repository` scope)

### Set Base URL

Update `config.toml`:

```toml
# User/org site (repo named "pages")
base_url = "https://USERNAME.codeberg.page"

# Project site (any other repo)
base_url = "https://USERNAME.codeberg.page/REPO"
```

Push to `main` and the workflow will build and deploy automatically.

## Method 2: Deploy via `hwaro deploy`

If you'd rather deploy from your local machine, wire it up as a `[[deployment.targets]]` entry that calls a small shell script.

Create `scripts/deploy-codeberg.sh`:

```bash
#!/bin/bash
set -e

SOURCE_DIR="${1:?Usage: deploy-codeberg.sh <source-dir>}"
REMOTE_URL="${CODEBERG_REMOTE:-$(git remote get-url origin)}"
TMPDIR=$(mktemp -d)

cp -r "$SOURCE_DIR"/. "$TMPDIR"

cd "$TMPDIR"
git init -b pages
git add -A
git commit -m "Deploy to Codeberg Pages"
git push --force "$REMOTE_URL" pages

rm -rf "$TMPDIR"
```

```bash
chmod +x scripts/deploy-codeberg.sh
```

Add the target to `config.toml`:

```toml
[[deployment.targets]]
name = "codeberg-pages"
command = "scripts/deploy-codeberg.sh {source}"
```

Then build and deploy:

```bash
hwaro build
hwaro deploy codeberg-pages

# Preview without deploying
hwaro deploy codeberg-pages --dry-run
```

## Method 3: Manual Branch Deploy

```bash
hwaro build

cd public
git init -b pages
git add -A
git commit -m "Deploy"
git push --force https://codeberg.org/USERNAME/REPO.git pages
```

## Custom Domain

Codeberg Pages supports custom domains. Place a `.domains` file in the root of your `pages` branch listing the domains to serve, one per line:

```
www.example.org
example.org
```

Add the file under `static/.domains` so Hwaro copies it into `public/` on every build:

```
static/
└── .domains
```

Then point your DNS at Codeberg:

| Type  | Name | Value                |
|-------|------|----------------------|
| CNAME | www  | USERNAME.codeberg.page |
| A     | @    | 217.197.91.145        |
| AAAA  | @    | 2a0a:1580:6:5::3      |

(Verify the latest IPs on the [Codeberg Pages docs](https://docs.codeberg.org/codeberg-pages/).)

Update `config.toml`:

```toml
base_url = "https://www.example.org"
```

## Troubleshooting

### Workflow Doesn't Run

- Make sure Forgejo Actions is enabled under **Settings → Actions** for the repository
- Confirm the workflow file is committed at `.forgejo/workflows/deploy.yml`

### Push Fails with 401 / 403

- Re-check the `CODEBERG_TOKEN` secret value and that the token still has `write:repository` scope
- Tokens are tied to your account — make sure the actor has push access to the target repo

### 404 on the Deployed Site

- Codeberg Pages may take a minute or two to publish after the first push
- Confirm the branch is named exactly `pages`
- Verify `base_url` matches the published URL (no trailing slash)

## See Also

- [Deploy Configuration](/deploy/config/) — Target setup and matchers
- [CLI Reference](/start/cli/) — All deploy command options
- Other platforms: [GitHub Pages](/deploy/github-pages/) | [GitLab CI](/deploy/gitlab-ci/) | [Netlify](/deploy/netlify/) | [Cloudflare Pages](/deploy/cloudflare-pages/)
