+++
title = "Cache Busting"
weight = 7
toc = true
+++

Cache busting automatically appends a `?v=<timestamp>` query parameter to locally served CSS and JS resource URLs. This forces browsers to fetch the latest version of assets after each build, preventing stale cached files from being used.

## How It Works

When Hwaro builds your site, it generates a Unix timestamp and appends it as a query parameter to local resource URLs:

```html
<!-- With cache busting (default) -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=1709420400">
<script src="/assets/js/highlight.min.js?v=1709420400"></script>
<link rel="stylesheet" href="/assets/css/style.css?v=1709420400">

<!-- Without cache busting -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css">
<script src="/assets/js/highlight.min.js"></script>
<link rel="stylesheet" href="/assets/css/style.css">
```

The timestamp is generated once per build, so all resources within a single build share the same version string.

## CDN URLs Are Not Modified

Cache busting only applies to **local** resource URLs. CDN URLs (e.g., cdnjs.cloudflare.com) already contain version numbers in their paths and are not modified:

```html
<!-- CDN URL — unchanged -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">

<!-- Local URL — cache busted -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=1709420400">
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
