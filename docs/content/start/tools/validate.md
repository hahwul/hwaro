+++
title = "validate"
description = "Validate content frontmatter and markup"
weight = 8
+++

Validate content files for frontmatter completeness, accessibility, and structural correctness.

```bash
# Validate all content files
hwaro tool validate

# Validate a specific content directory
hwaro tool validate -c posts

# Output as JSON
hwaro tool validate --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory (default: content) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## What It Checks

- Missing `title` in frontmatter
- Missing `description` in frontmatter
- Images without alt text (`![](url)`)
- Broken internal links (`@/` prefixed paths that don't resolve)
- Frontmatter parse errors (TOML/YAML)
- Invalid date formats
- Mixed-case tags (e.g., `Crystal` instead of `crystal`)
- Draft files (reported as info)

## Example Output

```
Validating content in 'content'...

  content/blog/draft.md:
    ⚠ Missing description in frontmatter
    ℹ File is marked as draft

  content/about.md:
    ⚠ Image missing alt text: ![](photo.jpg)
    ℹ Tag has mixed case: "Crystal" (consider lowercase)

Found 0 error(s), 2 warning(s), 2 info(s)
```

## Rule IDs

| ID | Level | Description |
|----|-------|-------------|
| `content-title-missing` | warning | Missing or "Untitled" title |
| `content-description-missing` | warning | Missing description |
| `content-alt-text-missing` | warning | Image without alt text |
| `content-internal-link-broken` | warning | Broken `@/` internal link |
| `content-date-invalid` | warning | Unrecognized date format |
| `content-frontmatter-toml-error` | error | TOML frontmatter parse error |
| `content-frontmatter-yaml-error` | error | YAML frontmatter parse error |
| `content-read-error` | error | Failed to read content file |
| `content-tag-mixed-case` | info | Tag has mixed case |
| `content-draft` | info | File marked as draft |

## JSON Output

```json
{
  "issues": [
    {
      "id": "content-description-missing",
      "level": "warning",
      "category": "content",
      "file": "content/blog/draft.md",
      "message": "Missing description in frontmatter"
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 1,
    "infos": 0,
    "total": 1
  }
}
```
