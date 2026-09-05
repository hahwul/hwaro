+++
title = "check-links"
description = "Check for dead links in content files"
weight = 3
+++

Check for broken external and internal links in your content files.

```bash
hwaro tool check-links

# Output result as JSON
hwaro tool check-links --json

# Custom timeout and concurrency
hwaro tool check-links --timeout 30 --concurrency 4

# Check only external or internal links
hwaro tool check-links --external-only
hwaro tool check-links --internal-only

# Silence a known-flaky host, and accept bot-blocking status codes
hwaro tool check-links --ignore-url twitter.com --allow-status 403,429
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Content directory (default: `content`) |
| --timeout SECONDS | HTTP request timeout in seconds (default: 10) |
| --concurrency N | Max concurrent requests (default: 8) |
| --external-only | Check external links only |
| --internal-only | Check internal links only |
| --ignore-url PATTERN | Skip links whose URL matches PATTERN (repeatable) |
| --allow-status CODES | Treat these HTTP status codes as healthy (comma-separated) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

`--ignore-url` matches the URL as written in the source, as a
case-insensitive substring. `--ignore-url twitter.com` skips every link
containing `twitter.com` (or `Twitter.com`), and `*` matches any run of
characters (`--ignore-url 'https://example.com/*'`). The flag can be passed
multiple times; matching links are never contacted at all, the scan line
reports how many were ignored, and the JSON payload carries the same number
as `ignored_count`, so a machine consumer can tell "all healthy" from "an
over-broad pattern checked nothing".

`--allow-status` is for hosts that answer link checkers with `403`/`429`
while serving browsers fine: a listed status counts as healthy instead of
failing CI.

## How It Works

1. Scans all Markdown files in the `content/` directory
2. Finds external URLs (http/https links) and internal links (relative/absolute paths)
3. Sends concurrent HEAD requests to external URLs (falling back to GET when a
   host rejects HEAD with 405/403/501, following up to 5 redirects)
4. Verifies internal link targets exist on disk (checks `.md`, `_index.md`, `index.md`)
5. Accepts routes the build generates rather than reads from disk
6. Accepts pipeline-emitted assets found in the last build's output (see
   [Build output as evidence](#build-output-as-evidence))
7. Reports broken or unreachable links

External links that resolve to private or internal addresses (localhost,
RFC 1918 ranges, `.local`/`.internal` hosts) are never contacted. They are
reported as skipped instead, both in the human output and under
`skipped_external` in the JSON payload.

### Generated routes

Some URLs have no source file at all, because the build writes them. Those are
resolved from `config.toml`, so `check-links` can run **before** the first
build (the order a lint-then-build CI pipeline uses):

- `/sitemap.xml`, `/robots.txt`, `/llms.txt`, the search index, and `404.html`,
  each honouring its configured `filename`
- Feeds (`/rss.xml`, `/atom.xml`), including the per-language copies
  (`/ko/rss.xml`) and the per-section ones (`/posts/rss.xml`). A section feed
  only counts when the section's `_index.md` sets `generate_feeds = true`,
  since that is what makes the build write it
- Taxonomy listing and term pages (`/tags/`, `/categories/rust/`)
- Paginated listings (`/posts/page/2/`), only for a section that actually
  declares `paginate_by`, so a `/page/N/` link under a non-paginated section
  is still reported

## Link Types

| Type | Description |
|------|-------------|
| External | `http://` and `https://` links — checked via HTTP HEAD |
| Internal | Relative and absolute path links — checked on filesystem |
| Images | `![alt](path)` image references — checked on filesystem |

## Example Output

```
hwaro: check-links content
scan: 30 external, 20 internal

    [err] content/blog/post.md
      -> https://old-site.com/page  404
    [err] content/blog/post.md
      -> ../missing-page  Internal link target not found
    [err] content/about.md
      -> /images/photo.png  Image not found
checked: 50 links, 3 dead
```

In a color terminal each dead link renders as a `✗ file` item with a `→ url
status` detail line under an `hwaro check-links` heading, closed by a `✦ checked`
outcome (`checked: 50 links · all healthy` when everything resolves). The
command exits non-zero when dead links are found, so it can gate CI.

## JSON Output

```json
{
  "dead_internal": [
    {
      "link": {
        "file": "content/about.md",
        "url": "/images/photo.png",
        "kind": "image"
      },
      "status": -1,
      "error": "Image not found"
    }
  ],
  "dead_external": [
    {
      "link": {
        "file": "content/blog/post.md",
        "url": "https://old-site.com/page",
        "kind": "external"
      },
      "status": 404,
      "error": null
    }
  ],
  "skipped_external": [
    {
      "link": {
        "file": "content/notes/intranet.md",
        "url": "http://wiki.internal/page",
        "kind": "external"
      },
      "status": -1,
      "error": "Skipped: private/internal address"
    }
  ],
  "ignored_count": 0,
  "output_hint": null
}
```

`output_hint` is `null` unless the build output changed how the result should
be read (see below). The human report prints the same sentence; `--json`
carries it so a CI run that never sees the terminal output still gets it.

## Build Output as Evidence

Some links point at files no source explains: a compiled stylesheet, a
resized image variant, anything published through `[content.files]` or the
asset pipeline. `check-links` accepts those when it finds them in the last
build's `[build] output_dir` (`public/` by default), the only evidence
available to a command that runs outside the build.

That tree has to come from `hwaro build`. Since Hwaro 0.19, `hwaro serve`
builds into `.hwaro/serve/` and leaves `output_dir` alone, so a serve-only
workflow has nothing there. `check-links` now says so instead of reporting a
pile of dead links with no explanation:

```
checked: 4 links, 1 dead
  [info] public/ holds no build output — run `hwaro build` first; check-links
         validates build output, not `hwaro serve` output (.hwaro/serve/)
```

- **Absent or empty** — the note is printed alongside the dead links it
  explains.
- **`hwaro serve` output** (a leftover `.hwaro-dev` marker) — never used as
  evidence, the same rule `hwaro deploy` applies. `hwaro build` clears the
  marker.
- **Older than your newest source file** — noted under an otherwise healthy
  report, because a page you deleted still has its `index.html` standing in
  that tree and its links still resolve against it.

Run `hwaro build` before `check-links` in CI to check against real output;
source-only routes (`/about/`, `/tags/`, feeds, the sitemap) never need it.
