+++
title = "convert"
description = "Convert frontmatter between TOML, YAML, and JSON formats"
weight = 1
+++

Convert frontmatter between TOML, YAML, and JSON formats across your content files.

```bash
# Convert all frontmatter to YAML
hwaro tool convert to-yaml

# Convert all frontmatter to TOML
hwaro tool convert to-toml

# Convert all frontmatter to JSON
hwaro tool convert to-json

# Convert only in a specific directory
hwaro tool convert to-yaml -c posts

# Preview which files would change without touching anything
hwaro tool convert to-yaml --dry-run

# Output result as JSON
hwaro tool convert to-yaml --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Limit conversion to a specific content directory |
| --dry-run | Preview what would be converted without changing any file |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

Conversion rewrites files in place and cannot preserve front-matter comments,
so run `--dry-run` first on a tree you care about: it runs the full
detection/conversion pipeline, including the per-file "dropping N comment
line(s)" warnings, without writing anything back.

## JSON Output

```json
{
  "success": true,
  "message": "Converted 5 files to YAML",
  "converted_count": 5,
  "skipped_count": 2,
  "error_count": 0,
  "dry_run": false
}
```

## Skipped Files

The human summary breaks the skip count down by reason: `already TOML`,
`without front matter`, and `not front matter`:

```
converted: 5 files · 2 skipped (1 already TOML, 1 not front matter)
```

`not front matter` is the one worth reading. It means the file opens with a
`---`/`+++` pair whose contents are prose, not a key/value mapping (a thematic
rule, say). Rewriting it would delete the author's text, so the file is left
untouched and named on stderr.

## Example

Before:

```markdown
+++
title = "My Post"
date = "2024-01-15"
tags = ["crystal", "tutorial"]
+++

Content here.
```

After `hwaro tool convert to-yaml`:

```markdown
---
title: "My Post"
date: "2024-01-15"
tags:
  - crystal
  - tutorial
---

Content here.
```

After `hwaro tool convert to-json`:

```markdown
{
  "title": "My Post",
  "date": "2024-01-15",
  "tags": [
    "crystal",
    "tutorial"
  ]
}

Content here.
```
