+++
title = "urls"
description = "Preview the URLs a build would publish"
weight = 9
+++

List every URL `hwaro build` would publish, without rendering a template or writing a file. Use it to review URL changes before a deploy, or to compare routes between two commits in CI.

The list comes from the build itself: the command runs the build's read, parse and transform phases, then asks the same code that writes each file what it would write. Drafts, future-dated and expired pages, `slug` / `path`, `[permalinks]`, language prefixes, documentation versions, `[[content.generate]]` pages and output-path collisions are all resolved exactly as in a build, and the warnings a build prints about them (a duplicate output path, a refused alias) appear on stderr.

```bash
# One URL per line, sorted
hwaro tool urls

# Include drafts, as `hwaro build --drafts` would
hwaro tool urls --drafts

# Another project directory, with an environment override
hwaro tool urls -i ./site -e production

# URLs with their kind and source file
hwaro tool urls --json
```

## What Is Listed

| Kind | URLs |
|------|------|
| `page` | Content pages, including `[[content.generate]]` pages |
| `section` | Section index pages (`_index.md`) |
| `alias` | Redirect stubs written for `aliases` |
| `pagination` | Pager pages of sections and taxonomy terms (`/posts/page/2/`) |
| `taxonomy` | Taxonomy index pages (`/tags/`) |
| `term` | Taxonomy term pages (`/tags/crystal/`) |
| `feed` | Site, section, language and taxonomy feeds (`/rss.xml`) |

URLs are site-root paths (`/posts/hello/`): the `base_url` and its subpath are not part of them, so the list is the same for every environment that shares the content.

Files that are not routes of their own are left out: static and page-bundle files, `sitemap.xml`, `robots.txt`, `llms.txt`, the search index, `404.html`, `[outputs]` formats and AMP mirrors. `[build] hooks` do not run, so content a `hooks.pre` command generates is only listed once it exists on disk.

## Options

| Flag | Description |
|------|-------------|
| -i, --input DIR | Project directory (default: current directory) |
| -e, --env ENV | Environment name (loads `config.<env>.toml`) |
| -d, --drafts | Include draft content |
| --include-expired | Include expired content |
| --include-future | Include future-dated content |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

`[build] drafts` in `config.toml` applies as it does to a build.

## Example Output

```
/
/about/
/old-about/
/posts/
/posts/hello-world/
/posts/page/2/
/posts/rss.xml
/rss.xml
/tags/
/tags/crystal/
```

## JSON Output

`source` is the content file behind the URL, relative to the project directory. It is `null` for URLs no authored file owns: taxonomy pages, feeds and `[[content.generate]]` pages.

```json
{
  "count": 3,
  "urls": [
    {"url": "/", "kind": "page", "source": "content/index.md"},
    {"url": "/old-about/", "kind": "alias", "source": "content/about.md"},
    {"url": "/tags/", "kind": "taxonomy", "source": null}
  ]
}
```

## Comparing Routes in CI

```bash
# main is checked out beside the pull request, e.g. `git worktree add ../base origin/main`
hwaro tool urls -i ../base > before.txt
hwaro tool urls > after.txt
diff before.txt after.txt
```

A removed line is a URL that stops resolving after the deploy. Add an [alias](/writing/pages/) on the page that moved to keep it alive.
