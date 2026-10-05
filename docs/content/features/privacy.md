+++
title = "Privacy Mode"
description = "Self-host third-party fonts, scripts and images at build time"
weight = 27
toc = true
+++

`[privacy]` downloads the third-party assets your pages load (web fonts,
CDN stylesheets and scripts, remote images) at build time and serves them
from your own site, so visitors' browsers stop contacting those hosts for
them. It covers the tags listed under [What Gets Localized](#what-gets-localized);
anything else a page or script loads (see [Limitations](#limitations)) still
goes to its own host.

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
| `include` | `[]` | Hosts to localize, compared exactly (`fonts.googleapis.com`). Empty means every external host. A listed host is also trusted on the network (see [Network Safety](#network-safety)). |
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
A reference that stays remote is written back as an absolute URL. Strings
inside `image-set(...)` are handled like `url(...)`.

`<link rel="preconnect">` and `<link rel="dns-prefetch">` hints to a host
whose assets are now served locally are removed, since the browser would
still open a connection to it.

### File types

A file is published only under an extension that suits the tag that loads
it, taken from the response `Content-Type` (or, when that is generic, the URL
path): images for `<img>`, `<source>` and `poster`, audio and video for
`<video>` and `<audio>`, CSS for stylesheets, JavaScript for scripts, and
fonts, images (not SVG) and CSS for references inside a stylesheet. Anything else, such
as an `<img>` that answers with HTML, keeps its external URL with a warning.
HTML or XML is never published.

SVG is published only for `<img>`-like tags, with a warning: an SVG opened
directly on your site can run script. Add the host to `exclude` if you do not
trust it. An SVG referenced from a stylesheet (`background: url(icon.svg)`)
is never published and keeps loading from its own host.

### Hwaro's own tags

`[markdown] math = "mathjax"` loads MathJax from `cdn.jsdelivr.net`, and
MathJax loads its fonts and extensions relative to its own URL, so it stays
external. Mermaid (`[markdown] mermaid = true`) is loaded by an inline module
`import`, which privacy mode does not rewrite. KaTeX and highlight.js are
localized normally.

Published files are named `<hash>-<name>.<ext>`, where the hash is the first
12 hex characters of the SHA-256 of the bytes. Identical files are stored
once, and a changed upstream file gets a new name, so browsers never keep a
stale copy.

### User-Agent

Downloads send a desktop browser `User-Agent`. Google Fonts chooses the font
format from it, and an unknown client gets TrueType instead of the much
smaller woff2. No cookies or credentials are ever sent.

### Network Safety

The URLs privacy mode fetches are not all written by you: redirects and the
`url(...)` references inside a downloaded stylesheet come from the third
party. So every request, including every redirect hop, is checked first. A
host that resolves to a loopback, private (10/8, 172.16/12, 192.168/16,
fc00::/7, site-local fec0::/10), link-local (169.254/16, fe80::/10), CGNAT
(100.64/10), IETF-reserved (192.0.0.0/24), unspecified or multicast address
is refused, as is a NAT64 (64:ff9b::/96) or IPv4-mapped address that wraps
one of these. The refusal follows `on_error`. This keeps a third party from making the build read internal
services or cloud metadata and publish the response on your site. The
connection is pinned to the address that was checked.

A host listed in `include` skips this check, which is how an intranet CDN or
a local test server is allowed. `include` does both jobs at once: as soon as
it lists any host, only the listed hosts are localized. Behind split-horizon
DNS, where CDN names resolve to private addresses, list every host you need,
including the hosts a stylesheet loads from (Google Fonts CSS pulls from
`fonts.gstatic.com`).

A failed download is not retried by the same process for 10 minutes, so a
dead host slows down only one `hwaro serve` rebuild. Each file is capped at
20 MiB; a larger one (a long video, say) keeps its external URL with a
warning.

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
To keep builds independent of the third-party hosts, cache
`.hwaro/external/` in CI, or commit it. Hwaro writes a `.hwaro/.gitignore`
that ignores everything inside `.hwaro/`, so add it with
`git add -f .hwaro/external`. Old downloads are never deleted from this
directory; remove it to start over.

The rewrite happens when a page is written, after `--minify`, so a
`--cache` build that skips a page keeps its already-rewritten HTML and the
files it uses. A page that kept an external URL because its download failed
is not cached; the next `--cache` build renders it again and retries.

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

- Inline `style="…url(…)"` attributes, `<style>` blocks, inline module
  `import`s, import maps and other attributes (such as `<link rel="icon">`,
  `<link imagesrcset>` or `<track src>`) are not rewritten, so they still
  load from their own host.
- Scripts that load further files relative to their own URL (MathJax, ESM
  bundles with absolute `/npm/...` imports, pdf.js workers) break when moved;
  add their host to `exclude`.
- Tags inside HTML comments (including IE conditional comments) and tags
  with a `>` inside a quoted attribute value are left as they are, without a
  warning.
- `include` and `exclude` match whole host names; subdomains need their own
  entry.
- In the rare case of stylesheets that import each other in a cycle, or a
  chain deeper than four levels, which reference stays absolute depends on
  which page reaches the chain first.
- There is no limit on the total size or number of downloads per build.
- Raw `.html` files copied from `content/` are published as they are.

## See Also

- [Remote Data Sources](/features/remote-data/) uses the same HTTP client and
  cache conventions
- [Asset Pipeline](/features/asset-pipeline/) for Subresource Integrity
- [Configuration](/start/config/)
