+++
title = "AMP"
description = "Generate AMP-compliant versions of content pages"
weight = 18
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
| sections | array | [] | Sections to generate AMP for (empty = all) |

## What Gets Converted

The AMP converter automatically applies these transformations:

| Original | AMP Version |
|----------|-------------|
| `<html>` | `<html amp>` |
| `<img>` | `<amp-img layout="responsive">` |
| `<video>` | `<amp-video layout="responsive">` |
| `<iframe>` | `<amp-iframe layout="responsive">` |
| `<script>` (inline) | Removed |
| `style="..."` attributes | Removed |
| `onclick` handlers | Removed |

Additionally injected:
- AMP boilerplate CSS
- AMP runtime script (`cdn.ampproject.org/v0.js`)
- `<link rel="canonical">` pointing to the original page

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
sections = ["posts", "blog"]   # Only these sections get AMP versions
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
