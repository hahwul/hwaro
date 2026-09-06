+++
title = "Streaming Build"
description = "Reduce memory usage by processing pages in batches"
weight = 14
toc = true
+++

Streaming build reduces memory usage for large sites by processing pages in batches during the Render phase. Instead of holding all rendered HTML in memory at once, each batch is rendered, written to disk, and then released before the next batch begins.

```bash
hwaro build --stream
```

## When to Use

For most sites, the default build mode works well. Streaming build is useful when:

- Your site has thousands of pages
- The build process consumes too much memory
- You're building in a memory-constrained environment (CI, containers, small VMs)

## Usage

### `--stream` flag

Enable streaming with a default batch size of 500 pages:

```bash
hwaro build --stream
```

### `--memory-limit` flag

Set a memory limit and let Hwaro calculate the optimal batch size automatically:

```bash
hwaro build --memory-limit 512M
hwaro build --memory-limit 2G
```

Accepts `G` (gigabytes), `M` (megabytes), and `K` (kilobytes) suffixes. The batch size is calculated using a heuristic of ~50KB per page.

### Environment variable

Set `HWARO_MEMORYLIMIT` as a fallback when the CLI flag is not provided:

```bash
export HWARO_MEMORYLIMIT=1G
hwaro build
```

The CLI `--memory-limit` flag always overrides the environment variable.

Setting either also disables the GC heap presize that `hwaro build` normally applies (`GC_INITIAL_HEAP_SIZE=256M`): a presized heap never shrinks below its floor, which would work against the memory cap you asked for.

### Combined flags

You can combine `--stream` with `--memory-limit`. When `--memory-limit` is provided, it determines the batch size regardless of `--stream`:

```bash
hwaro build --stream --memory-limit 512M
```

## Flag Interaction

| `--stream` | `--memory-limit` | `HWARO_MEMORYLIMIT` | Result |
|---|---|---|---|
| - | - | - | Normal build |
| yes | - | - | Streaming, batch=500 |
| - | 2G | - | Streaming, batch≈20000 |
| - | - | 1G | Streaming, batch≈10000 |
| yes | 512M | - | Streaming, batch≈5000 |
| - | 2G | 1G | CLI wins (2G) |

## How It Works

1. During the Render phase, pages are split into batches
2. Each batch is rendered using the same parallel/sequential logic as a normal build
3. After each batch is written to disk, `page.content` is cleared to free memory —
   but only when nothing downstream reads it back (see below)
4. The garbage collector is invoked to reclaim the released memory
5. After the Generate phase (feeds, sitemap, search index), `page.raw_content` is also cleared

### When `page.content` is kept

The search index and every feed surface read each page's rendered body back
during the Generate phase. Releasing it under them would leave those generators
with a markdown-only re-render of `raw_content` — no shortcode expansion, no
`@/` link resolution, no anchor links, no `base_path` prefix — so `search.json`
and `rss.xml` would carry raw `{% shortcode %}` markup and broken links.

So step 3 is skipped whenever any of these is on:

- `[search] enabled`
- `[feeds] enabled`
- any `[[taxonomies]]` with `feed = true`
- any section with `generate_feeds` in its `_index.md`

With all of them off, batches are released as before. Either way the render
itself still runs in batches, so the per-batch peak (worker template output,
Crinja value caches) stays bounded.

## Output

The build output is **identical** whether streaming is enabled or not. Streaming only affects memory usage during the build process.

> This did not hold on releases up to v0.20.1: on a site with a search index
> or feeds, `--stream` shipped unexpanded shortcodes and unresolved `@/` links
> into `search.json` and every feed. Rebuild such a site once after upgrading.

Use `--verbose` to see batch progress:

```bash
hwaro build --stream --verbose
```

```
Building site...
  Streaming mode enabled (batch size: 500)
  ...
  Streaming batch 1 (500 pages)
  Streaming batch 2 (500 pages)
  Streaming batch 3 (234 pages)
  ...
```

## See Also

- [CLI Reference](/start/cli/) — Full list of build flags
- [Build Hooks](/features/build-hooks/) — Run custom commands before/after builds
