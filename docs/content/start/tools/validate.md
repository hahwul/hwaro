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
- Frontmatter parse errors (TOML/YAML/JSON)
- Invalid date formats
- Mixed-case tags (e.g., `Crystal` instead of `crystal`)
- Draft files (reported as info)

## Example Output

```
hwaro: validate content

content/blog/draft.md:
      [warn] Missing description in frontmatter
      [info] File is marked as draft

content/about.md:
      [warn] Image missing alt text: ![](photo.jpg)
      [info] Tag has mixed case: "Crystal" (consider lowercase)

checked: 0 errors, 2 warnings, 2 info
```

In a color terminal the findings use `⚠`/`✗`/`ℹ` glyphs under an `hwaro validate`
heading, and the closing line is a severity-colored `✦ checked` outcome. The
command exits non-zero when error-level issues are found, so it can gate CI.

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
| `content-frontmatter-json-error` | error | JSON frontmatter parse error |
| `content-read-error` | error | Failed to read content file |
| `content-tag-mixed-case` | info | Tag has mixed case |
| `content-draft` | info | File marked as draft |

## JSON Output

```json
{
  "findings": [
    {
      "file": "content/blog/draft.md",
      "line": null,
      "rule": "content-description-missing",
      "severity": "warning",
      "message": "Missing description in frontmatter"
    }
  ]
}
```
