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
| drafts | Show only files with `draft = true` |
| published | Show only files with `draft = false` or no draft field |

## JSON Output

```json
[
  {
    "path": "content/blog/my-post.md",
    "title": "My Post",
    "draft": false,
    "date": "2024-06-15T00:00:00+00:00"
  },
  {
    "path": "content/blog/draft-post.md",
    "title": "Draft Post",
    "draft": true,
    "date": "2024-06-10T00:00:00+00:00"
  }
]
```
