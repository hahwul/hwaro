+++
title = "unused-assets"
description = "Find unreferenced static files"
weight = 9
+++

Scan static files and co-located content assets, then report files not referenced by any content or template.

```bash
# Find unused assets
hwaro tool unused-assets

# Specify directories
hwaro tool unused-assets -c posts -s assets

# Delete unused files (with confirmation prompt)
hwaro tool unused-assets --delete

# Output as JSON
hwaro tool unused-assets --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory (default: content) |
| -s, --static-dir DIR | Static files directory (default: static) |
| --delete | Delete unused files (prompts for confirmation) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## What It Scans

**Asset sources:**
- Files in the `static/` directory (images, CSS, JS, fonts, media, etc.)
- Co-located assets in content directories (non-markdown files alongside `.md` files)

**Reference sources:**
- All content files (`.md`, `.markdown`)
- All template files (`.html`, `.css`, `.js`)

**Supported asset extensions:**
Images (png, jpg, jpeg, gif, svg, webp, avif, ico, bmp, tiff), stylesheets (css), scripts (js), fonts (woff, woff2, ttf, eot, otf), media (mp4, webm, ogg, mp3, wav), documents (pdf, zip).

## Example Output

```
Scanning for unused assets...

  Total assets:      24
  Referenced:         20
  Unused:             4

  Unused files:
    static/old-logo.png
    static/unused-banner.jpg
    content/blog/my-post/draft-image.png
    static/deprecated.css

Note: Dynamic references (e.g., template variables) may cause false positives.
```

## JSON Output

```json
{
  "unused_files": [
    "static/old-logo.png",
    "static/unused-banner.jpg"
  ],
  "total_assets": 24,
  "referenced_count": 22,
  "unused_count": 2
}
```

## Limitations

- Asset filenames referenced dynamically via template variables (e.g., `{{ page.image }}`) may not be detected, resulting in false positives.
- The detection is based on filename matching — if two files in different directories share the same name, both may be considered referenced even if only one is actually used.
