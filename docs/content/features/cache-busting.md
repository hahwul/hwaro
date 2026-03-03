+++
title = "Cache Busting"
weight = 7
toc = true
+++

Cache busting automatically appends a `?v=<hash>` query parameter to locally served CSS and JS resource URLs. This forces browsers to fetch the latest version of assets when their content changes, preventing stale cached files from being used.

## How It Works

Hwaro computes an MD5 content hash of your local CSS/JS files and appends the first 8 characters as a query parameter. The hash only changes when file contents actually change, so browsers keep using their cache until a real update occurs.

```html
<!-- With cache busting (default) -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=3a8f1b2c">
<script src="/assets/js/highlight.min.js?v=3a8f1b2c"></script>
<link rel="stylesheet" href="/assets/css/style.css?v=3a8f1b2c">

<!-- Without cache busting -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css">
<script src="/assets/js/highlight.min.js"></script>
<link rel="stylesheet" href="/assets/css/style.css">
```

## Content Hash vs Timestamp

Hwaro uses a **content-based hash** rather than a build timestamp. This means:

- The hash stays the same across builds if files haven't changed — no unnecessary cache invalidation
- The hash changes immediately when any CSS/JS file content is modified
- Different build machines produce the same hash for identical files

## CDN URLs Are Not Modified

Cache busting only applies to **local** resource URLs. CDN URLs (e.g., cdnjs.cloudflare.com) already contain version numbers in their paths and are not modified:

```html
<!-- CDN URL — unchanged -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">

<!-- Local URL — cache busted -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=3a8f1b2c">
```

## Affected Template Variables

Cache busting applies to the following template variables:

| Variable | Description |
|----------|-------------|
| `highlight_css` | Syntax highlighting CSS (local only) |
| `highlight_js` | Syntax highlighting JS (local only) |
| `highlight_tags` | Combined highlighting CSS + JS (local only) |
| `auto_includes_css` | Auto-included CSS files |
| `auto_includes_js` | Auto-included JS files |
| `auto_includes` | Combined auto-included CSS + JS |

## Disabling Cache Busting

Cache busting is enabled by default. To disable it, use the `--skip-cache-busting` flag:

```bash
# Build without cache busting
hwaro build --skip-cache-busting

# Serve without cache busting
hwaro serve --skip-cache-busting
```

This can be useful when you manage cache invalidation through other means (e.g., filename hashing, CDN purge).

## See Also

- [Syntax Highlighting](/features/syntax-highlighting/) — Highlight.js configuration
- [Auto Includes](/features/auto-includes/) — Automatic CSS/JS loading
- [CLI](/start/cli/) — Command-line options
