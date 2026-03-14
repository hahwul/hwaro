+++
title = "convert"
description = "Convert frontmatter between YAML and TOML formats"
weight = 1
+++

Convert frontmatter between YAML and TOML formats across your content files.

```bash
# Convert all frontmatter to YAML
hwaro tool convert toYAML

# Convert all frontmatter to TOML
hwaro tool convert toTOML

# Convert only in a specific directory
hwaro tool convert toYAML -c posts

# Output result as JSON
hwaro tool convert toYAML --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit conversion to a specific content directory |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## JSON Output

```json
{
  "success": true,
  "message": "Converted 5 files to YAML",
  "converted_count": 5,
  "skipped_count": 2,
  "error_count": 0
}
```

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

After `hwaro tool convert toYAML`:

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
