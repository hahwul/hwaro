+++
title = "Content Files"
description = "Publish non-Markdown files from the content directory"
weight = 7
toc = true
+++

Non-Markdown files placed in the `content/` directory can be automatically published to the output directory. This is useful for images, PDFs, and other assets that live alongside your content.

## Configuration

Enable content file publishing in `config.toml`:

```toml
[content.files]
allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp", "pdf"]
disallow_extensions = ["psd", "ai"]
disallow_paths = ["drafts/**", "**/_*"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| allow_extensions | array | [] | File extensions to publish |
| disallow_extensions | array | [] | File extensions to exclude |
| disallow_paths | array | [] | Glob patterns for paths to exclude |

## How It Works

When content file publishing is enabled, Hwaro copies non-Markdown files from `content/` to the output directory, preserving their directory structure.

### Example

```
content/
├── about/
│   ├── index.md          → /about/index.html
│   ├── team-photo.jpg    → /about/team-photo.jpg
│   └── resume.pdf        → /about/resume.pdf
├── blog/
│   ├── _index.md         → /blog/index.html
│   └── my-post/
│       ├── index.md      → /blog/my-post/index.html
│       ├── diagram.svg   → /blog/my-post/diagram.svg
│       └── screenshot.png → /blog/my-post/screenshot.png
└── index.md              → /index.html
```

Files are copied directly to the matching output path. The `content/` prefix is stripped automatically.

## Extension Matching

### Allow List

Only files with extensions in `allow_extensions` are published:

```toml
[content.files]
allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp"]
```

Extensions are normalized — both `"jpg"` and `".jpg"` are accepted.

### Deny List

Exclude specific extensions with `disallow_extensions`:

```toml
[content.files]
allow_extensions = ["jpg", "png", "gif", "svg"]
disallow_extensions = ["psd", "ai", "sketch"]
```

The deny list takes priority over the allow list.

### Path Exclusion

Exclude files by path pattern using glob syntax:

```toml
[content.files]
disallow_paths = ["drafts/**", "**/_*", "private/**"]
```

| Pattern | Matches |
|---------|---------|
| `drafts/**` | All files under `content/drafts/` |
| `**/_*` | Any file starting with underscore |
| `private/**` | All files under `content/private/` |

Paths are matched relative to the `content/` directory.

## Referencing Content Files

### In Markdown

Reference colocated files with relative paths:

```markdown
![Team Photo](team-photo.jpg)

[Download Resume](resume.pdf)

![Diagram](diagram.svg)
```

### In Templates

For page bundles, colocated assets are also available via `page.assets`:

```jinja
{% for asset in page.assets %}
  {% if asset is matching("[.](jpg|png|gif)$") %}
    <img src="{{ get_url(path=asset) }}" alt="Asset">
  {% endif %}
{% endfor %}
```

## Content Files vs Static Files

| Feature | Content Files (`content/`) | Static Files (`static/`) |
|---------|---------------------------|--------------------------|
| Colocated with content | ✅ Yes | ❌ No |
| Requires configuration | ✅ Yes | ❌ No (always copied) |
| Extension filtering | ✅ Yes | ❌ No |
| Path filtering | ✅ Yes | ❌ No |
| Best for | Per-page assets | Site-wide assets |

Use **content files** for assets that belong to specific pages (screenshots, diagrams, attachments). Use **static files** for site-wide assets (CSS, JS, logos, favicons).

## Tips

- **Page Bundles**: For the best organization, use [page bundles](/writing/pages/#asset-colocation) — place `index.md` and its assets in a directory together.
- **Image formats**: Include common web image formats: `["jpg", "jpeg", "png", "gif", "svg", "webp"]`.
- **Security**: Use `disallow_paths` to prevent publishing source files or drafts.
- **Keep it lean**: Only allow extensions you actually need. This prevents accidentally publishing large source files.

## See Also

- [Image Processing](/features/image-processing/) — Automatic image resizing
- [Pages — Asset Colocation](/writing/pages/#asset-colocation) — Page bundles
- [Sections — Asset Colocation](/writing/sections/#asset-colocation) — Section assets
- [Configuration](/start/config/) — Full configuration reference