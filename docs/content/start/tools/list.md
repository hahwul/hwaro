+++
title = "list"
description = "List content files by status"
weight = 2
+++

List content files filtered by status.

```bash
# List all content files
hwaro tool list all

# List only draft files
hwaro tool list drafts

# List only published files
hwaro tool list published

# List files in a specific directory
hwaro tool list all -c posts

# The 5 newest published files
hwaro tool list published --limit 5

# Sort by title (A→Z), or reverse any ordering
hwaro tool list all --sort title
hwaro tool list all --sort path --reverse

# Output result as JSON
hwaro tool list all --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Limit listing to a specific content directory |
| --sort KEY | Sort key: `date` (newest first, default), `title`, or `path` |
| -r, --reverse | Reverse the sort order |
| -n, --limit N | Show at most N files (applied after sorting) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

`--limit` caps the result after sorting, so `--sort date --limit 5` means
"the 5 newest files", and `--sort date --reverse --limit 5` the 5 oldest.
`--sort title` uses the same case-sensitive ordering as the template
engine's `sort_by="title"`, so the CLI listing matches a rendered section
index.

The filter argument also accepts the shorthands `draft` (for `drafts`) and
`pub` (for `published`).

## Filters

| Filter | Description |
|--------|-------------|
| all | Show all content files |
| drafts | Show only drafts — `draft = true`, or a `draft` cascaded from a parent section |
| published | Show only the files a default `hwaro build` actually publishes |

`published` means what the build ships, not merely "not flagged draft". A
default build also drops future-dated pages (`date` in the future) and expired
ones (`expires` in the past), so those are reported separately:

| Status | Meaning |
|--------|---------|
| `[pub]` | Published by a default build |
| `[draft]` | `draft = true`, own or cascaded |
| `[future]` | `date` is in the future (build it with `--include-future`) |
| `[expired]` | `expires` has passed (build it with `--include-expired`) |

## JSON Output

```json
[
  {
    "path": "content/blog/my-post.md",
    "title": "My Post",
    "draft": false,
    "date": "2024-06-15T00:00:00+00:00",
    "status": "published",
    "expires": null
  },
  {
    "path": "content/blog/draft-post.md",
    "title": "Draft Post",
    "draft": true,
    "date": "2024-06-10T00:00:00+00:00",
    "status": "draft",
    "expires": null
  }
]
```

`status` is `published`, `draft`, `future` or `expired`. `draft` is kept for
existing consumers and is true only for actual drafts.
