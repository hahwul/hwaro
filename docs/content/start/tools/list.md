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

# Output result as JSON
hwaro tool list all --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit listing to a specific content directory |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

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
