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
Content statistics for 'content':

  Overview:
    Total:     42
    Published: 38
    Drafts:    4

  Word Count:
    Total:   28500
    Average: 678
    Min:     120
    Max:     3200

  Tags (top 15):
    crystal              12 ████████████
    web                   8 ████████
    tutorial              5 █████
    ... and 7 more

  Monthly Publishing:
    2024-01   3 ███
    2024-02   5 █████
    2024-03   2 ██
```

## JSON Output

```json
{
  "total": 42,
  "drafts": 4,
  "published": 38,
  "words_total": 28500,
  "words_avg": 678,
  "words_min": 120,
  "words_max": 3200,
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
