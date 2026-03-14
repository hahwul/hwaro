+++
title = "doctor"
description = "Diagnose config and content issues"
weight = 4
+++

Diagnose configuration and content issues in your Hwaro site.

```bash
hwaro tool doctor

# Check only a specific content directory
hwaro tool doctor -c posts

# Output result as JSON
hwaro tool doctor --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory to check |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## What It Checks

**Config diagnostics:**

- `base_url` is not set
- `base_url` doesn't start with `http://` or `https://`
- `base_url` has a trailing slash
- `title` is still the default value
- `feeds.enabled` is true but `feeds.filename` is empty
- `sitemap.changefreq` has an invalid value
- `sitemap.priority` is out of range (0.0–1.0)
- Duplicate taxonomy names
- Duplicate language codes
- Invalid `search.format` value

**Template diagnostics:**

- Templates directory not found
- Required templates missing (`page.html`, `section.html`)
- Unclosed block tags (`if`, `for`, `block`, `macro` without matching `end`)
- Mismatched `{{ }}` variable tags

**Content diagnostics:**

- Missing `title` in frontmatter
- Missing `description` in frontmatter
- Images without alt text (`![](url)`)
- Broken internal links (`@/` prefixed paths that don't resolve)
- Frontmatter parse errors (TOML/YAML)
- Draft files (reported as info)

**Structure diagnostics:**

- Section directories missing `_index.md`

## Example Output

```
Running diagnostics...

Config:
  ⚠ config.toml: base_url is not set
  ⚠ config.toml: feeds.enabled is true but feeds.filename is not set

Content:
  ⚠ content/blog/draft.md: Missing description in frontmatter
  ℹ content/blog/draft.md: File is marked as draft
  ⚠ content/about.md: Image missing alt text: ![](photo.jpg)

Found 0 error(s), 3 warning(s), 1 info(s)
```

## JSON Output

```json
{
  "issues": [
    {
      "level": "warning",
      "category": "config",
      "file": "config.toml",
      "message": "base_url is not set"
    },
    {
      "level": "warning",
      "category": "content",
      "file": "content/blog/draft.md",
      "message": "Missing description in frontmatter"
    },
    {
      "level": "info",
      "category": "content",
      "file": "content/blog/draft.md",
      "message": "File is marked as draft"
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 2,
    "infos": 1,
    "total": 3
  }
}
```
