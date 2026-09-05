+++
title = "PWA"
description = "Progressive Web App support with manifest.json and service worker"
weight = 24
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
cache_strategy = "cache-first"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable PWA file generation |
| name | string | site title | Full application name |
| short_name | string | name | Short name for home screen |
| theme_color | string | "#ffffff" | Browser toolbar / status bar color |
| background_color | string | "#ffffff" | Splash screen background color |
| display | string | "standalone" | Display mode: `fullscreen`, `standalone`, `minimal-ui` or `browser` (an unknown value falls back to `standalone`) |
| start_url | string | "/" | URL when the app launches |
| icons | array | [] | Icon file paths |
| offline_page | string | — | Fallback page when offline |
| precache_urls | array | [] | URLs to cache during service worker install |
| cache_strategy | string | `"cache-first"` | Asset fetch strategy: `cache-first`, `network-first`, or `stale-while-revalidate` |

> Write `start_url`, `icons`, `offline_page`, and `precache_urls` as plain root-relative paths **without** your `base_url` prefix (e.g. `start_url = "/"`, not `"/repo/"`). When `base_url` includes a subpath (GitHub Pages project sites), Hwaro prepends it automatically in the generated `manifest.json` and `sw.js`.

## Icon Sizing

The `sizes` field of each icon is measured from the file itself: the real
pixel dimensions read out of the PNG, JPEG, or BMP header. Browsers pick the
install icon by this value, so a measured size is always preferred over a
guess.

| Icon | Declared `sizes` |
|------|------------------|
| `logo.png` (200x60 on disk) | 200x60 |
| `icon-2024.jpg` (192x192 on disk) | 192x192 |
| `favicon.svg` | `any` (scalable — no pixel size) |
| `icon-192.png` (unreadable / missing) | 192x192 (from the filename) |
| `icon-512x512.png` (unreadable / missing) | 512x512 (from the filename) |
| `logo.webp`, `https://cdn.example/icon.png` | from the filename, else 512x512 |

The filename heuristic is only a fallback: it applies to formats whose header
Hwaro cannot read (WebP, ICO), to remote `http(s)://` icons, and to files whose
bytes turn out to be unreadable. A build warning names the icon when that
happens.

Place icon files in your `static/` directory so they are copied to the build output.

## Template Integration

The easiest wiring is the `{{ pwa_tags }}` template variable. It expands to
the manifest link, a theme-color meta, and the service worker registration
(already base-path-prefixed), and renders as an empty string while `[pwa]` is
disabled. The scaffold header templates include it out of the box:

```jinja
<head>
  {{ pwa_tags }}
</head>
```

To wire things manually instead, add the manifest link and service worker
registration to your base template:

```html
<head>
  <link rel="manifest" href="{{ base_url }}/manifest.json">
  <meta name="theme-color" content="{{ config.pwa.theme_color }}">
</head>
<body>
  ...
  <script>
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('{{ base_url }}/sw.js');
    }
  </script>
</body>
```

> The `{{ base_url }}` prefix is required so the manifest and service worker
> resolve correctly on subpath deploys (e.g. GitHub Pages project sites served
> at `https://user.github.io/repo/`). The generated `manifest.json`/`sw.js`
> already carry the subpath internally, but their `<link>`/`register()` URLs do
> not unless you add it here.

## Caching Strategy

The generated service worker uses:

- **Precache on install** — URLs listed in `precache_urls` plus `start_url` are cached immediately
- **Asset fetching** — Controlled by `cache_strategy` (see below)
- **Network-first for navigation** — Page navigations always try the network first, falling back to the offline page
- **Automatic cache versioning** — Old caches are cleaned up on service worker activation

Set `cache_strategy` to pick how assets (non-navigation requests) are served:

| Value | Behavior |
|-------|----------|
| `cache-first` (default) | Serve from cache if present, otherwise fetch from network and cache the response. Fastest for static sites. |
| `network-first` | Try the network first; fall back to cache on failure. Use when you want fresh content but offline resilience. |
| `stale-while-revalidate` | Serve the cached copy immediately and refresh the cache in the background. Balances speed and freshness. |

Unknown values log a warning and fall back to `cache-first`.

## Offline Page

If `offline_page` is set, create a static HTML page at that path (e.g., `content/offline.md` or `static/offline.html`) that will be shown when the user navigates while offline.

## See Also

- [Configuration](/start/config/) — Full config reference
- [SEO](/features/seo/) — Sitemaps, feeds, and OpenGraph
