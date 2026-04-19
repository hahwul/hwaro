+++
title = "import"
description = "Import content from various platforms"
weight = 11
+++

Import content from other static site generators or platforms into hwaro. This is the reverse of [`hwaro tool export`](/start/tools/export/).

```bash
# Import a WordPress WXR file
hwaro tool import wordpress path/to/export.xml

# Import a Jekyll site directory
hwaro tool import jekyll path/to/jekyll-site

# Import a Hugo site
hwaro tool import hugo path/to/hugo-site

# Import a Notion export
hwaro tool import notion path/to/notion-export

# Import an Obsidian vault
hwaro tool import obsidian path/to/vault

# Specify output directory and include drafts
hwaro tool import jekyll path/to/site -o content/blog --drafts

# Verbose output
hwaro tool import hugo path/to/site --verbose
```

## Supported Sources

| Source | Input | Notes |
|--------|-------|-------|
| wordpress | WXR XML file | Imports posts and pages from a WordPress export file |
| jekyll | Site directory | Reads `_posts/` and (with `--drafts`) `_drafts/` |
| hugo | Site directory | Reads `content/` preserving section layout |
| notion | Export directory | Recursively imports `.md` files from a Notion export |
| obsidian | Vault directory | Recursively imports notes (skips dot-prefixed folders) |
| hexo | Site directory | Reads `source/_posts/` and `source/_drafts/` |
| astro | Site directory | Reads `src/content/` collections |
| eleventy | Site directory | Reads Markdown files with Eleventy front matter |

## Options

| Flag | Description |
|------|-------------|
| -o, --output DIR | Output content directory (default: `content`) |
| -d, --drafts | Include draft content |
| -v, --verbose | Show detailed output |
| -h, --help | Show help |

## Behavior

- Front matter is converted to hwaro's TOML format (`+++`).
- HTML content (e.g. WordPress) is converted to Markdown.
- Existing files at the destination path are **skipped**, not overwritten. Remove or rename them first if you want to re-import.
- Only known post types are imported (e.g. WordPress `post` and `page`).

## Example Output

```
Importing from jekyll: ./old-blog
Output directory: content
✔ Import complete: 42 imported, 3 skipped, 0 errors
```

## See Also

- [`hwaro tool export`](/start/tools/export/) — Export hwaro content to other formats
- [Writing Pages](/writing/pages/) — Front matter reference
