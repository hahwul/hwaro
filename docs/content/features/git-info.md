+++
title = "Git Metadata"
description = "Expose each page's commit history as page.git and derive lastmod from it"
weight = 12
+++

Read each content file's commit history once per build and expose it to templates and SEO outputs, like Hugo's `enableGitInfo`. With `[git]` enabled, a page that has no `updated` in its front matter gets one from its latest commit, so sitemap `<lastmod>`, feed `<updated>`, and JSON-LD `dateModified` reflect when the file really changed.

## Configuration

Opt in via `config.toml`:

```toml
[git]
enabled = true
use_lastmod = true   # page.updated ← latest commit when front matter has none
use_date = false     # page.date ← first commit when front matter has none
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Collect git metadata for `content/` files |
| use_lastmod | bool | true | Set `page.updated` from the file's latest commit when front matter has no `updated` |
| use_date | bool | false | Set `page.date` from the file's first commit when front matter has no `date` |

Front matter always wins: a fallback only fills a field the file left unset.

## How It Works

1. The build runs **one** `git log` over `content/` (never one process per page) and maps every path to its commits. On a 5,200-page test repository the whole collection step took about 50 ms.
2. Each page whose source file has at least one non-merge commit gets a `page.git` object.
3. `use_lastmod` / `use_date` fill the missing `updated` / `date` fields, after which everything downstream (sitemap, feeds, JSON-LD, OpenGraph, `sort_by = "date"`) sees the git-derived value with no template changes.

`hwaro serve` collects history once per full rebuild, not on every file save. `hwaro build --cache` folds each page's commit id and timestamps into its cache key, so a warm rebuild after a new commit re-renders exactly the pages that commit touched (and the listings that show them).

## Template Variable

| Variable | Type | Description |
|----------|------|-------------|
| page.git | Object? | `nil` when the page has no history (see below) |
| page.git.hash | String | Full commit id of the latest non-merge commit that touched the file |
| page.git.short_hash | String | First 7 characters of `hash` |
| page.git.lastmod | Time | Author date of that latest commit |
| page.git.first_commit | Time | Earliest author date across every commit that touched the file |
| page.git.author_name | String | Author name of the latest commit |
| page.git.author_email | String | Author email of the latest commit |

`lastmod` and `first_commit` are real time values (the author's UTC offset is preserved), so the `date` filter formats them directly. The same object is available on pages iterated from listings (`section.pages`, `site.pages`, taxonomy terms).

```jinja
{% if page.git %}
<p class="meta">
  Last updated {{ page.git.lastmod | date(format="%B %d, %Y") }}
  by {{ page.git.author_name }}
  (<a href="https://github.com/you/site/commit/{{ page.git.hash }}">{{ page.git.short_hash }}</a>)
</p>
{% endif %}
```

`page.git` is `nil`, and no fallback applies, for:

- files that are not committed yet (new or untracked),
- pages materialized from `[[content.generate]]`,
- generated taxonomy and listing pages,
- every page when the site is not inside a git repository.

## Bundles, Translations, Renames

- A page bundle (`posts/hello/index.md` + assets) is keyed by its Markdown file, so committing only an asset does not move `lastmod`.
- Each translation (`hello.md`, `hello.ko.md`) is its own file with its own history.
- Renames are **not** followed: a renamed file's history restarts at the rename commit, so `first_commit` (and `page.date` under `use_date`) is the rename date.

## Graceful Degradation

The feature never aborts a build. Each of these produces a single warning and leaves `page.git` unset:

| Situation | Effect |
|-----------|--------|
| No `git` binary on `PATH` | Warning; no git metadata |
| `content/` is not inside a repository | Warning; no git metadata |
| Shallow clone (`--depth N`) | Warning that `lastmod`/`first_commit` may be wrong for files older than the clone depth; metadata is still used |

Most CI checkouts are shallow by default. Fetch the full history so dates are correct:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

## See Also

- [Data Model](/templates/data-model/) — the full `page` object
- [SEO](/features/seo/) and [Structured Data](/features/structured-data/) — where `page.updated` is emitted
- [Incremental Build](/features/incremental-build/) — how `--cache` decides what to re-render
