+++
title = "Incremental Build"
description = "Only rebuild changed files for faster builds on large sites"
weight = 10
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

Beyond per-file checksums, Hwaro tracks global dependencies:

- **Template checksum** — a combined hash of all template files
- **Config checksum** — a hash of `config.toml`

If either changes between builds, **all cache entries are invalidated** and every page is rebuilt. This ensures that template or config changes are always reflected across the entire site.

```
Build N:   templates hash = abc123, config hash = def456
Build N+1: templates hash = abc123, config hash = def456  → incremental (only changed content rebuilt)
Build N+2: templates hash = xyz789, config hash = def456  → full invalidation (template changed)
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
| Template files only | Re-render all pages with existing content (skip parsing) |
| Config file | Full rebuild |
| Static files only | Copy only changed files |

## Cache File

The cache is stored in `.hwaro_cache.json` at the project root. This file contains:

- **Metadata** — template and config checksums from the last build
- **Entries** — per-file records with path, mtime, content hash, and output path

Add `.hwaro_cache.json` to your `.gitignore`:

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
hwaro build --cache --minify --parallel
```

## See Also

- [CLI Reference](/start/cli/) — Full list of build flags
- [Streaming Build](/features/streaming-build/) — Reduce memory usage for large sites
- [Build Hooks](/features/build-hooks/) — Run custom commands before/after builds
