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
- HTML content (e.g. WordPress) is converted to Markdown. Links, emphasis and code inside list items and table cells are kept, `[caption]` shortcodes become the image followed by its caption, and entity-encoded markup such as `&lt;script&gt;` stays visible text.
- WordPress's "Read more" tag and Hexo's `more` comment are kept as hwaro's excerpt marker, so a post's [summary](/writing/pages/) still ends where its author put it.
- Dates are read in the shapes the source generators accept: RFC 3339, `2024-01-15 10:30:00 +0900`, minute precision (`2024-01-15 10:30`), slash dates (`2024/01/15 10:30:00`, with or without an offset), and prose dates (`July 8, 2022`, or `Jul 08 2022` from Astro's blog template).
- Existing files at the destination path are **skipped**, not overwritten. Remove or rename them first if you want to re-import, or pass `--force`.
- When two source files resolve to the **same** destination (a duplicate slug, two same-titled notes, a stripped `YYYY-MM-DD-` date prefix, two collection subfolders flattened into one section), the second and later ones are written alongside the first as `slug-1.md`, `slug-2.md`, … instead of one silently overwriting the other. The number of renamed destinations is reported once at the end of the run rather than one line per file.
- `--force` means "overwrite files that pre-dated this import". It never lets one imported file clobber another that the *same run* just wrote; those still get the `-1` / `-2` suffix above. Re-running an import is therefore idempotent: every source resolves to the destination it picked the first time and is skipped (or overwritten with `--force`), instead of accumulating `-1` copies on each run.
- Only known post types are imported (e.g. WordPress `post` and `page`).
- A page keeps its published address. Hugo `url` and a literal Jekyll or Eleventy `permalink` (not a `:placeholder` or `{{ }}` pattern) become `path`; Eleventy `permalink: false` becomes `render = false`. A `.html` address becomes an extensionless `path` plus an alias at the old address, and a trailing `index.html` maps to its directory with no alias. A query or fragment is dropped. A URL naming another kind of file (`/feed.xml`) is left unmapped, with a warning. Jekyll `redirect_from` entries become `aliases`.
- Hugo: front matter keys are case-insensitive, as in Hugo (`Title`, `Draft` and `publishdate` all work). JSON front matter is read like TOML and YAML, and a leaf bundle with a `slug` is written as a bundle under the slugged directory (`posts/<slug>/index.md`). If that directory already holds another bundle, the page stays in its own directory, with a warning.
- Hugo: a page scheduled with a future `publishDate` takes it as its `date`, so it stays unpublished until then (a past `publishDate` keeps `date`). A page with no output (`headless = true`, or `build`/`_build` `render = "never"`) becomes `render = false`, and `sitemap.disable = true` becomes `in_sitemap = false`.
- Hexo: a post marked `published: false` is imported as a draft.
- Hugo: `layout` becomes `template`. hwaro keys Hugo has no meaning for (`toc`, `template`, `page_template`, `image`, `updated`, …) are kept as they are, and every other page param (top-level custom keys and the `[params]` table) goes to `[extra]`, where templates read it as `page.extra.<key>`. An `[extra]` table, as `tool export hugo` writes it, is merged into `[extra]` as well.
- Jekyll: `last_modified_at` becomes `updated`, `sitemap: false` becomes `in_sitemap = false`, and the `image: {path: …}` form becomes `image`. Every other front matter key (what Jekyll templates read as `page.<key>`) goes to `[extra]`.
- Obsidian: `%%comments%%` (inline or spanning lines) are removed, since Obsidian never shows them. `%%` inside code is kept.
- A note whose name or title has no letters or digits (an emoji-only Notion page, say) is written under a name derived from the original text rather than skipped. A source that cannot be given any filename is skipped with a warning that says so.
- A blank `title:` counts as no title: Obsidian falls back to the file name, Astro and Eleventy to a title derived from it, Notion to the page's first heading. An unquoted date title (`title: 2024-05-01`) is kept as written.
- Links between pages point at the file each target was actually written to, including the `-1` copy of a same-titled page (Notion page links, Obsidian `[[wikilinks]]`). Obsidian `[[Note\|alias]]` links, as required inside tables, resolve like `[[Note|alias]]`, and `#tags` or `[[links]]` inside HTML tags and math are left alone.
- Jekyll and Hexo: a post without a `title` gets one from its file name, and a date-prefixed file name is slugified like any other (`2024-01-01-Hello World.md` becomes `hello-world`).
- Hugo: a translation (`about.ko.md`, `index.ko.md`) keeps its language suffix when it has a `slug`, and a translated bundle follows the default-language bundle's directory. Assets beside `index.<lang>.md` and `_index.md` are copied too. Astro bundles that hold assets are written as bundles (`blog/<name>/index.md`) with their files.
- Notion: only emoji callouts (`> 💡 text`) are flattened; ordinary quotes, fenced code and inline code are left as written.
- WordPress: `<script>` and `<style>` are dropped with their contents, and `<iframe>`, `<video>` and `<audio>` embeds are kept as HTML with only their `src` (and numeric size).

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
