+++
title = "stats"
description = "Show content statistics"
weight = 7
+++

Show content statistics including post counts, word count metrics, tag distribution, and monthly publishing frequency.

`published` counts what a default `hwaro build` actually ships, so files it
drops are reported under their own reason — `drafts` (own or cascaded from a
parent section), `future` (`date` in the future) and `expired` (`expires` in
the past). Word counts, the tag distribution and the monthly chart cover the
published set only. Tags are read from a top-level `tags` list or, when that is
absent, from the `[taxonomies] tags` table — the same fallback the build uses.

```bash
# Show statistics for content directory
hwaro tool stats

# Use a custom content directory
hwaro tool stats -c posts

# Chart the top 30 tags instead of the default 15
hwaro tool stats --top 30

# Output as JSON
hwaro tool stats --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Content directory (default: content) |
| --top N | Show the top N tags in the chart (default: 15) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## Example Output

```
hwaro: stats content
total: 42 files, 4 drafts · 1 future
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

counted: 42 files, 37 published, 4 drafts · 1 future
```

In a color terminal the same report renders as an `hwaro stats` heading, aligned
receipt rows, proportional bar charts, and a `✦ counted` outcome line. When
there are more tags than the chart budget, only the top N are charted
(`tags: top 15` by default — raise or lower it with `--top N`). The JSON
output always contains every tag regardless of `--top`.

## JSON Output

```json
{
  "total": 42,
  "published": 37,
  "drafts": 4,
  "future": 1,
  "expired": 0,
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
