+++
title = "export"
description = "Export content to other platforms"
weight = 10
+++

Export hwaro content to other static site generator formats. This is the reverse of `hwaro tool import`.

Source files can use TOML (`+++`), YAML (`---`), or JSON (`{...}`) front matter.
All three formats use the same field mappings and draft filtering. Invalid JSON
front matter is reported as an export error instead of being copied into the body.

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

`files` lists every destination written, content assets included,
while the counts cover content documents only.

## Content Assets

Every non-Markdown file the build publishes from `content/` is exported to the
same relative path: page-bundle and section files (filtered by
`[content.files]` when it is configured), `[content.files]` matches anywhere
in the tree, and raw `.json`/`.xml` files. Files of a draft that is not
exported are left out, as the build leaves them out. Hugo reads files beside an
`index.md`/`_index.md` as bundle resources. In a Jekyll export, a post bundle
flattened into `_posts/` or `_drafts/` has no directory to keep its files in,
so they are named in a warning instead.

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
| aliases | aliases (a relative alias gains a leading `/`; absolute, `//host` and `..` aliases, which the build skips, are dropped) |
| image | images (array) |
| expires | expiryDate |
| weight | weight |
| path | url (`/<path>/`) |
| in_sitemap = false | sitemap = { disable = true } |
| [taxonomies] table | flattened to top-level `tags` / `categories` / … |

Every other front-matter key is passed through as a Hugo page param.

Output structure preserves the original directory layout under `export/content/`.
An `index.md` at the site root, or one with other pages below it, is written
as `_index.md`: Hugo reads `index.md` as a leaf bundle, which turns every page
beneath it into a bundle resource. Leaf bundles (`posts/my-post/index.md`)
keep their name.

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
| path | permalink (`/<path>/`) |
| aliases | redirect_from (jekyll-redirect-from; aliases the build skips are dropped) |
| updated | last_modified_at |
| in_sitemap = false | sitemap: false (jekyll-sitemap) |
| [taxonomies] table | flattened to top-level `tags` / `categories` / … |

Output conventions:
- Regular posts go to `_posts/` with `YYYY-MM-DD-slug.md` filename
- A post moved into `_posts/` gets `permalink: /<section>/<name>/` (its hwaro address) unless it already has a `path` or `permalink`, so rewritten `@/` links and inbound URLs keep working instead of moving to Jekyll's `/YYYY/MM/DD/name.html`
- Draft posts go to `_drafts/` without date prefix
- `redirect_from` only redirects when the [jekyll-redirect-from](https://github.com/jekyll/jekyll-redirect-from) plugin is enabled under `plugins:` in the Jekyll `_config.yml` (it is allow-listed, not on by default, on GitHub Pages)
- Section index files (`_index.md`, and translations such as `_index.ko.md`) become `index.md` (`index.ko.md`) pages
- Frontmatter is converted from TOML, YAML, or JSON to YAML (`---`)
- A `[taxonomies]` table is hoisted to top-level keys, since neither Hugo nor
  Jekyll reads taxonomy membership from a nested table. An explicit top-level
  key of the same name wins, matching how the build resolves the two

## Internal Links

Internal links using the `@/` prefix are automatically converted to absolute paths:

```markdown
<!-- Hwaro -->
[About](@/about/_index.md)

<!-- Exported -->
[About](/about/)
```

A section `_index.md` and a page-bundle `index.md` both map to their directory
URL. Links shown inside code blocks or inline code spans are left exactly as
written, since the build does not resolve them there either.

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
