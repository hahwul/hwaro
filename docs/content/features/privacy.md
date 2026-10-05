+++
title = "Privacy Mode"
description = "Self-host third-party fonts, scripts and images at build time"
weight = 27
toc = true
+++

`[privacy]` downloads the third-party assets your pages load (web fonts,
CDN stylesheets and scripts, remote images) at build time and serves them
from your own site. The built site then makes no requests to other hosts.

The usual reason is the GDPR. Embedding Google Fonts from
`fonts.googleapis.com` sends every visitor's IP address to Google, and a
German court has ruled that this needs consent. Self-hosting the fonts
removes the request and with it the need for consent.

## Quick Start

```toml
[privacy]
enabled = true
```

With this, a Google Fonts tag in a template

```html
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter&display=swap">
```

is published as

```html
<link rel="stylesheet" href="/assets/external/3f2a9c01b7de-css2.css">
```

The local stylesheet points at local copies of the `.woff2` files it uses.

## Configuration

```toml
[privacy]
enabled = false                 # off by default
include = []                    # hosts to localize; empty = every external host
exclude = []                    # hosts never localized, e.g. ["www.youtube.com"]
output_dir = "assets/external"  # directory under the build output
cache_ttl = "7d"                # how long a download is reused without a request
on_error = "warn-and-keep"      # warn-and-keep | fail
```

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Turn privacy mode on. When it is off the output is unchanged. |
| `include` | `[]` | Hosts to localize, compared exactly (`fonts.googleapis.com`). Empty means every external host. |
| `exclude` | `[]` | Hosts that stay external. `exclude` wins over `include`. |
| `output_dir` | `"assets/external"` | Where the downloaded files are published. URLs include the `base_url` subpath. |
| `cache_ttl` | `"7d"` | Download cache lifetime, in the `[[data.remote]]` duration syntax (`"90s"`, `"12h"`, `"7d"`). |
| `on_error` | `"warn-and-keep"` | A download that fails with no cached copy: `warn-and-keep` warns and leaves the external URL, `fail` stops the build. |

## What Gets Localized

Hwaro rewrites these attributes in every page, section, pagination page,
taxonomy page and the 404 page:

- `<link href>` when `rel` is `stylesheet`, `preload` or `modulepreload`
- `<script src>`
- `<img src>`, `<img srcset>`, `<source src>`, `<source srcset>`
- `<video src>`, `<video poster>`, `<audio src>`

Only absolute `http(s)://` and protocol-relative `//` URLs on another host
are touched. Relative URLs, `data:` URLs and URLs on your `base_url` host
are left alone. HTML comments and the bodies of inline `<script>` and
`<style>` elements are not rewritten.

A downloaded stylesheet is rewritten too: its `@import` and `url(...)`
references are resolved against the stylesheet's own URL and localized,
nested up to four levels deep. Those references are followed whatever
`include` says (the stylesheet needs them), but `exclude` still applies.
A reference that stays remote is written back as an absolute URL.

Published files are named `<hash>-<name>.<ext>`, where the hash is the first
12 hex characters of the SHA-256 of the bytes. Identical files are stored
once, and a changed upstream file gets a new name, so browsers never keep a
stale copy.

### User-Agent

Downloads send a desktop browser `User-Agent`. Google Fonts chooses the font
format from it, and an unknown client gets TrueType instead of the much
smaller woff2. No cookies or credentials are ever sent.

## Cache and Offline Builds

Downloads are kept in `.hwaro/external/` next to `config.toml`, with an
`index.json` that records each URL's file, fetch time, Content-Type and
SHA-256. The directory sits outside the build cache and outside everything
`hwaro serve` watches, so writing it never triggers a rebuild.

- A download younger than `cache_ttl` is used without a request. A warm
  build works fully offline.
- An older one is fetched again. If that fails, the old copy is used and
  Hwaro prints a warning.
- With no copy at all, `on_error` decides.

`hwaro serve` uses the same cache, so rebuilds do not hit the network.
Commit `.hwaro/external/` (or cache it in CI) if your builds must never
depend on the third-party hosts being up.

The rewrite happens when a page is written, after `--minify`, so a
`--cache` build that skips a page keeps its already-rewritten HTML and the
files it uses.

## Interactions

- **Subresource Integrity.** A rewritten `<link>` or `<script>` keeps its
  `integrity` attribute when the hash matches the bytes Hwaro serves.
  Otherwise Hwaro drops `integrity` and `crossorigin` and warns once per
  URL. With [`[assets] sri = true`](/features/asset-pipeline/#subresource-integrity), Hwaro
  writes its own `integrity` for every localized stylesheet and script.
- **PWA.** External URLs in `[pwa] precache_urls` are replaced by their
  local copies.
- **AMP.** AMP pages are built from the rewritten HTML. AMP allows external
  stylesheets only from font providers, so a localized font stylesheet is
  removed from the AMP mirror, and AMP pages still load the AMP runtime
  from `cdn.ampproject.org`.

## Limitations

- Inline `style="…url(…)"` attributes, `<style>` blocks and other
  attributes (such as `<link rel="icon">`) are not rewritten.
- `srcset` is split on commas, so a candidate URL that itself contains a
  comma is not recognised.
- `include` and `exclude` match whole host names; subdomains need their own
  entry.
- Raw `.html` files copied from `content/` are published as they are.

## See Also

- [Remote Data Sources](/features/remote-data/) uses the same HTTP client and
  cache conventions
- [Asset Pipeline](/features/asset-pipeline/) for Subresource Integrity
- [Configuration](/start/config/)
