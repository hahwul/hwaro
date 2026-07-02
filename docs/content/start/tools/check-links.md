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
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Content directory (default: `content`) |
| --timeout SECONDS | HTTP request timeout in seconds (default: 10) |
| --concurrency N | Max concurrent requests (default: 8) |
| --external-only | Check external links only |
| --internal-only | Check internal links only |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## How It Works

1. Scans all Markdown files in the `content/` directory
2. Finds external URLs (http/https links) and internal links (relative/absolute paths)
3. Sends concurrent HEAD requests to external URLs
4. Verifies internal link targets exist on disk (checks `.md`, `_index.md`, `index.md`)
5. Reports broken or unreachable links

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
status` detail line under an `● check-links` heading, closed by a `▴ checked`
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
  ]
}
```
