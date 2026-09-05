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
| --force | Overwrite existing files instead of skipping |
| --dry-run | Preview every destination without writing anything |
| -v, --verbose | Show detailed output |
| -j, --json | Output a per-file manifest as JSON |
| -h, --help | Show help |

`--dry-run` resolves every destination, collision renames and skip decisions
included, and reports the counts and manifest without touching disk, so you
can inspect exactly what a large import will do before running it for real.

## JSON Output

```json
{
  "success": true,
  "dry_run": false,
  "imported_count": 2,
  "skipped_count": 1,
  "error_count": 0,
  "files": [
    { "path": "content/posts/hello.md", "action": "imported" },
    { "path": "content/posts/second.md", "action": "imported" },
    { "path": "content/posts/existing.md", "action": "skipped" }
  ]
}
```

`action` is `imported`, `skipped` (destination already exists and `--force`
was not passed), or `overwritten` (`--force` replaced an existing file).
`files` lists every destination the run resolved, page-bundle assets
included, while the counts cover content documents only; sources skipped
before a destination was resolved (drafts without `--drafts`, unsafe slugs)
appear in the counts but have no row.

## Behavior

- Front matter is converted to hwaro's default TOML format (`+++`). Hwaro also supports YAML front matter (`---`): run `hwaro tool convert to-yaml` afterwards, or set `[content.new].front_matter_format = "yaml"` in `config.toml` to change what `hwaro new` scaffolds from then on. Note that `front_matter_format` only applies to the built-in template. An archetype supplies its own front matter verbatim, and every scaffold ships `archetypes/default.md`, so delete it (or the matching archetype) if you want the config setting to take effect. See [Archetypes](/writing/archetypes/).
- HTML content (e.g. WordPress) is converted to Markdown.
- Existing files at the destination path are **skipped**, not overwritten. Remove or rename them first if you want to re-import, or pass `--force`.
- When two source files resolve to the **same** destination (a duplicate slug, two same-titled notes, a stripped `YYYY-MM-DD-` date prefix, two collection subfolders flattened into one section), the second and later ones are written alongside the first as `slug-1.md`, `slug-2.md`, … instead of one silently overwriting the other. The number of renamed destinations is reported once at the end of the run rather than one line per file.
- `--force` means "overwrite files that pre-dated this import". It never lets one imported file clobber another that the *same run* just wrote; those still get the `-1` / `-2` suffix above. Re-running an import is therefore idempotent: every source resolves to the destination it picked the first time and is skipped (or overwritten with `--force`), instead of accumulating `-1` copies on each run.
- Only known post types are imported (e.g. WordPress `post` and `page`).

## Example Output

```
hwaro: import jekyll
source: ./old-blog
output: content
imported: 42 files, 3 skipped
```

An `errors` count is appended only when errors occurred, and a warning reminds
you about `--force` when files were skipped. In a color terminal the same
report renders as an `hwaro import` heading with aligned rows and a `✦ imported`
outcome line.

## See Also

- [`hwaro tool export`](/start/tools/export/) — Export hwaro content to other formats
- [Writing Pages](/writing/pages/) — Front matter reference
