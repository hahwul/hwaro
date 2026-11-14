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
hwaro tool convert to-yaml -c content/posts

# Preview which files would change without touching anything
hwaro tool convert to-yaml --dry-run

# Output result as JSON
hwaro tool convert to-yaml --json
```

The command accepts one format argument (`to-yaml`, `to-toml`, or `to-json`).
Extra positional arguments are rejected; use flags such as `--content-dir` for
additional options.

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

TOML has no null, so `to-toml` writes a null YAML/JSON value in whichever
form the build reads the same way. For built-in keys such as `title`,
`description`, `slug`, `image` and `date` (`description:` with nothing after
it, `slug: ~`, `"image": null`) the key is omitted, since an empty string
would set an empty title or slug. Keys a section's `[cascade]` can set
(`draft`, `tags`, `template`, ...), `extra` values and custom keys become `""`:
a null there still declares the key, so it keeps blocking the cascade, and the
build already reads a null custom value as an empty string.

## Values that change type

The three formats do not share a type system, so a conversion can change a
value's type while keeping its text. Nothing is silently dropped, but these
mappings are lossy:

- Dates and datetimes are written as date strings (`date = "2024-01-15"`),
  which is how the build reads them. A re-read with another tool sees a string,
  not a native date.
- TOML arrays that mix types, and nested tables inside such arrays, are written
  as strings (`[1, "a", true]` becomes `["1", "a", "true"]`) because the bundled
  TOML writer requires uniform arrays. `-9223372036854775808` (the smallest
  64-bit integer) is written as a quoted string for the same reason.
- `inf`/`nan` have no JSON spelling: `to-json` refuses such a file and names it.
- Keys that are not plain words (digits first, a leading `-`, `inf`, `nan`,
  spaces, dots) are quoted in TOML, and an unquoted YAML date key
  (`2024-01-01: v`) becomes the string key `"2024-01-01"`.
- A leading UTF-8 BOM is dropped.

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

A run that fails before reading any file (a missing content directory) prints
the standard error envelope
(`{"status": "error", "error": {"code", "category", "message", "hint"}}`)
instead. When individual files fail, the payload above is printed with
`"success": false` and an `error_count` above zero. Both exit non-zero, with
the same code as the human output.

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
title: My Post
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
