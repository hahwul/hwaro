+++
title = "stats"
description = "Show content statistics"
weight = 7
+++

Show content statistics including post counts, word count metrics, tag distribution, and monthly publishing frequency.

```bash
# Show statistics for content directory
hwaro tool stats

# Use a custom content directory
hwaro tool stats -c posts

# Output as JSON
hwaro tool stats --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory (default: content) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## Example Output

```
hwaro: stats content
total: 42 files, 4 drafts
words: 28,500 total, 678 avg
range: 120 min, 3,200 max

tags:
      crystal     12  ####################
      web          8  #############
      tutorial     5  ########

monthly:
      2024-01      3  ############
      2024-02      5  ####################
      2024-03      2  ########

counted: 42 files, 38 published, 4 drafts
```

In a color terminal the same report renders as an `hwaro stats` heading, aligned
receipt rows, proportional bar charts, and a `✦ counted` outcome line. When
there are more than 15 tags, only the top 15 are charted (`tags: top 15`).

## JSON Output

```json
{
  "total": 42,
  "published": 38,
  "drafts": 4,
  "word_count": {
    "total": 28500,
    "average": 678,
    "min": 120,
    "max": 3200
  },
  "tags": {
    "crystal": 12,
    "web": 8,
    "tutorial": 5
  },
  "monthly": {
    "2024-01": 3,
    "2024-02": 5,
    "2024-03": 2
  }
}
```
