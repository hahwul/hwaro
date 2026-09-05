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
| -c, --content-dir DIR | Content directory (default: content) |
| -d, --drafts | Include draft content |
| --dry-run | Preview every destination without writing anything |
| -v, --verbose | Show detailed output |
| -j, --json | Output a per-file manifest as JSON |
| -h, --help | Show help |

Re-exporting into the same directory **replaces** the previous output. That
is the normal refresh workflow. When a run replaces pre-existing files, the
summary warns with the count, and the JSON manifest marks those rows
`overwritten` (fresh destinations are `exported`). Use `--dry-run` to see the
full manifest before writing.

## JSON Output

```json
{
  "success": true,
  "dry_run": false,
  "exported_count": 2,
  "skipped_count": 0,
  "error_count": 0,
  "files": [
    { "path": "export/_posts/2024-01-01-hello.md", "action": "exported" },
    { "path": "export/about.md", "action": "overwritten" }
  ]
}
```

`files` lists every destination written, page-bundle assets included,
while the counts cover content documents only.

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
| [taxonomies] table | flattened to top-level `tags` / `categories` / … |

Every other front-matter key is passed through as a Hugo page param.

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
| template | layout |
| [taxonomies] table | flattened to top-level `tags` / `categories` / … |

Output conventions:
- Regular posts go to `_posts/` with `YYYY-MM-DD-slug.md` filename
- Draft posts go to `_drafts/` without date prefix
- Section index files (`_index.md`) become `index.md` pages
- Frontmatter is converted from TOML (`+++`) to YAML (`---`)
- A `[taxonomies]` table is hoisted to top-level keys, since neither Hugo nor
  Jekyll reads taxonomy membership from a nested table. An explicit top-level
  key of the same name wins, matching how the build resolves the two

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
hwaro: export hugo
source: content
output: export
exported: 38 files, 4 skipped
```

An `errors` count is appended only when errors occurred. In a color terminal
the same report renders as an `hwaro export` heading with aligned rows and a
`✦ exported` outcome line.
