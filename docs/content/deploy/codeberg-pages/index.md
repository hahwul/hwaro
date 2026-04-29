+++
title = "Codeberg Pages"
description = "Deploy your Hwaro site to Codeberg Pages"
weight = 7
+++

Deploy your Hwaro site to [Codeberg Pages](https://codeberg.page/) — free static hosting backed by Codeberg's Forgejo instance.

## How Codeberg Pages Works

Codeberg serves static sites in two modes:

- **User / org site** — a repository named **`pages`** under your account. Codeberg serves the *default branch* of that repo at `https://USERNAME.codeberg.page/`.
- **Project site** — any other repository. Codeberg serves a branch named **`pages`** at `https://USERNAME.codeberg.page/REPO/`.

This distinction matters: a project site pushes to a `pages` *branch*, while a user site pushes to the *default branch* (typically `main`) of the `pages` *repo*. The workflow below defaults to the project-site case and exposes `PAGES_BRANCH` so the user-site case is a one-line change.

## Prerequisites

- Codeberg account
- Repository on Codeberg (either `pages` for a user site, or any repo for a project site)
- A Codeberg access token with `write:repository` scope (Settings → Applications → Generate new token)

## Method 1: Forgejo Actions (Recommended)

Codeberg supports [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/), which is GitHub Actions–compatible. Forgejo Actions is opt-in per repository — enable it under **Settings → Actions** before the workflow will run.

> Forgejo also accepts workflows under `.gitea/workflows/` for backwards compatibility, but `.forgejo/workflows/` is the upstream-blessed path and the one Hwaro generates.

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
    env:
      # Project site: "pages" (default). User/org site (repo named
      # "pages"): override to your default branch, e.g. "main".
      PAGES_BRANCH: pages
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
          git init -b "$PAGES_BRANCH"
          git config user.name  "${{ github.actor }}"
          git config user.email "${{ github.actor }}@noreply.codeberg.org"
          git add -A
          git commit -m "Deploy: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
          git push --force \
            "https://${{ github.actor }}:$CODEBERG_TOKEN@codeberg.org/${{ github.repository }}.git" \
            "$PAGES_BRANCH"
```

> **Branch history is not preserved.** Each run starts with a fresh `git init` and force-pushes, so the published branch is treated as a publish-only artifact. Keep your source on `main` (or wherever you develop); never edit the `pages` branch by hand.

### User Site vs Project Site

The default `PAGES_BRANCH: pages` targets a **project site** (any repo, served at `USERNAME.codeberg.page/REPO/`). For a **user / org site** in a repo literally named `pages`, change the branch to your default branch:

```yaml
    env:
      PAGES_BRANCH: main   # default branch of the `pages` repo
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
PAGES_BRANCH="${PAGES_BRANCH:-pages}"
TMPDIR=$(mktemp -d)

cp -r "$SOURCE_DIR"/. "$TMPDIR"

cd "$TMPDIR"
git init -b "$PAGES_BRANCH"
git add -A
git commit -m "Deploy to Codeberg Pages"
git push --force "$REMOTE_URL" "$PAGES_BRANCH"

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

# User site (push to the default branch instead of `pages`)
PAGES_BRANCH=main hwaro deploy codeberg-pages
```

As with Method 1, the script force-pushes a fresh init — branch history is not preserved.

## Method 3: Manual Branch Deploy

```bash
hwaro build

cd public
git init -b pages
git add -A
git commit -m "Deploy"
git push --force https://codeberg.org/USERNAME/REPO.git pages
```

For a user site (`pages` repo), substitute the default branch name (e.g. `main`) for `pages` in both the `init` and `push` commands.

## Custom Domain

Codeberg Pages supports custom domains via a `.domains` file plus a DNS record. See the [official Codeberg docs](https://docs.codeberg.org/codeberg-pages/using-custom-domain/) for the authoritative version.

> **Repo names with dots are unsupported.** Use `-` or `_` in the repo name if you plan to attach a custom domain.

### 1. Add a `.domains` file

Place a `.domains` file at the root of the served branch listing the domains, one per line. The **first line is the canonical domain**; all subsequent domains are 301-redirected to it. Empty lines and `#` comments are allowed.

```
www.example.org
example.org
```

Drop it under `static/.domains` so Hwaro copies it into `public/` on every build:

```
static/
└── .domains
```

### 2. Configure DNS

Pick **one** of the three options below.

**Option A — CNAME (recommended, simplest).** Point your domain at one of these names:

| Site type     | CNAME target                              |
|---------------|-------------------------------------------|
| Personal site | `USERNAME.codeberg.page`                  |
| Project site  | `REPO.USERNAME.codeberg.page`             |
| Custom branch | `BRANCH.REPO.USERNAME.codeberg.page`      |

CNAME delegates *the whole hostname*, so you cannot run email (MX) on the same name with this option.

**Option B — ALIAS + TXT.** If your DNS provider supports `ALIAS` (or `ANAME`) records:

| Type  | Name | Value                                |
|-------|------|--------------------------------------|
| ALIAS | @    | `codeberg.page`                      |
| TXT   | @    | `REPO.USERNAME.codeberg.page` (or `USERNAME.codeberg.page` for a user site) |

**Option C — A + AAAA + TXT.** Use this if your provider doesn't support ALIAS, or if your zone uses DNSSEC (which is incompatible with the `codeberg.page` CNAME):

| Type | Name | Value                                |
|------|------|--------------------------------------|
| A    | @    | `217.197.84.141`                     |
| AAAA | @    | `2a0a:4580:103f:c0de::2`             |
| TXT  | @    | `REPO.USERNAME.codeberg.page` (or `USERNAME.codeberg.page` for a user site) |

> Verify the latest IPs on the [Codeberg Pages docs](https://docs.codeberg.org/codeberg-pages/using-custom-domain/) before relying on them — Codeberg occasionally rotates them.

If your zone uses CAA records, add an entry that allows Let's Encrypt so Codeberg can issue a TLS certificate:

```
@   CAA   0 issue "letsencrypt.org"
```

### 3. Update `base_url`

```toml
base_url = "https://www.example.org"
```

## Troubleshooting

### Workflow Doesn't Run

- Make sure Forgejo Actions is enabled under **Settings → Actions** for the repository
- Confirm the workflow file is committed at `.forgejo/workflows/deploy.yml` (or `.gitea/workflows/deploy.yml`)

### Push Fails with 401 / 403

- Re-check the `CODEBERG_TOKEN` secret value and that the token still has `write:repository` scope
- Tokens are tied to your account — make sure the actor has push access to the target repo

### 404 on the Deployed Site

- Codeberg Pages may take a minute or two to publish after the first push
- For a project site, confirm the branch is named exactly `pages`
- For a user site, confirm the repo is named exactly `pages` and `PAGES_BRANCH` matches its default branch
- Verify `base_url` matches the published URL (no trailing slash)

### Custom Domain Doesn't Resolve to HTTPS

- Confirm the `.domains` file is present at the root of the published branch
- If you have CAA records, make sure `letsencrypt.org` is allowed
- Allow a few minutes for the certificate to be issued after DNS propagates

## See Also

- [Deploy Configuration](/deploy/config/) — Target setup and matchers
- [CLI Reference](/start/cli/) — All deploy command options
- [Codeberg Pages docs](https://docs.codeberg.org/codeberg-pages/) — Upstream reference
- Other platforms: [GitHub Pages](/deploy/github-pages/) | [GitLab CI](/deploy/gitlab-ci/) | [Netlify](/deploy/netlify/) | [Cloudflare Pages](/deploy/cloudflare-pages/)
