+++
title = "export"
description = "Export content to other platforms"
weight = 10
+++

Export hwaro content to other static site generator formats. This is the reverse of `hwaro tool import`.

```bash
# Export to Hugo
hwaro tool export hugo

# Export to Jekyll
hwaro tool export jekyll

# Specify output and content directories
hwaro tool export hugo -o ~/hugo-site -c posts

# Include draft content
hwaro tool export jekyll --drafts

# Verbose output
hwaro tool export hugo --verbose
```

## Supported Targets

| Target | Description |
|--------|-------------|
| hugo | Export to Hugo format (TOML frontmatter, content/ structure) |
| jekyll | Export to Jekyll format (YAML frontmatter, _posts/ naming convention) |

## Options

| Flag | Description |
|------|-------------|
| -o, --output DIR | Output directory (default: export) |
| -c, --content DIR | Content directory (default: content) |
| -d, --drafts | Include draft content |
| -v, --verbose | Show detailed output |
| -h, --help | Show help |

## Field Mappings

### Hugo

| Hwaro | Hugo |
|-------|------|
| title | title |
| date | date |
| description | description |
| draft | draft |
| updated | lastmod |
| tags | tags |
| series | series |
| aliases | aliases |
| image | images (array) |
| expires | expiryDate |
| weight | weight |

Output structure preserves the original directory layout under `export/content/`.

### Jekyll

| Hwaro | Jekyll |
|-------|--------|
| title | title |
| date | date |
| description | description |
| draft = true | published: false |
| tags | tags |
| categories | categories |
| image | image |

Output conventions:
- Regular posts go to `_posts/` with `YYYY-MM-DD-slug.md` filename
- Draft posts go to `_drafts/` without date prefix
- Section index files (`_index.md`) become `index.md` pages
- Frontmatter is converted from TOML (`+++`) to YAML (`---`)

## Internal Links

Internal links using the `@/` prefix are automatically converted to absolute paths:

```markdown
<!-- Hwaro -->
[About](@/about/_index.md)

<!-- Exported -->
[About](/about)
```

## Example Output

```
Exporting to hugo: export
Content directory: content
✔ Export complete: 38 exported, 4 skipped, 0 errors
```
