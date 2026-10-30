+++
title = "AMP"
description = "Generate AMP-compliant versions of content pages"
weight = 25
toc = true
+++

Hwaro can automatically generate AMP (Accelerated Mobile Pages) versions of your content alongside the regular pages.

## How It Works

1. Regular pages are rendered normally
2. After rendering, Hwaro reads each page's HTML and creates an AMP-compliant version
3. AMP pages are written under a configurable path prefix (default: `/amp/`)
4. A `<link rel="amphtml">` tag is injected into the canonical page's `<head>`

## Configuration

```toml
[amp]
enabled = true
path_prefix = "amp"
sections = ["posts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable AMP page generation |
| path_prefix | string | "amp" | URL prefix for AMP pages |
| sections | array | [] | Sections to generate AMP for (empty = all); a section also covers its subsections (`"posts"` includes `posts/2024`), as in `[feeds]` |

## What Gets Converted

The AMP converter automatically applies these transformations:

| Original | AMP Version |
|----------|-------------|
| `<html>` | `<html amp>` |
| `<img>` | `<amp-img layout="responsive">` when it has `width` and `height`; otherwise `<amp-img layout="fill">` inside `<div class="amp-img-container">` |
| `<video>` | `<amp-video layout="responsive">` |
| `<iframe>` | `<amp-iframe layout="responsive">` (`layout="fixed-height"` when it has only a `height`), with a default `sandbox` when it has none |
| `<picture>` | Only its `<img>` is kept (the `<source>` elements are dropped), then converted as above |
| `<script>` | Removed, except JSON-LD (`type="application/ld+json"`) and scripts loaded from `cdn.ampproject.org` |
| `<link rel="stylesheet">` | Removed, except font providers AMP allows (Google Fonts, Bunny Fonts, Typekit, Font Awesome, …) |
| `<style>` blocks | Merged into the single `<style amp-custom>`, without `!important` and at-rules AMP disallows (`@import`, `@layer`, …) |
| `style="..."` attributes | Removed |
| `on*` event handlers (`onclick`, …) | Removed |
| `loading`, `decoding`, `fetchpriority` attributes | Removed (AMP elements do their own lazy loading and reject these attributes) |
| Relative `src` / `href` (`cover.png`, `../other/`) | Resolved against the original page's URL, because the AMP copy lives one directory deeper |

Additionally injected:
- AMP boilerplate CSS
- AMP runtime script (`cdn.ampproject.org/v0.js`), plus the `amp-iframe` / `amp-video` extension scripts when the page uses them
- `<link rel="canonical">` pointing to the original page

If the theme already ships `<style amp-boilerplate>`, the boilerplate, runtime and `<style>` merge are skipped; Hwaro still adds any missing extension scripts and the `<link rel="canonical">`. Drafts, `redirect_to` pages and pages with `render = false` get no AMP version. With [CSP](/features/csp/) enabled, the AMP copy carries no CSP `<meta>` tag.

## Output Structure

Given a page at `/posts/hello/`, the output is:

```
public/
  posts/hello/index.html       ← canonical (has <link rel="amphtml">)
  amp/posts/hello/index.html   ← AMP version
```

## Section Filtering

By default, AMP pages are generated for all sections. Use `sections` to limit:

```toml
[amp]
enabled = true
sections = ["posts", "blog"]   # Only these sections (and their subsections) get AMP versions
```

## Custom Path Prefix

```toml
[amp]
enabled = true
path_prefix = "mobile"    # /mobile/posts/hello/ instead of /amp/posts/hello/
```

## See Also

- [Configuration](/start/config/) — Full config reference
- [SEO](/features/seo/) — Sitemaps, feeds, and OpenGraph
