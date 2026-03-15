+++
title = "PWA"
description = "Progressive Web App support with manifest.json and service worker"
weight = 17
toc = true
+++

Hwaro can generate Progressive Web App (PWA) files to enable offline access and installability for your site.

## What Gets Generated

When `[pwa]` is enabled, two files are added to your build output:

- **`manifest.json`** — Web app manifest describing your app (name, icons, theme, display mode)
- **`sw.js`** — Service worker for offline caching with a cache-first strategy

## Configuration

```toml
[pwa]
enabled = true
name = "My Blog"
short_name = "Blog"
theme_color = "#1a1a2e"
background_color = "#ffffff"
display = "standalone"
start_url = "/"
icons = ["static/icon-192.png", "static/icon-512.png"]
offline_page = "/offline.html"
precache_urls = ["/", "/about/", "/css/main.css"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable PWA file generation |
| name | string | site title | Full application name |
| short_name | string | name | Short name for home screen |
| theme_color | string | "#ffffff" | Browser toolbar / status bar color |
| background_color | string | "#ffffff" | Splash screen background color |
| display | string | "standalone" | Display mode |
| start_url | string | "/" | URL when the app launches |
| icons | array | [] | Icon file paths |
| offline_page | string | — | Fallback page when offline |
| precache_urls | array | [] | URLs to cache during service worker install |

## Icon Sizing

Icon sizes are automatically extracted from filenames:

| Filename | Detected Size |
|----------|--------------|
| `icon-192.png` | 192x192 |
| `icon-512x512.png` | 512x512 |
| `logo-180.svg` | 180x180 |

Place icon files in your `static/` directory so they are copied to the build output.

## Template Integration

Add the manifest link and service worker registration to your base template:

```html
<head>
  <link rel="manifest" href="/manifest.json">
  <meta name="theme-color" content="{{ config.pwa.theme_color }}">
</head>
<body>
  ...
  <script>
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js');
    }
  </script>
</body>
```

## Caching Strategy

The generated service worker uses:

- **Precache on install** — URLs listed in `precache_urls` plus `start_url` are cached immediately
- **Cache-first for assets** — Subsequent requests serve from cache, falling back to network
- **Network-first for navigation** — Page navigations try the network first, falling back to the offline page
- **Automatic cache versioning** — Old caches are cleaned up on service worker activation

## Offline Page

If `offline_page` is set, create a static HTML page at that path (e.g., `content/offline.md` or `static/offline.html`) that will be shown when the user navigates while offline.

## See Also

- [Configuration](/start/config/) — Full config reference
- [SEO](/features/seo/) — Sitemaps, feeds, and OpenGraph
