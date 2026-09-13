+++
title = "Incremental Build"
description = "Only rebuild changed files for faster builds on large sites"
weight = 13
toc = true
+++

Incremental build tracks file checksums and dependency changes to skip unchanged pages, significantly reducing rebuild times for large sites.

```bash
hwaro build --cache
```

## When to Use

Incremental builds are most effective when:

- Your site has many pages but you typically change only a few at a time
- You want faster edit-build-preview cycles
- You're working on content rather than templates or config

## Usage

### Enable caching

```bash
hwaro build --cache
```

On the first run, Hwaro builds every page and saves checksums to `.hwaro_cache.json`. On subsequent builds, only changed files are re-processed.

### Force a full rebuild

```bash
hwaro build --cache --full
```

The `--full` flag clears the cache and rebuilds every page from scratch. The new cache is saved afterward, so the next build without `--full` will be incremental again.

## How It Works

### Change detection

Each cached entry tracks:

- **File modification time (mtime)** — fast first check
- **Content checksum (MD5)** — verifies actual change when mtime differs, catching false positives from file touches

When mtime hasn't changed, the file is considered unchanged without reading its content. When mtime differs, Hwaro computes and compares the content hash to confirm the change is real.

### Dependency invalidation

Beyond per-file checksums, Hwaro tracks what each page actually depends on:

- **Template closure** — the page's template plus everything it transitively
  `extends`, `include`s, or `import`s, plus any shortcode templates the page
  content invokes. Each page's cache entry stores a fingerprint of this
  closure, so editing `partials/footer.html` only rebuilds the pages whose
  template chain renders that partial.
- **Cascade fingerprint** — the merged section `[cascade]` values applied to
  the page, so editing a parent `_index.md` cascade rebuilds its descendants.
- **Config checksum** — a hash of the effective merged config. A config
  change invalidates **all** entries.
- **Render hooks** — a fingerprint of every configured `templates/hooks/render-*`
  template (see [Render Hooks](/templates/render-hooks/)) is folded into every
  page's template closure. Since a hook isn't reached via a page's
  `{% include %}`/`{% extends %}` graph, editing one re-renders **every**
  page rather than a narrowed set.

Template dependency tracking requires every template reference to be a string
literal. If any template uses a dynamic reference (`{% include some_var %}`),
Hwaro falls back to whole-site invalidation: any template change rebuilds
every page. You can also opt out explicitly:

```toml
[build]
template_deps = false  # any template change rebuilds every page
```

### What gets skipped

When a page is unchanged and its dependencies haven't changed:

- Content parsing is still performed (to build navigation, taxonomies, etc.)
- **Rendering and writing are skipped** — the existing output file is reused
- SEO files (sitemap, feeds, etc.) are always regenerated

### Serve mode

The development server (`hwaro serve`) uses a more targeted incremental strategy:

| Change Type | Strategy |
|-------------|----------|
| Content files only | Re-parse and re-render only affected pages + neighbors |
| Template files only | Re-render only pages whose template closure includes an edited template (all pages when tracking is off, the graph has dynamic references, or the edited file is under `templates/hooks/`) |
| Config file | Full rebuild |
| Static files only | Copy only changed files |

### Removed pages

A cold build starts from an empty output directory, so a page you delete is
gone from `public/` on the next build. `--cache` keeps the directory — that is
the point — so removals are handled from the cache instead: every entry records
the file the page wrote, and on each build the entries no live page claims have
their output deleted.

That covers a page that was deleted, renamed, moved to a new URL (`slug`,
`path`, a permalink rule), turned into a draft, passed its `expires` date, or
set `render = false`.

Everything a removed page brought with it goes too: its `aliases` redirect
stubs, its AMP mirror, its auto-generated OG image, the taxonomy term page of
a tag nobody uses any more (with that term's feed), and the pagination page a
section no longer fills. Turning a whole feature off — `[amp] enabled = false`
— removes what it used to publish on the next build for the same reason.

Files that have a source but no cache entry are covered the same way, by
recording what each build publishes and deleting what the next one no longer
does: `static/` copies, `[content.files]` and raw (`.json`/`.xml`) copies,
page-bundle assets, and the fingerprinted asset bundles — so editing a
stylesheet replaces `main.<hash>.css` instead of leaving every past revision
in `public/assets/`.

A `--cache` build's output is therefore byte-identical to a clean build's, and
`hwaro build --full` is not needed to clear anything. (`--full` only clears the
cache, so it does nothing at all without `--cache`; a plain `hwaro build`
already rebuilds everything.)

## Cache File

The cache is stored in `.hwaro_cache.json` at the project root. This file contains:

- **Metadata** — template and config checksums from the last build
- **Entries** — per-file records with path, mtime, content hash, and output path
  (the output path is also what identifies a removed page's stale file)

Add `.hwaro_cache.json` to your `.gitignore` (the one `hwaro init` scaffolds already lists it):

```gitignore
.hwaro_cache.json
```

## Flag Reference

| Flag | Description |
|------|-------------|
| `--cache` | Enable incremental build caching |
| `--full` | Force a complete rebuild (clears and repopulates the cache) |

## Examples

```bash
# First build — creates cache
hwaro build --cache

# Edit a few files, then rebuild — only changed pages are re-rendered
hwaro build --cache

# Something seems off — force a clean rebuild
hwaro build --cache --full

# Combine with other flags
hwaro build --cache --minify
```

## See Also

- [CLI Reference](/start/cli/) — Full list of build flags
- [Streaming Build](/features/streaming-build/) — Reduce memory usage for large sites
- [Build Hooks](/features/build-hooks/) — Run custom commands before/after builds
