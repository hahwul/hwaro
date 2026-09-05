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

# Delete without the prompt (scripts/CI)
hwaro tool unused-assets --delete --force

# Output as JSON
hwaro tool unused-assets --json

# Delete in JSON mode (requires --force, since there is no prompt)
hwaro tool unused-assets --delete --force --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Content directory (default: content) |
| -s, --static-dir DIR | Static files directory (default: static) |
| -t, --templates-dir DIR | Templates directory scanned for references (default: templates) |
| --delete | Delete unused files (prompts for confirmation) |
| -f, --force | Skip the confirmation prompt when deleting (required for deletion under `--json`) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## What It Scans

**Asset sources:**
- Files in the `static/` directory (images, CSS, JS, fonts, media, etc.)
- Co-located assets in content directories (non-markdown files alongside `.md` files)

**Reference sources:**
- All content files (`.md`, `.markdown`)
- Template files (`.html`, `.j2`, `.jinja`, `.jinja2`, `.ecr`, plus `.css`, `.js`, `.xml`, `.json`, `.webmanifest`, `.svg`, `.txt`)
- Static sources that can reference other static files (`.css`, `.scss`, `.sass`, `.js`, `.json`, `.webmanifest`, `.xml`, `.svg`, `.txt`, `.html`, `.htm`)
- Data and translation files (`.yml`, `.yaml`, `.json`, `.toml` under `data/` and `i18n/`)
- `config.toml` values that name files

If your templates live outside `templates/`, point the scan at them with
`--templates-dir` — otherwise their asset references are invisible and the
assets they use are reported (and can be deleted) as unused. An explicitly
passed `--templates-dir` must exist (the path is resolved relative to the
current directory); the command refuses to run against a missing one rather
than silently scanning zero templates.

**Supported asset extensions:**
Images (png, jpg, jpeg, gif, svg, webp, avif, ico, bmp, tiff, tif), stylesheets (css), scripts (js), fonts (woff, woff2, ttf, eot, otf), media (mp4, webm, ogg, mp3, wav), documents (pdf, zip).

## Example Output

```
hwaro: unused-assets static
total: 24
referenced: 20
unused: 4
unused files:
    - static/old-logo.png
    - static/unused-banner.jpg
    - content/blog/my-post/draft-image.png
    - static/deprecated.css
    [info] dynamic references (e.g. template variables) may cause false positives
found: 4 unused assets
```

In a color terminal this renders as an `hwaro unused-assets` receipt with aligned
rows and a `✦ found` outcome line (`found: no unused assets` when everything is
referenced). With `--delete` the outcome becomes `deleted: N files` after
confirmation, or `cancelled: no files deleted`.

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
- The detection is based on filename matching. If two files in different directories share the same name, both may be considered referenced even if only one is actually used.
