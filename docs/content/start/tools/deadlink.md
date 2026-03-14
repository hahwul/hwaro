+++
title = "deadlink"
description = "Check for dead links in content files"
weight = 3
+++

Check for broken external and internal links in your content files.

```bash
hwaro tool deadlink

# Output result as JSON
hwaro tool deadlink --json
```

## Options

| Flag | Description |
|------|-------------|
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
Starting dead link check in 'content'...
----------------------------------------
✘ Found 3 dead links (out of 50 total):
[DEAD] content/blog/post.md
  └─ URL: https://old-site.com/page
  └─ Status: 404
[DEAD] content/blog/post.md
  └─ URL: ../missing-page (internal)
  └─ Internal link target not found
[DEAD] content/about.md
  └─ URL: /images/photo.png (internal)
  └─ Image not found
----------------------------------------
```

## JSON Output

```json
{
  "dead_links": [
    {
      "link": {
        "file": "content/blog/post.md",
        "url": "https://old-site.com/page",
        "kind": "external"
      },
      "status": 404,
      "error": null
    },
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
  "total_links": 50,
  "external_links": 30,
  "internal_links": 20,
  "dead_link_count": 2
}
```
