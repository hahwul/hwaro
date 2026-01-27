+++
title = "Production Checklist"
toc = true
+++

Use this checklist right before you ship.

## URL + SEO basics

- Set `base_url` in `config.toml` to the final URL (no trailing slash).
- Enable sitemap and robots (usually on by default).
- Set OpenGraph defaults (image, twitter card).

See: [Configuration](/getting-started/configuration/).

## Build settings

```bash
hwaro build --minify
```

- Prefer `--minify` for production.
- Use `--cache` if you have large sites and rebuild often.

## Static assets

- Put files under `static/` to copy them as-is to output.
- Use build hooks to compile assets (Tailwind, Vite, etc.).

Example:

```toml
[build]
hooks.pre = ["npm ci", "npm run build"]
```

See: [CLI Usage](/getting-started/cli/#build-hooks).

## Deploy

- Deploy the `public/` directory to any static host.
- For GitHub Pages, use the action: [Github Pages](/deployment/github-pages/).

## Common gotchas

- **Broken links in production**: `base_url` is empty or wrong.
- **CSS/JS missing**: files are not under `static/`, or your build hook didn’t run.
- **Search missing**: `[search].enabled` is false, or you’re not deploying `search.json`.
